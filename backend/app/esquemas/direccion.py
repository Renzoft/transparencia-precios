"""Esquemas de /direcciones (openapi.yaml: DireccionBuscar, Direccion)."""
from typing import Annotated

from pydantic import BaseModel, StringConstraints


class DireccionBuscar(BaseModel):
    texto: Annotated[str, StringConstraints(strip_whitespace=True, min_length=3,
                                            max_length=200)]


class Direccion(BaseModel):
    etiqueta: str
    latitud: float
    longitud: float
