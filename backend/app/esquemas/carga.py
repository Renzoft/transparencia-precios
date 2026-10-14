"""Esquemas de /cargas (openapi.yaml: CargaResumen, CargaEstado, CargaConfirmada,
Rechazo, CatalogoNuevo, Periodo)."""
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

Fuente = Literal["SISAP minorista", "SISAP mayorista", "precios por mercado"]
MotivoRechazo = Literal["duplicado", "dato faltante", "precio no válido",
                        "unidad desconocida", "fecha fuera de rango"]


class Periodo(BaseModel):
    desde: date
    hasta: date


class Rechazo(BaseModel):
    motivo: MotivoRechazo
    cantidad: int = Field(ge=1)


class CatalogoNuevo(BaseModel):
    productos: list[str] = []
    variedades: list[str] = []


class CargaResumen(BaseModel):
    id_carga_archivo: int
    estado: Literal["pendiente", "confirmada", "descartada"]
    nombre_archivo: str
    fuente: Fuente | None = None
    periodo: Periodo | None = None
    registros_validos: int = Field(ge=0)
    registros_rechazados: int = Field(ge=0)
    rechazos: list[Rechazo] = []
    catalogo_nuevo: CatalogoNuevo | None = None


class CargaEstado(BaseModel):
    estado: Literal["confirmada", "descartada"]


class CargaConfirmada(BaseModel):
    id_carga_archivo: int
    estado: Literal["confirmada", "descartada"]
    precios_guardados: int = Field(ge=0)
    confirmada_en: datetime
