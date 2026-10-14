"""Esquemas de POST /sesiones (openapi.yaml: SesionCrear, SesionToken, UsuarioResumen)."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field


class SesionCrear(BaseModel):
    correo: EmailStr = Field(max_length=120)
    contrasena: str = Field(min_length=8, max_length=72)


class UsuarioResumen(BaseModel):
    nombre: str
    rol: Literal["administrador"]


class SesionToken(BaseModel):
    token: str
    tipo: Literal["Bearer"] = "Bearer"
    expira_en: datetime
    usuario: UsuarioResumen
