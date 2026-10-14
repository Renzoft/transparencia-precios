"""Esquemas de /mercados (openapi.yaml: Mercado, MercadoCrear, MercadoActualizar)."""
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints, model_validator

# Los espacios de los extremos se quitan antes de validar: un nombre hecho solo de
# espacios cuenta como vacío y responde «es obligatorio» (CU02, EX1).
Nombre = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=150)]
Distrito = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
Direccion = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=160)]
Horario = Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)]
Latitud = Annotated[float, Field(ge=-90, le=90)]
Longitud = Annotated[float, Field(ge=-180, le=180)]


class Mercado(BaseModel):
    id_mercado: int
    nombre: str
    distrito: str
    direccion: str
    latitud: float
    longitud: float
    horario_atencion: str | None = None
    activo: bool


class MercadoCrear(BaseModel):
    nombre: Nombre
    distrito: Distrito
    direccion: Direccion
    latitud: Latitud
    longitud: Longitud
    horario_atencion: Horario | None = None


class MercadoActualizar(BaseModel):
    """Solo los campos que cambian. «activo» en falso desactiva el mercado (RN11).

    Los campos que el contrato no declara nulos se definen sin «| None»: se pueden
    omitir, pero enviarlos en null es un error. Solo el horario admite null, que lo borra.
    """
    nombre: Nombre = None             # type: ignore[assignment]
    distrito: Distrito = None         # type: ignore[assignment]
    direccion: Direccion = None       # type: ignore[assignment]
    latitud: Latitud = None           # type: ignore[assignment]
    longitud: Longitud = None         # type: ignore[assignment]
    horario_atencion: Horario | None = None
    activo: bool = None               # type: ignore[assignment]

    @model_validator(mode="after")
    def al_menos_un_campo(self):
        if not self.model_fields_set:
            raise ValueError("indica al menos un campo para modificar")
        return self
