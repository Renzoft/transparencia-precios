"""Configuración de la API, leída de variables de entorno.

El Documento de Arquitectura (sección 8.4) fija que los parámetros se leen del entorno
y no del código, para poder ajustarlos sin volver a desplegar. En desarrollo vienen del
archivo backend/.env; en Railway, de las variables que se definan en el servicio.
"""
from pathlib import Path

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

# backend/.env, sin importar desde qué carpeta se lance la API.
ARCHIVO_ENV = Path(__file__).resolve().parents[2] / ".env"


class Configuracion(BaseSettings):
    model_config = SettingsConfigDict(env_file=ARCHIVO_ENV, env_file_encoding="utf-8",
                                      extra="ignore")

    entorno: str = "desarrollo"

    # Los nombres coinciden con los que usan psql y los scripts de la tesis.
    pghost: str = "localhost"
    pgport: int = 5432
    pgdatabase: str = "transparencia_precios"
    pguser: str = "app_precios"
    # SecretStr evita que la contraseña aparezca si alguien imprime la configuración.
    pgpassword: SecretStr


configuracion = Configuracion()
