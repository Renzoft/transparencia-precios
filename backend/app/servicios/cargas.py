"""Carga de precios en dos pasos (CU01, R2, R3; AD10).

  1. Subir: se lee el archivo, se separan los registros válidos de los rechazados y se
     guarda la carga como «pendiente» junto con el archivo original. No se guarda ningún
     precio todavía.
  2. Resolver: el administrador revisa el resumen y confirma o descarta. Al confirmar, el
     archivo guardado se vuelve a leer y recién ahí se guardan los precios.

Se vuelve a leer al confirmar, en lugar de confiar en el resumen del primer paso, porque
entre los dos pasos puede haberse confirmado otra carga con las mismas fechas: lo que se
guarda es lo que de verdad falta en ese momento, y los conteos de la carga se corrigen
para que digan lo que realmente pasó.

Una variedad nueva no se crea al subir sino al confirmar: si el administrador descarta,
el catálogo queda intacto.
"""
import hashlib
from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, undefer

from app.core.errores import ErrorAPI
from app.esquemas.carga import (CargaConfirmada, CargaResumen, CatalogoNuevo, Periodo,
                                Rechazo)
from app.modelos import (CargaArchivo, CargaRechazo, PrecioSerie, Producto, Usuario,
                         Variedad)
from app.servicios import lector_sisap
from app.servicios.lector_sisap import DUPLICADO, MAYORISTA, MINORISTA, Lectura, Registro
from app.servicios.texto import normalizar as _normalizar

# Un archivo del SISAP de un año entero de una variedad pesa unos 200 KB.
TAMANO_MAXIMO = 5 * 1024 * 1024

# Orden fijo de los motivos en el resumen, el mismo del contrato.
MOTIVOS = ["duplicado", "dato faltante", "precio no válido", "unidad desconocida",
           "fecha fuera de rango"]


# ----------------------------------------------------------- análisis de un archivo
@dataclass
class Analisis:
    lectura: Lectura
    variedad: Variedad | None              # la variedad del catálogo, si ya existe
    producto: Producto | None = None       # producto existente para una variedad nueva
    producto_nuevo: str | None = None      # nombre del producto que habría que crear
    nuevos: list[Registro] = field(default_factory=list)
    rechazos: Counter = field(default_factory=Counter)

    @property
    def variedad_nueva(self) -> str | None:
        return None if self.variedad else self.lectura.variedad

    def catalogo_nuevo(self) -> CatalogoNuevo:
        return CatalogoNuevo(
            productos=[self.producto_nuevo] if self.producto_nuevo else [],
            variedades=[self.variedad_nueva] if self.variedad_nueva else [])


def _formato_no_valido(motivo: str) -> ErrorAPI:
    return ErrorAPI(400, "FORMATO_NO_VALIDO", lector_sisap.MENSAJE_FORMATO,
                    [{"campo": "archivo", "problema": motivo}])


def analizar(sesion: Session, contenido: bytes, fuente: str) -> Analisis:
    """Lee el archivo y lo cruza con la base: catálogo y precios ya guardados."""
    try:
        lectura = lector_sisap.leer(contenido, fuente)
    except lector_sisap.FormatoNoValido as e:
        raise _formato_no_valido(e.motivo) from None

    buscado = _normalizar(lectura.variedad)
    variedad = next((v for v in sesion.scalars(select(Variedad))
                     if _normalizar(v.nombre) == buscado), None)
    analisis = Analisis(lectura=lectura, variedad=variedad,
                        rechazos=Counter(lectura.rechazos))

    if variedad is None:
        # Variedad nueva: el archivo no dice a qué producto pertenece. Se toma el producto
        # del catálogo cuyo nombre encabeza el de la variedad («Papa negra andina» va en
        # «Papa»); si no hay ninguno, se propone uno con la primera palabra. Las dos cosas
        # se muestran en el resumen, antes de confirmar.
        candidatos = [p for p in sesion.scalars(select(Producto))
                      if buscado == _normalizar(p.nombre)
                      or buscado.startswith(_normalizar(p.nombre) + " ")]
        if candidatos:
            analisis.producto = max(candidatos, key=lambda p: len(p.nombre))
        else:
            analisis.producto_nuevo = lectura.variedad.split()[0].capitalize()
        analisis.nuevos = list(lectura.registros)
        return analisis

    ya_guardados = set(sesion.execute(
        select(PrecioSerie.fecha, PrecioSerie.ambito).where(
            PrecioSerie.id_variedad == variedad.id_variedad,
            PrecioSerie.fecha.between(lectura.desde, lectura.hasta))))
    for r in lectura.registros:
        if (r.fecha, r.ambito) in ya_guardados:
            analisis.rechazos[DUPLICADO] += 1
        else:
            analisis.nuevos.append(r)
    return analisis


# -------------------------------------------------------------------- resúmenes
def _rechazos(conteo: Counter) -> list[Rechazo]:
    return [Rechazo(motivo=m, cantidad=conteo[m]) for m in MOTIVOS if conteo.get(m)]


def _periodo_del_archivo(carga: CargaArchivo) -> Periodo | None:
    if not carga.contenido_archivo:
        return None
    try:
        lectura = lector_sisap.leer(carga.contenido_archivo, carga.fuente)
    except lector_sisap.FormatoNoValido:
        return None
    return Periodo(desde=lectura.desde, hasta=lectura.hasta)


def _resumen(carga: CargaArchivo, rechazos: Counter, periodo: Periodo | None,
             catalogo: CatalogoNuevo | None = None) -> CargaResumen:
    return CargaResumen(
        id_carga_archivo=carga.id_carga_archivo, estado=carga.estado,
        nombre_archivo=carga.nombre_archivo, fuente=carga.fuente, periodo=periodo,
        registros_validos=carga.registros_validos,
        registros_rechazados=carga.registros_rechazados,
        rechazos=_rechazos(rechazos), catalogo_nuevo=catalogo)


def _rechazos_guardados(sesion: Session, ids: list[int]) -> dict[int, Counter]:
    out: dict[int, Counter] = {i: Counter() for i in ids}
    for r in sesion.scalars(select(CargaRechazo).where(CargaRechazo.id_carga_archivo.in_(ids))):
        out[r.id_carga_archivo][r.motivo] = r.cantidad
    return out


def _periodos_historicos(sesion: Session, ids: list[int]) -> dict[int, Periodo]:
    """Periodo de las cargas sin archivo guardado, las históricas de cargar_precios.py."""
    if not ids:
        return {}
    filas = sesion.execute(
        select(PrecioSerie.id_carga_archivo, func.min(PrecioSerie.fecha),
               func.max(PrecioSerie.fecha))
        .where(PrecioSerie.id_carga_archivo.in_(ids))
        .group_by(PrecioSerie.id_carga_archivo))
    return {i: Periodo(desde=d, hasta=h) for i, d, h in filas}


# ------------------------------------------------------------- paso 1: subir el archivo
def crear_carga(sesion: Session, admin: Usuario, nombre_archivo: str, contenido: bytes,
                fuente: str) -> CargaResumen:
    if len(contenido) > TAMANO_MAXIMO:
        raise ErrorAPI(422, "ARCHIVO_DEMASIADO_GRANDE",
                       "El archivo supera los 5 MB permitidos.",
                       [{"campo": "archivo", "problema": "no puede pasar de 5 MB"}])
    if not contenido:
        raise _formato_no_valido("el archivo está vacío")

    huella = hashlib.sha256(contenido).hexdigest()
    # Una carga descartada no bloquea volver a subir el mismo archivo (uq_carga_hash).
    previa = sesion.scalar(select(CargaArchivo).where(CargaArchivo.hash_archivo == huella,
                                                      CargaArchivo.estado != "descartada"))
    if previa is not None:
        raise _ya_cargado(previa)

    analisis = analizar(sesion, contenido, fuente)
    if not analisis.nuevos:
        # CU01, EX3: no se guarda nada, ni siquiera la carga.
        raise ErrorAPI(422, "SIN_REGISTROS_VALIDOS", "El archivo no contiene registros válidos",
                       [{"campo": "archivo", "problema": "%d %s" % (r.cantidad, r.motivo)}
                        for r in _rechazos(analisis.rechazos)])

    carga = CargaArchivo(
        id_usuario=admin.id_usuario, nombre_archivo=(nombre_archivo or "archivo.xls")[:255],
        hash_archivo=huella, fuente=fuente, registros_validos=len(analisis.nuevos),
        registros_rechazados=sum(analisis.rechazos.values()), estado="pendiente",
        contenido_archivo=contenido)
    sesion.add(carga)
    try:
        sesion.flush()
    except IntegrityError:
        # Otra petición subió el mismo archivo entre la consulta de arriba y esta.
        sesion.rollback()
        raise _ya_cargado(sesion.scalar(
            select(CargaArchivo).where(CargaArchivo.hash_archivo == huella,
                                       CargaArchivo.estado != "descartada"))) from None
    sesion.add_all(CargaRechazo(id_carga_archivo=carga.id_carga_archivo, motivo=m,
                                cantidad=c) for m, c in analisis.rechazos.items() if c)
    sesion.flush()
    lectura = analisis.lectura
    return _resumen(carga, analisis.rechazos, Periodo(desde=lectura.desde, hasta=lectura.hasta),
                    analisis.catalogo_nuevo())


def _ya_cargado(previa: CargaArchivo | None) -> ErrorAPI:
    detalle = ("Ya se subió como la carga %d, que está %s."
               % (previa.id_carga_archivo, previa.estado)) if previa else ""
    return ErrorAPI(409, "ARCHIVO_YA_CARGADO",
                    ("Este archivo ya fue cargado antes. " + detalle).strip())


# --------------------------------------------------------- paso 2: confirmar o descartar
def resolver_carga(sesion: Session, id_carga: int, estado: str) -> CargaConfirmada:
    # FOR UPDATE: si llegan dos confirmaciones de la misma carga a la vez, la segunda
    # espera a que termine la primera y entonces ya la encuentra resuelta.
    carga = sesion.get(CargaArchivo, id_carga, with_for_update=True,
                       options=[undefer(CargaArchivo.contenido_archivo)])
    if carga is None:
        raise ErrorAPI(404, "CARGA_NO_ENCONTRADA", "No existe la carga %d." % id_carga)
    if carga.estado != "pendiente":
        raise ErrorAPI(409, "CARGA_YA_RESUELTA",
                       "La carga %d ya está %s; una carga se resuelve una sola vez."
                       % (id_carga, carga.estado))

    guardados = 0
    if estado == "confirmada":
        guardados = _guardar_precios(sesion, carga)
    carga.estado = estado
    sesion.flush()
    return CargaConfirmada(id_carga_archivo=carga.id_carga_archivo, estado=estado,
                           precios_guardados=guardados, confirmada_en=datetime.now(UTC))


def _guardar_precios(sesion: Session, carga: CargaArchivo) -> int:
    analisis = analizar(sesion, carga.contenido_archivo, carga.fuente)
    variedad = analisis.variedad or _crear_variedad(sesion, analisis)

    guardados = 0
    if analisis.nuevos:
        filas = [{"id_variedad": variedad.id_variedad,
                  "id_carga_archivo": carga.id_carga_archivo, "fecha": r.fecha,
                  "ambito": r.ambito, "precio_kg": r.precio_kg, "volumen_t": r.volumen_t}
                 for r in analisis.nuevos]
        # ON CONFLICT DO NOTHING es la última red: la consulta de duplicados ya excluyó
        # lo existente, pero si otra transacción inserta lo mismo justo ahora, la fila
        # se omite en lugar de hacer fallar toda la confirmación.
        # Se cuentan las filas que la base devuelve como insertadas, no rowcount: en
        # una inserción múltiple con ON CONFLICT el controlador lo informa como -1.
        insertadas = sesion.execute(
            insert(PrecioSerie).values(filas).on_conflict_do_nothing(
                index_elements=["id_variedad", "fecha", "ambito"])
            .returning(PrecioSerie.id_precio_serie)).all()
        guardados = len(insertadas)
        analisis.rechazos[DUPLICADO] += len(filas) - guardados

    # Los conteos de la carga pasan a decir lo que de verdad se guardó.
    carga.registros_validos = guardados
    carga.registros_rechazados = sum(analisis.rechazos.values())
    sesion.execute(delete(CargaRechazo).where(
        CargaRechazo.id_carga_archivo == carga.id_carga_archivo))
    sesion.add_all(CargaRechazo(id_carga_archivo=carga.id_carga_archivo, motivo=m,
                                cantidad=c) for m, c in analisis.rechazos.items() if c)
    return guardados


def _crear_variedad(sesion: Session, analisis: Analisis) -> Variedad:
    producto = analisis.producto
    if producto is None:
        producto = Producto(nombre=analisis.producto_nuevo)
        sesion.add(producto)
        sesion.flush()
    # La unidad de origen es la que ve el consumidor: la minorista si el archivo la trae.
    unidades = analisis.lectura.unidades
    unidad, factor = unidades.get(MINORISTA) or unidades.get(MAYORISTA) or ("kilogramo",
                                                                             Decimal(1))
    variedad = Variedad(id_producto=producto.id_producto, nombre=analisis.lectura.variedad,
                        unidad_origen=unidad.lower()[:20], factor_a_kg=factor)
    sesion.add(variedad)
    sesion.flush()
    return variedad


# --------------------------------------------------------------------- consultas
def listar_cargas(sesion: Session, limite: int) -> list[CargaResumen]:
    cargas = list(sesion.scalars(
        select(CargaArchivo).options(undefer(CargaArchivo.contenido_archivo))
        .order_by(CargaArchivo.fecha_carga.desc(), CargaArchivo.id_carga_archivo.desc())
        .limit(limite)))
    ids = [c.id_carga_archivo for c in cargas]
    rechazos = _rechazos_guardados(sesion, ids)
    historicos = _periodos_historicos(
        sesion, [c.id_carga_archivo for c in cargas if not c.contenido_archivo])
    return [_resumen(c, rechazos[c.id_carga_archivo],
                     _periodo_del_archivo(c) or historicos.get(c.id_carga_archivo))
            for c in cargas]


def obtener_carga(sesion: Session, id_carga: int) -> CargaResumen:
    carga = sesion.get(CargaArchivo, id_carga,
                       options=[undefer(CargaArchivo.contenido_archivo)])
    if carga is None:
        raise ErrorAPI(404, "CARGA_NO_ENCONTRADA", "No existe la carga %d." % id_carga)
    periodo = (_periodo_del_archivo(carga)
               or _periodos_historicos(sesion, [id_carga]).get(id_carga))
    catalogo = None
    if carga.estado == "pendiente" and carga.contenido_archivo:
        # Lo que se incorporaría al catálogo si se confirma ahora.
        catalogo = analizar(sesion, carga.contenido_archivo, carga.fuente).catalogo_nuevo()
    return _resumen(carga, _rechazos_guardados(sesion, [id_carga])[id_carga], periodo,
                    catalogo)
