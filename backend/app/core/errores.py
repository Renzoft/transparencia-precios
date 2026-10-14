"""Errores de la API con el formato que fija el contrato.

openapi.yaml define un único cuerpo de error para toda la API:

    {"error": {"codigo": "...", "mensaje": "...", "detalles": [...]}}

«codigo» es estable y lo compara la aplicación; «mensaje» es el texto que se muestra al
usuario. Los servicios lanzan ErrorAPI y este módulo lo convierte en esa respuesta.
"""
from fastapi import Request
from fastapi.responses import JSONResponse


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


async def manejar_error_api(_: Request, exc: ErrorAPI) -> JSONResponse:
    cabeceras = None
    if exc.estado == 401:
        # Lo exige el estándar HTTP para 401: indica qué esquema de autenticación usar.
        cabeceras = {"WWW-Authenticate": "Bearer"}
    return JSONResponse(cuerpo_error(exc.codigo, exc.mensaje, exc.detalles),
                        status_code=exc.estado, headers=cabeceras)
