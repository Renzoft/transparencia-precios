"""Endpoint de /comparaciones (CU05). Público: el consumidor no inicia sesión."""
from fastapi import APIRouter

from app.core.dependencias import SesionBD
from app.esquemas.comparacion import ComparacionCrear, ComparacionResultado
from app.esquemas.error import Error, respuestas
from app.servicios import comparaciones

router = APIRouter()


# exclude_none: lo que no aplica se omite (la duración con distancia aproximada, el
# ahorro cuando no hay mercados con qué compararlo), porque el contrato no lo declara nulo.
@router.post("/comparaciones", status_code=201, response_model=ComparacionResultado,
             response_model_exclude_none=True, tags=["Comparación"],
             operation_id="crearComparacion",
             summary="Calcula el costo total por mercado cercano y la recomendación",
             responses={**respuestas(422),
                        429: {"model": Error, "description": "Se superó el límite de "
                              "peticiones que protege la cuota del servicio de rutas"}})
def crear_comparacion(sesion: SesionBD, datos: ComparacionCrear) -> ComparacionResultado:
    return comparaciones.comparar(sesion, datos)
