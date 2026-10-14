"""Esquemas de /productos (openapi.yaml: Producto, Variedad)."""
from pydantic import BaseModel


class Producto(BaseModel):
    id_producto: int
    nombre: str


class Variedad(BaseModel):
    id_variedad: int
    id_producto: int
    nombre: str
    unidad_origen: str
    factor_a_kg: float
