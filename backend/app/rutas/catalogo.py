"""Endpoints de /productos (CU04, CU05). Públicos: el consumidor no inicia sesión."""
from typing import Annotated

from fastapi import APIRouter, Path, Query

from app.core.dependencias import SesionBD
from app.esquemas.catalogo import Producto, Variedad
from app.esquemas.error import respuestas
from app.servicios import catalogo

router = APIRouter()

IdProducto = Annotated[int, Path(alias="id", ge=1, description="Identificador del recurso")]


@router.get("/productos", response_model=list[Producto], tags=["Catálogo"],
            operation_id="listarProductos", summary="Catálogo de productos activos",
            responses=respuestas(422))
def listar_productos(sesion: SesionBD,
                     buscar: Annotated[str | None, Query(max_length=120)] = None
                     ) -> list[Producto]:
    return catalogo.listar_productos(sesion, buscar)


@router.get("/productos/{id}/variedades", response_model=list[Variedad], tags=["Catálogo"],
            operation_id="listarVariedadesDeProducto",
            summary="Variedades activas de un producto", responses=respuestas(404, 422))
def listar_variedades(sesion: SesionBD, id_producto: IdProducto) -> list[Variedad]:
    return catalogo.listar_variedades(sesion, id_producto)
