"""Errores de la API con el formato que fija el contrato.

openapi.yaml define un único cuerpo de error para toda la API:

    {"error": {"codigo": "...", "mensaje": "...", "detalles": [...]}}

«codigo» es estable y lo compara la aplicación; «mensaje» es el texto que se muestra al
usuario; «detalles» aparece solo cuando el error se refiere a campos concretos
(Especificación de Endpoints, sección 5).

Aquí se convierten a ese formato los cuatro orígenes de error posibles:

  ErrorAPI                los que lanzan los servicios a propósito
  RequestValidationError  datos que no cumplen el esquema: 400 o 422
  HTTPException           rutas inexistentes, métodos no admitidos
  Exception               cualquier falla no prevista: 500 sin detalles internos
"""
import logging

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

registro = logging.getLogger("transparencia_precios")


class ErrorAPI(Exception):
    def __init__(self, estado: int, codigo: str, mensaje: str,
                 detalles: list[dict] | None = None):
        super().__init__(mensaje)
        self.estado = estado
        self.codigo = codigo
        self.mensaje = mensaje
        self.detalles = detalles


def cuerpo_error(codigo: str, mensaje: str, detalles: list[dict] | None = None) -> dict:
    error = {"codigo": codigo, "mensaje": mensaje}
    if detalles:
        error["detalles"] = detalles
    return {"error": error}


def respuesta_error(estado: int, codigo: str, mensaje: str,
                    detalles: list[dict] | None = None,
                    cabeceras: dict | None = None) -> JSONResponse:
    if estado == 401:
        # Lo exige el estándar HTTP para 401: indica qué esquema de autenticación usar.
        cabeceras = {**(cabeceras or {}), "WWW-Authenticate": "Bearer"}
    return JSONResponse(cuerpo_error(codigo, mensaje, detalles), status_code=estado,
                        headers=cabeceras)


# ---------------------------------------------------------------- errores propios
async def manejar_error_api(_: Request, exc: ErrorAPI) -> JSONResponse:
    return respuesta_error(exc.estado, exc.codigo, exc.mensaje, exc.detalles)


# ------------------------------------------------------------ validación de datos
# Traducción de los tipos de error de Pydantic. Los mensajes van al consumidor y al
# administrador, que leen español. Lo que no esté aquí cae en un texto genérico.
def _problema(e: dict) -> str:
    tipo, ctx = e.get("type", ""), e.get("ctx") or {}
    traducciones = {
        "missing": "es obligatorio",
        "string_too_short": "debe tener al menos {min_length} caracteres",
        "string_too_long": "no puede tener más de {max_length} caracteres",
        "too_short": "debe tener al menos {min_length} elementos",
        "too_long": "no puede tener más de {max_length} elementos",
        "string_type": "debe ser texto",
        "int_type": "debe ser un número entero",
        "int_parsing": "debe ser un número entero",
        "int_from_float": "debe ser un número entero",
        "float_type": "debe ser un número",
        "float_parsing": "debe ser un número",
        "decimal_parsing": "debe ser un número",
        "bool_type": "debe ser verdadero o falso",
        "bool_parsing": "debe ser verdadero o falso",
        "date_type": "debe ser una fecha (AAAA-MM-DD)",
        "date_parsing": "debe ser una fecha (AAAA-MM-DD)",
        "date_from_datetime_parsing": "debe ser una fecha (AAAA-MM-DD)",
        "datetime_type": "debe ser una fecha y hora",
        "datetime_parsing": "debe ser una fecha y hora",
        "greater_than": "debe ser mayor que {gt}",
        "greater_than_equal": "debe ser mayor o igual que {ge}",
        "less_than": "debe ser menor que {lt}",
        "less_than_equal": "debe ser menor o igual que {le}",
        "literal_error": "debe ser uno de: {expected}",
        "enum": "debe ser uno de: {expected}",
        "extra_forbidden": "no se admite este campo",
        "dict_type": "debe ser un objeto",
        "list_type": "debe ser una lista",
    }
    if tipo == "value_error" and "email" in e.get("msg", "").lower():
        return "no es un correo electrónico válido"
    plantilla = traducciones.get(tipo)
    if plantilla is None:
        return "no es un valor válido"
    try:
        return plantilla.format(**ctx)
    except (KeyError, IndexError):
        return plantilla.split(" {")[0]


def _campo(loc: tuple) -> str:
    # ("body", "correo") -> "correo"; ("query", "desde") -> "desde"; ("body",) -> "cuerpo"
    partes = [str(p) for p in loc[1:]] if loc and loc[0] in ("body", "query", "path",
                                                             "header", "cookie") else \
             [str(p) for p in loc]
    return ".".join(partes) or "cuerpo"


async def manejar_validacion(_: Request, exc: RequestValidationError) -> JSONResponse:
    errores = exc.errors()

    # 400: el cuerpo ni siquiera es JSON legible. No hay campos de los que hablar.
    if any(e.get("type") == "json_invalid" for e in errores):
        return respuesta_error(400, "PETICION_MALFORMADA",
                               "La petición no se pudo interpretar. Revisa que el "
                               "cuerpo sea un JSON válido.")

    # 422: se leyó bien, pero hay campos que no cumplen. Se arma la lista sin el valor
    # recibido: FastAPI lo incluye por defecto, y eso devolvería —y dejaría en los
    # registros— una contraseña o cualquier otro dato que el usuario haya escrito.
    detalles = [{"campo": _campo(tuple(e.get("loc", ()))), "problema": _problema(e)}
                for e in errores]
    return respuesta_error(422, "DATOS_NO_VALIDOS",
                           "Hay datos que no son válidos. Revisa los campos indicados.",
                           detalles)


# ------------------------------------------------------------ errores del protocolo
_HTTP = {
    404: ("RECURSO_NO_ENCONTRADO", "El recurso solicitado no existe."),
    405: ("METODO_NO_PERMITIDO", "Esta operación no está disponible para el recurso."),
    413: ("CONTENIDO_DEMASIADO_GRANDE", "El contenido enviado supera el tamaño permitido."),
    415: ("TIPO_NO_ADMITIDO", "El tipo de contenido enviado no está admitido."),
}


async def manejar_http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    codigo, mensaje = _HTTP.get(exc.status_code,
                                ("ERROR_HTTP", "La petición no se pudo completar."))
    # Se conservan las cabeceras del error original: en un 405, «Allow» le dice al
    # cliente qué métodos sí puede usar.
    return respuesta_error(exc.status_code, codigo, mensaje,
                           cabeceras=getattr(exc, "headers", None))


# ---------------------------------------------------------------- fallas previstas no
async def manejar_inesperado(request: Request, exc: Exception) -> JSONResponse:
    # El detalle completo va al registro del servidor, donde lo puede leer el tesista.
    # Al cliente no: una traza de error revela rutas, versiones y consultas.
    registro.exception("Error no controlado en %s %s", request.method, request.url.path)
    return respuesta_error(500, "ERROR_INTERNO",
                           "Ocurrió un error inesperado. Inténtalo de nuevo en unos "
                           "minutos.")


def registrar_manejadores(app) -> None:
    app.add_exception_handler(ErrorAPI, manejar_error_api)
    app.add_exception_handler(RequestValidationError, manejar_validacion)
    app.add_exception_handler(StarletteHTTPException, manejar_http)
    app.add_exception_handler(Exception, manejar_inesperado)
