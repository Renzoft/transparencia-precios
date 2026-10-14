"""Configuración de la API, leída de variables de entorno.

El Documento de Arquitectura (sección 8.4) fija que los parámetros se leen del entorno
y no del código, para poder ajustarlos sin volver a desplegar. En desarrollo vienen del
archivo backend/.env; en Railway, de las variables que se definan en el servicio.
"""
from pathlib import Path

from pydantic import SecretStr, field_validator
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

    # Orígenes web autorizados a llamar a la API desde el navegador (CORS), separados por
    # comas. Es el dominio donde se publique el panel. En desarrollo, además, se admite
    # cualquier puerto de localhost, porque Flutter levanta el panel en un puerto propio.
    cors_origenes: str = ""

    # Sesión del administrador (RNF001): token firmado con vigencia de ocho horas.
    jwt_secreto: SecretStr
    jwt_horas: int = 8

    # OpenRouteService (RNF017): distancias y tiempos de viaje, y búsqueda de direcciones.
    # Sin clave, la distancia se estima en línea recta (RNF008) y no se pueden buscar
    # direcciones. La clave la obtiene el tesista en openrouteservice.org.
    ors_clave: SecretStr | None = None
    ors_url: str = "https://api.openrouteservice.org"

    @field_validator("ors_clave")
    @classmethod
    def clave_vacia_es_ninguna(cls, v: SecretStr | None) -> SecretStr | None:
        # «ORS_CLAVE=» en el .env llega como texto vacío: equivale a no tener clave.
        return v if v is not None and v.get_secret_value().strip() else None

    @field_validator("jwt_secreto")
    @classmethod
    def secreto_suficiente(cls, v: SecretStr) -> SecretStr:
        # Con un secreto corto, cualquiera podría adivinarlo y fabricar tokens válidos.
        if len(v.get_secret_value()) < 32:
            raise ValueError("JWT_SECRETO debe tener al menos 32 caracteres")
        return v

    @property
    def lista_cors(self) -> list[str]:
        return [o.strip().rstrip("/") for o in self.cors_origenes.split(",") if o.strip()]


configuracion = Configuracion()
