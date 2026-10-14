"""Esquemas de /modos-desplazamiento y /tarifas (openapi.yaml: ModoDesplazamiento,
Tarifa, TarifaCrear)."""
from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, Field

NombreModo = Literal["a pie", "transporte público", "taxi", "auto particular"]
TipoCobro = Literal["fijo", "por_km"]

# monto es NUMERIC(8,2) en la base: seis cifras enteras y dos decimales. Sin el máximo,
# un monto mayor no lo rechazaría la API sino la base, con un error 500.
MONTO_MAXIMO = 999_999.99
Monto = Annotated[float, Field(ge=0, le=MONTO_MAXIMO, allow_inf_nan=False)]


class ModoDesplazamiento(BaseModel):
    id_modo_desplazamiento: int
    nombre: NombreModo
    activo: bool


class Tarifa(BaseModel):
    id_tarifa: int
    id_modo_desplazamiento: int
    tipo_cobro: TipoCobro
    monto: float
    vigente_desde: date
    vigente_hasta: date | None = None
    # Solo lo trae la respuesta de POST /tarifas: la tarifa cuya vigencia se cerró.
    tarifa_cerrada: int | None = None


class TarifaCrear(BaseModel):
    id_modo_desplazamiento: int
    tipo_cobro: TipoCobro
    monto: Monto
    vigente_desde: date
