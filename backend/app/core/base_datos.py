"""Conexión a PostgreSQL.

Un solo motor para toda la API, con un grupo de conexiones que se reutilizan entre
peticiones. Cada petición recibe su propia sesión y la cierra al terminar.
"""
from collections.abc import Iterator

from sqlalchemy import URL, create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import configuracion

# URL.create escapa la contraseña: si tuviera «@», «:» o «/», armar la URL a mano
# como texto la rompería.
URL_BASE = URL.create(
    "postgresql+psycopg",
    username=configuracion.pguser,
    password=configuracion.pgpassword.get_secret_value(),
    host=configuracion.pghost,
    port=configuracion.pgport,
    database=configuracion.pgdatabase,
)

motor = create_engine(
    URL_BASE,
    # Comprueba que la conexión siga viva antes de usarla: si PostgreSQL se reinició,
    # la API se recupera sola en vez de fallar en la primera petición.
    pool_pre_ping=True,
    # En Windows el cliente puede negociar la codificación de la consola en lugar de
    # UTF-8, y las tildes llegan dañadas. Ya pasó con crear_base_datos.sql; se fija aquí
    # para que no pase con la API.
    connect_args={"client_encoding": "utf8"},
)

FabricaSesion = sessionmaker(bind=motor, autoflush=False, expire_on_commit=False)


def obtener_sesion() -> Iterator[Session]:
    """Dependencia de FastAPI: una sesión por petición, cerrada siempre al terminar."""
    sesion = FabricaSesion()
    try:
        yield sesion
    finally:
        sesion.close()


def base_responde() -> bool:
    """True si la base acepta una consulta trivial. Lo usa el endpoint de salud."""
    try:
        with motor.connect() as cn:
            cn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
