"""Catálogo de productos y variedades para el consumidor (CU04, CU05).

Solo se muestran los activos. La búsqueda ignora tildes y mayúsculas: quien escribe
«azucar» en el teléfono busca «Azúcar».
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errores import ErrorAPI
from app.esquemas.catalogo import Producto as ProductoSalida
from app.esquemas.catalogo import Variedad as VariedadSalida
from app.modelos import Producto, Variedad
from app.servicios.texto import normalizar


def listar_productos(sesion: Session, buscar: str | None) -> list[ProductoSalida]:
    productos = sesion.scalars(select(Producto).where(Producto.activo)
                               .order_by(Producto.nombre))
    buscado = normalizar(buscar or "")
    return [ProductoSalida(id_producto=p.id_producto, nombre=p.nombre) for p in productos
            if buscado in normalizar(p.nombre)]


def listar_variedades(sesion: Session, id_producto: int) -> list[VariedadSalida]:
    producto = sesion.get(Producto, id_producto)
    if producto is None or not producto.activo:
        raise ErrorAPI(404, "PRODUCTO_NO_ENCONTRADO", "No existe el producto %d." % id_producto)
    variedades = sesion.scalars(
        select(Variedad).where(Variedad.id_producto == id_producto, Variedad.activo)
        .order_by(Variedad.nombre))
    return [VariedadSalida(id_variedad=v.id_variedad, id_producto=v.id_producto,
                           nombre=v.nombre, unidad_origen=v.unidad_origen,
                           factor_a_kg=float(v.factor_a_kg)) for v in variedades]
