"""Esquemas de /comparaciones (openapi.yaml: ComparacionCrear, Origen, ItemLista,
ComparacionResultado, Referencia, MercadoComparado, Recomendacion)."""
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field


class Origen(BaseModel):
    latitud: Annotated[float, Field(ge=-90, le=90)]
    longitud: Annotated[float, Field(ge=-180, le=180)]


class ItemLista(BaseModel):
    id_variedad: int
    cantidad_kg: Annotated[float, Field(gt=0, allow_inf_nan=False)]


class ComparacionCrear(BaseModel):
    origen: Origen
    id_modo_desplazamiento: int
    radio_km: Annotated[float, Field(ge=0.5, le=20)] = 3      # RN06
    id_mercado_habitual: int | None = None
    items: Annotated[list[ItemLista], Field(min_length=1, max_length=50)]


class Referencia(BaseModel):
    tipo: Literal["mercado habitual", "promedio de cercanos"]
    id_mercado: int | None = None
    costo_total: float


class MercadoComparado(BaseModel):
    id_mercado: int
    nombre: str
    distrito: str
    distancia_km: float
    # Se omite cuando la distancia es en línea recta: no da un tiempo de viaje.
    duracion_min: int | None = None
    costo_productos: float
    costo_desplazamiento: float
    costo_total: float
    ahorro_neto: float | None = None
    sin_precio: list[int]


class Recomendacion(BaseModel):
    disponible: bool
    postergar: bool | None = None
    motivo: str
    ahorro_estimado: float | None = None
    productos_sin_tendencia: int


class ComparacionResultado(BaseModel):
    generado_en: datetime
    distancia_aproximada: bool
    referencia: Referencia | None = None
    mercados: list[MercadoComparado]
    recomendacion: Recomendacion
