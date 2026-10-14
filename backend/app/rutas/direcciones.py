"""Endpoint de /direcciones (R12; CU05, EX2). Público: el consumidor no inicia sesión."""
from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.limite import limite_direcciones
from app.esquemas.direccion import Direccion, DireccionBuscar
from app.esquemas.error import respuestas
from app.servicios import direcciones

router = APIRouter()


# POST y no GET con ?texto=: la dirección del consumidor es un dato personal, y lo que va
# en la URL queda escrito en la bitácora de acceso del servidor (RNF003).
@router.post("/direcciones", response_model=list[Direccion], tags=["Comparación"],
             operation_id="buscarDirecciones",
             summary="Busca una dirección de partida en Lima Metropolitana",
             responses=respuestas(422, 429, 503),
             dependencies=[Depends(limite_direcciones)])
def buscar_direcciones(datos: DireccionBuscar) -> list[Direccion]:
    return direcciones.buscar(datos.texto)
