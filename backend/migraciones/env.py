"""Entorno de Alembic.

Las migraciones cambian la estructura de la base, y el rol de la API, app_precios, no
puede hacerlo: solo lee y escribe datos. Por eso Alembic se conecta con un rol propio,
por defecto postgres, cuya contraseña se toma de la variable MIG_PGPASSWORD y nunca de
un archivo. Desde Git Bash:

    read -s -p "Clave de postgres: " MIG_PGPASSWORD && export MIG_PGPASSWORD

El esquema de partida lo crea crear_base_datos.sql, no Alembic: la revisión 0001 está
vacía y solo marca ese estado como punto de partida. Alembic se usa para los cambios
posteriores.
"""
import os
import sys
from logging.config import fileConfig

from alembic import context
from sqlalchemy import URL, create_engine, pool

from app.core.config import configuracion
from app.modelos import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def url_migracion() -> URL:
    clave = os.environ.get("MIG_PGPASSWORD")
    if not clave:
        sys.exit(
            "Falta MIG_PGPASSWORD. Alembic necesita un rol que pueda cambiar la "
            "estructura de la base.\nEn Git Bash:\n"
            '  read -s -p "Clave de postgres: " MIG_PGPASSWORD && '
            "export MIG_PGPASSWORD")
    return URL.create(
        "postgresql+psycopg",
        username=os.environ.get("MIG_PGUSER", "postgres"),
        password=clave,
        host=configuracion.pghost,
        port=configuracion.pgport,
        database=configuracion.pgdatabase,
    )


def run_migrations_offline() -> None:
    """Genera el SQL de las migraciones sin conectarse, para revisarlo antes."""
    context.configure(url=url_migracion(), target_metadata=target_metadata,
                      literal_binds=True, dialect_opts={"paramstyle": "named"})
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    motor = create_engine(url_migracion(), poolclass=pool.NullPool,
                          connect_args={"client_encoding": "utf8"})
    with motor.connect() as conexion:
        context.configure(connection=conexion, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
