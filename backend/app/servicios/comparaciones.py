"""Costo total de compra por mercado cercano (CU05; R12 a R15; RN03, RN06, RN07, RN08).

Para cada mercado activo dentro del radio:

  costo de los productos      suma de precio vigente × cantidad (RN03: el precio vigente
                              es el del registro más reciente de ese mercado)
  costo de desplazamiento     tarifa vigente del modo, de ida y vuelta (RN07): el pasaje
                              fijo se paga dos veces; el cobro por km, por el doble de la
                              distancia
  costo total                 la suma de los dos

El ahorro neto se mide contra el mercado habitual del consumidor o, si no lo indica,
contra el promedio de los mercados cercanos (RN08).

Nada de esto se guarda: el resultado es un dato derivado (Diccionario de Datos) y el
cuerpo trae la ubicación del consumidor, que no se registra (RNF003).
"""
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import or_, select
from sqlalchemy.dialects.postgresql import distinct_on
from sqlalchemy.orm import Session

from app.core.errores import ErrorAPI
from app.esquemas.comparacion import (ComparacionCrear, ComparacionResultado,
                                      MercadoComparado, Recomendacion, Referencia)
from app.modelos import Mercado, ModoDesplazamiento, PrecioMercado, Tarifa, Variedad
from app.servicios import rutas
from app.servicios.tarifas import hoy

CENTIMO = Decimal("0.01")


def _no_valido(codigo: str, mensaje: str, campo: str, problema: str) -> ErrorAPI:
    return ErrorAPI(422, codigo, mensaje, [{"campo": campo, "problema": problema}])


def _soles(x: Decimal) -> float:
    return float(x.quantize(CENTIMO))


# ------------------------------------------------------------------ validaciones
def _tarifa_vigente(sesion: Session, datos: ComparacionCrear) -> tuple[ModoDesplazamiento, Tarifa]:
    modo = sesion.get(ModoDesplazamiento, datos.id_modo_desplazamiento)
    if modo is None or not modo.activo:
        raise _no_valido("MODO_NO_VALIDO", "El modo de desplazamiento no existe o no está "
                         "activo.", "id_modo_desplazamiento", "no es un modo activo")
    h = hoy()
    tarifa = sesion.scalars(select(Tarifa).where(
        Tarifa.id_modo_desplazamiento == modo.id_modo_desplazamiento,
        Tarifa.vigente_desde <= h,
        or_(Tarifa.vigente_hasta.is_(None), Tarifa.vigente_hasta > h))).first()
    if tarifa is None:
        raise _no_valido("TARIFA_NO_CONFIGURADA", "El modo de desplazamiento elegido "
                         "todavía no tiene una tarifa.", "id_modo_desplazamiento",
                         "%s no tiene tarifa vigente" % modo.nombre)
    return modo, tarifa


def _validar_items(sesion: Session, datos: ComparacionCrear) -> None:
    ids = [i.id_variedad for i in datos.items]
    activas = set(sesion.scalars(select(Variedad.id_variedad).where(
        Variedad.id_variedad.in_(ids), Variedad.activo)))
    problemas, vistas = [], set()
    for n, id_variedad in enumerate(ids):
        if id_variedad in vistas:
            problemas.append({"campo": "items.%d.id_variedad" % n,
                              "problema": "la variedad %d está repetida en la lista" % id_variedad})
        elif id_variedad not in activas:
            problemas.append({"campo": "items.%d.id_variedad" % n,
                              "problema": "no existe la variedad %d" % id_variedad})
        vistas.add(id_variedad)
    if problemas:
        raise ErrorAPI(422, "LISTA_NO_VALIDA", "Hay productos de la lista que no son "
                       "válidos.", problemas)


# ------------------------------------------------------------------------ cálculo
def _precios_vigentes(sesion: Session, ids_mercado: list[int],
                      ids_variedad: list[int]) -> dict[tuple[int, int], Decimal]:
    """{(mercado, variedad): precio por kg del registro más reciente} (RN03)."""
    if not ids_mercado:
        return {}
    filas = sesion.execute(
        select(PrecioMercado.id_mercado, PrecioMercado.id_variedad, PrecioMercado.precio_kg)
        .where(PrecioMercado.id_mercado.in_(ids_mercado),
               PrecioMercado.id_variedad.in_(ids_variedad))
        .ext(distinct_on(PrecioMercado.id_mercado, PrecioMercado.id_variedad))
        .order_by(PrecioMercado.id_mercado, PrecioMercado.id_variedad,
                  PrecioMercado.fecha.desc()))
    return {(m, v): p for m, v, p in filas}


def _desplazamiento(tarifa: Tarifa, distancia_km: float) -> Decimal:
    if tarifa.tipo_cobro == "fijo":
        return tarifa.monto * 2                                  # ida y vuelta (RN07)
    return tarifa.monto * Decimal(str(distancia_km)) * 2


def comparar(sesion: Session, datos: ComparacionCrear) -> ComparacionResultado:
    modo, tarifa = _tarifa_vigente(sesion, datos)
    _validar_items(sesion, datos)

    habitual = None
    if datos.id_mercado_habitual is not None:
        habitual = sesion.get(Mercado, datos.id_mercado_habitual)
        if habitual is None or not habitual.activo:
            raise _no_valido("MERCADO_HABITUAL_NO_VALIDO", "El mercado habitual no existe o "
                             "no está activo.", "id_mercado_habitual", "no es un mercado activo")

    # Mercados dentro del radio (RN06). El radio se mide en línea recta: la distancia por
    # calle siempre es mayor o igual, y así la búsqueda no depende del servicio de rutas.
    origen = rutas.Punto(datos.origen.latitud, datos.origen.longitud)

    def punto(m: Mercado) -> rutas.Punto:
        return rutas.Punto(float(m.latitud), float(m.longitud))

    cercanos = [m for m in sesion.scalars(select(Mercado).where(Mercado.activo))
                if rutas.linea_recta(origen, punto(m)) <= datos.radio_km]
    # El habitual se calcula aunque quede fuera del radio: es la referencia del ahorro.
    destinos = cercanos + ([habitual] if habitual and habitual not in cercanos else [])
    trayectos, aproximada = rutas.trayectos(origen, [punto(m) for m in destinos], modo.nombre)

    ids_variedad = [i.id_variedad for i in datos.items]
    precios = _precios_vigentes(sesion, [m.id_mercado for m in destinos], ids_variedad)

    calculados = {}
    for m, t in zip(destinos, trayectos):
        productos = Decimal(0)
        sin_precio = []
        for item in datos.items:
            precio = precios.get((m.id_mercado, item.id_variedad))
            if precio is None:
                sin_precio.append(item.id_variedad)
            else:
                productos += precio * Decimal(str(item.cantidad_kg))
        viaje = _desplazamiento(tarifa, t.distancia_km)
        calculados[m.id_mercado] = MercadoComparado(
            id_mercado=m.id_mercado, nombre=m.nombre, distrito=m.distrito,
            distancia_km=round(t.distancia_km, 2), duracion_min=t.duracion_min,
            costo_productos=_soles(productos), costo_desplazamiento=_soles(viaje),
            costo_total=_soles(productos + viaje), sin_precio=sin_precio)

    resultado = [calculados[m.id_mercado] for m in cercanos]

    referencia = None
    if habitual is not None:
        referencia = Referencia(tipo="mercado habitual", id_mercado=habitual.id_mercado,
                                costo_total=calculados[habitual.id_mercado].costo_total)
    elif resultado:
        promedio = sum(Decimal(str(r.costo_total)) for r in resultado) / len(resultado)
        referencia = Referencia(tipo="promedio de cercanos", costo_total=_soles(promedio))
    if referencia is not None:
        for r in resultado:
            r.ahorro_neto = round(referencia.costo_total - r.costo_total, 2)

    # Primero los mercados con la lista completa: uno sin precios no es «el más barato».
    resultado.sort(key=lambda r: (len(r.sin_precio), r.costo_total))

    return ComparacionResultado(
        generado_en=datetime.now(timezone.utc), distancia_aproximada=aproximada,
        referencia=referencia, mercados=resultado,
        # La recomendación de cuándo comprar es el CU06, que usa las tendencias del CU03.
        recomendacion=Recomendacion(
            disponible=False, productos_sin_tendencia=len(datos.items),
            motivo="La recomendación de cuándo comprar todavía no está disponible."))
