"""Modos de desplazamiento y tarifas (CU02, R5; RN07; AD13).

Una tarifa no se edita: se registra una nueva vigencia y la anterior se cierra en la
misma transacción. Así, el monto con que se calculó una comparación pasada sigue en la
base (AD13).

Reglas que aplica este módulo, además de las del esquema:

  - El desplazamiento a pie cuesta cero (RN07) y su tarifa no se modifica.
  - Cada modo tiene un solo tipo de cobro (R5): el transporte público cobra un pasaje
    fijo; el taxi y el auto particular, por kilómetro.
  - Una vigencia no puede empezar en el pasado: cambiaría el monto de un día que ya
    pasó.
  - Una vigencia nueva debe empezar después de la que está abierta. Si empezara el mismo
    día, la abierta quedaría con cero días de vigencia; si empezara antes, se solaparía.
"""
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errores import ErrorAPI
from app.esquemas.tarifa import ModoDesplazamiento as ModoSalida
from app.esquemas.tarifa import Tarifa as TarifaSalida
from app.esquemas.tarifa import TarifaCrear
from app.modelos import ModoDesplazamiento, Tarifa

# Hora de Lima. El Perú no cambia de hora en verano, así que basta el desfase fijo.
LIMA = timezone(timedelta(hours=-5))

TIPO_POR_MODO = {"transporte público": "fijo", "taxi": "por_km", "auto particular": "por_km"}

MENSAJE_SOLAPADA = "Ya existe una tarifa vigente para ese modo en esa fecha."


def hoy() -> date:
    return datetime.now(LIMA).date()


def _a_salida(t: Tarifa, **extra) -> TarifaSalida:
    return TarifaSalida(
        id_tarifa=t.id_tarifa, id_modo_desplazamiento=t.id_modo_desplazamiento,
        tipo_cobro=t.tipo_cobro, monto=float(t.monto), vigente_desde=t.vigente_desde,
        vigente_hasta=t.vigente_hasta, **extra)


def _no_valido(codigo: str, mensaje: str, campo: str, problema: str) -> ErrorAPI:
    return ErrorAPI(422, codigo, mensaje, [{"campo": campo, "problema": problema}])


# --------------------------------------------------------------------- consultas
def listar_modos(sesion: Session) -> list[ModoSalida]:
    modos = sesion.scalars(select(ModoDesplazamiento).where(ModoDesplazamiento.activo)
                           .order_by(ModoDesplazamiento.id_modo_desplazamiento))
    return [ModoSalida(id_modo_desplazamiento=m.id_modo_desplazamiento, nombre=m.nombre,
                       activo=m.activo) for m in modos]


def listar(sesion: Session, vigentes: bool) -> list[TarifaSalida]:
    consulta = select(Tarifa).order_by(Tarifa.id_modo_desplazamiento,
                                       Tarifa.vigente_desde.desc())
    if vigentes:
        # Las que rigen hoy. Una tarifa programada para una fecha futura todavía no rige,
        # y la que la precede sigue rigiendo aunque ya tenga fecha de cierre.
        h = hoy()
        consulta = consulta.where(Tarifa.vigente_desde <= h,
                                  or_(Tarifa.vigente_hasta.is_(None), Tarifa.vigente_hasta > h))
    return [_a_salida(t) for t in sesion.scalars(consulta)]


# ------------------------------------------------------------------------ registro
def crear(sesion: Session, datos: TarifaCrear) -> TarifaSalida:
    modo = sesion.get(ModoDesplazamiento, datos.id_modo_desplazamiento)
    if modo is None or not modo.activo:
        raise _no_valido("MODO_NO_VALIDO", "El modo de desplazamiento no existe o no está "
                         "activo.", "id_modo_desplazamiento", "no es un modo activo")
    if modo.nombre not in TIPO_POR_MODO:
        raise _no_valido("TARIFA_NO_MODIFICABLE", "El desplazamiento a pie no tiene costo.",
                         "id_modo_desplazamiento", "su tarifa es siempre cero (RN07)")
    esperado = TIPO_POR_MODO[modo.nombre]
    if datos.tipo_cobro != esperado:
        raise _no_valido("TIPO_COBRO_NO_CORRESPONDE",
                         "El tipo de cobro no corresponde al modo de desplazamiento.",
                         "tipo_cobro", "para %s debe ser «%s»" % (modo.nombre, esperado))
    # Céntimos: 2.505 soles no es un monto que se pueda cobrar ni guardar.
    if abs(datos.monto * 100 - round(datos.monto * 100)) > 1e-6:
        raise _no_valido("DATOS_NO_VALIDOS",
                         "Hay datos que no son válidos. Revisa los campos indicados.",
                         "monto", "no puede tener más de 2 decimales")
    if datos.vigente_desde < hoy():
        raise _no_valido("FECHA_NO_VALIDA", "Una tarifa no puede regir desde una fecha "
                         "pasada.", "vigente_desde",
                         "no puede ser anterior a hoy (%s)" % hoy().isoformat())

    # La tarifa abierta del modo, bloqueada hasta el final de la transacción: si dos
    # administradores guardan a la vez, el segundo espera y luego ve la del primero.
    abierta = sesion.scalars(
        select(Tarifa).where(Tarifa.id_modo_desplazamiento == modo.id_modo_desplazamiento,
                             Tarifa.vigente_hasta.is_(None)).with_for_update()).first()
    if abierta is not None and datos.vigente_desde <= abierta.vigente_desde:
        raise ErrorAPI(409, "TARIFA_SOLAPADA", MENSAJE_SOLAPADA, [
            {"campo": "vigente_desde", "problema": "se solapa con la tarifa %d, vigente "
             "desde %s" % (abierta.id_tarifa, abierta.vigente_desde.isoformat())}])

    if abierta is not None:
        abierta.vigente_hasta = datos.vigente_desde
    nueva = Tarifa(id_modo_desplazamiento=modo.id_modo_desplazamiento,
                   tipo_cobro=datos.tipo_cobro, monto=Decimal("%.2f" % datos.monto),
                   vigente_desde=datos.vigente_desde)
    sesion.add(nueva)
    try:
        sesion.flush()
    except IntegrityError:
        # La restricción ex_tarifa_sin_solape de la base encontró otra vigencia que choca
        # con la nueva (una tarifa cerrada que este módulo no ve como abierta).
        sesion.rollback()
        raise ErrorAPI(409, "TARIFA_SOLAPADA", MENSAJE_SOLAPADA, [
            {"campo": "vigente_desde", "problema": "se solapa con otra tarifa del mismo "
             "modo"}]) from None
    return _a_salida(nueva, tarifa_cerrada=abierta.id_tarifa if abierta else None)
