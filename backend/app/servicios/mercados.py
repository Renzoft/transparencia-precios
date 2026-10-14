"""Mercados minoristas (CU02, R4; RN11).

Un mercado no se borra nunca: se desactiva. Desactivado, deja de mostrarse al
consumidor pero conserva su historial de precios (RN11, AD12).
"""
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errores import ErrorAPI
from app.esquemas.mercado import Mercado as MercadoSalida
from app.esquemas.mercado import MercadoActualizar, MercadoCrear
from app.modelos import Mercado
from app.servicios.texto import normalizar

# Rectángulo que contiene Lima Metropolitana y el Callao, de Ancón a Pucusana y de
# la isla San Lorenzo a Chosica. No es el contorno exacto de Lima: sirve para atrapar
# los errores de tipeo que de verdad ocurren al copiar coordenadas —latitud y longitud
# intercambiadas, un signo olvidado—, que llevarían el mercado a otro continente.
LATITUD = (-12.55, -11.55)
LONGITUD = (-77.25, -76.55)

MENSAJE_FUERA_DE_LIMA = "Las coordenadas no corresponden a Lima Metropolitana"   # EX2
MENSAJE_REPETIDO = "El mercado ya se encuentra registrado"                       # EX3


def _a_salida(m: Mercado) -> MercadoSalida:
    return MercadoSalida(
        id_mercado=m.id_mercado, nombre=m.nombre, distrito=m.distrito,
        direccion=m.direccion, latitud=float(m.latitud), longitud=float(m.longitud),
        horario_atencion=m.horario_atencion, activo=m.activo)


def _validar_lima(latitud: float, longitud: float) -> None:
    problemas = []
    if not LATITUD[0] <= latitud <= LATITUD[1]:
        problemas.append({"campo": "latitud",
                          "problema": "debe estar entre %s y %s" % LATITUD})
    if not LONGITUD[0] <= longitud <= LONGITUD[1]:
        problemas.append({"campo": "longitud",
                          "problema": "debe estar entre %s y %s" % LONGITUD})
    if not problemas:
        return
    # El error más común: copiar las dos coordenadas en el orden contrario.
    if LATITUD[0] <= longitud <= LATITUD[1] and LONGITUD[0] <= latitud <= LONGITUD[1]:
        problemas = [{"campo": "latitud",
                      "problema": "parece estar intercambiada con la longitud"}]
    raise ErrorAPI(422, "COORDENADAS_FUERA_DE_LIMA", MENSAJE_FUERA_DE_LIMA, problemas)


def _buscar_repetido(sesion: Session, nombre: str, distrito: str,
                     excepto: int | None = None) -> Mercado | None:
    # Se compara sin tildes ni mayúsculas: «Mercado de magdalena» y «Mercado de
    # Magdalena» son el mismo mercado aunque la base los vería distintos.
    clave = (normalizar(nombre), normalizar(distrito))
    for m in sesion.scalars(select(Mercado)):
        if m.id_mercado != excepto and (normalizar(m.nombre), normalizar(m.distrito)) == clave:
            return m
    return None


def _repetido(existente: Mercado) -> ErrorAPI:
    estado = "activo" if existente.activo else "desactivado"
    return ErrorAPI(409, "MERCADO_YA_REGISTRADO", MENSAJE_REPETIDO, [
        {"campo": "nombre",
         "problema": "ya existe «%s» en %s (mercado %d, %s)" % (
             existente.nombre, existente.distrito, existente.id_mercado, estado)}])


def _guardar(sesion: Session, mercado: Mercado) -> None:
    try:
        sesion.flush()
    except IntegrityError:
        # Otra petición registró el mismo mercado entre la consulta y el guardado.
        sesion.rollback()
        repetido = _buscar_repetido(sesion, mercado.nombre, mercado.distrito)
        raise _repetido(repetido) if repetido else ErrorAPI(
            409, "MERCADO_YA_REGISTRADO", MENSAJE_REPETIDO) from None


# --------------------------------------------------------------------- consultas
def listar(sesion: Session, distrito: str | None, incluir_inactivos: bool) -> list[MercadoSalida]:
    consulta = select(Mercado).order_by(Mercado.nombre)
    if not incluir_inactivos:
        consulta = consulta.where(Mercado.activo)
    mercados = list(sesion.scalars(consulta))
    if distrito:
        buscado = normalizar(distrito)
        mercados = [m for m in mercados if normalizar(m.distrito) == buscado]
    return [_a_salida(m) for m in mercados]


def obtener(sesion: Session, id_mercado: int, es_admin: bool) -> MercadoSalida:
    m = sesion.get(Mercado, id_mercado)
    # Para el consumidor, un mercado desactivado no existe (RN11).
    if m is None or (not m.activo and not es_admin):
        raise ErrorAPI(404, "MERCADO_NO_ENCONTRADO", "No existe el mercado %d." % id_mercado)
    return _a_salida(m)


# ---------------------------------------------------------------- registro y edición
def crear(sesion: Session, datos: MercadoCrear) -> MercadoSalida:
    _validar_lima(datos.latitud, datos.longitud)
    repetido = _buscar_repetido(sesion, datos.nombre, datos.distrito)
    if repetido:
        raise _repetido(repetido)
    m = Mercado(nombre=datos.nombre, distrito=datos.distrito, direccion=datos.direccion,
                latitud=round(datos.latitud, 6), longitud=round(datos.longitud, 6),
                horario_atencion=datos.horario_atencion or None)
    sesion.add(m)
    _guardar(sesion, m)
    return _a_salida(m)


def actualizar(sesion: Session, id_mercado: int, datos: MercadoActualizar) -> MercadoSalida:
    m = sesion.get(Mercado, id_mercado)
    if m is None:
        raise ErrorAPI(404, "MERCADO_NO_ENCONTRADO", "No existe el mercado %d." % id_mercado)
    cambios = datos.model_dump(exclude_unset=True)

    # Las coordenadas se validan juntas: cambiar solo la latitud se comprueba con la
    # longitud que ya tenía el mercado.
    if "latitud" in cambios or "longitud" in cambios:
        _validar_lima(cambios.get("latitud", float(m.latitud)),
                      cambios.get("longitud", float(m.longitud)))
    if "nombre" in cambios or "distrito" in cambios:
        repetido = _buscar_repetido(sesion, cambios.get("nombre", m.nombre),
                                    cambios.get("distrito", m.distrito), excepto=id_mercado)
        if repetido:
            raise _repetido(repetido)

    for campo, valor in cambios.items():
        if campo in ("latitud", "longitud"):
            valor = round(valor, 6)
        elif campo == "horario_atencion":
            valor = valor or None
        setattr(m, campo, valor)
    _guardar(sesion, m)
    return _a_salida(m)
