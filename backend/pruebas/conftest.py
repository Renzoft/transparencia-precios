"""Utilidades compartidas por las pruebas.

sesion_aislada: una sesión de base de datos que vive dentro de una transacción que se
deshace al terminar la prueba. Hace falta para las pruebas que guardan precios: el rol
de la API no puede borrar de precio_serie (RNF010), así que lo que una prueba insertara
quedaría para siempre. Dentro de la transacción la prueba inserta de verdad, la API ve
lo insertado, y al final todo se revierte sin necesitar ese permiso.

La API usa esta misma sesión gracias a dependency_overrides, y cada commit que hace el
código pasa a ser un punto de guardado dentro de la transacción de la prueba.
"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.base_datos import motor, obtener_sesion
from app.core.config import configuracion
from app.core.limite import limite_comparaciones, limite_direcciones
from app.core.seguridad import crear_token, hash_clave
from app.main import app
from app.modelos import Usuario


@pytest.fixture(autouse=True)
def sin_openrouteservice(monkeypatch):
    # Ninguna prueba llama al OpenRouteService real, aunque el .env tenga la clave: eso
    # gastaría la cuota diaria y haría que las pruebas dependan de internet. Las que
    # prueban la integración lo simulan (test_ors.py).
    monkeypatch.setattr(configuracion, "ors_clave", None)


@pytest.fixture(autouse=True)
def limites_en_cero():
    # Cada prueba empieza con el contador de peticiones vacío: si no, las pruebas de
    # /comparaciones, que llegan todas del mismo cliente, chocarían con el límite.
    limite_comparaciones.reiniciar()
    limite_direcciones.reiniciar()


@pytest.fixture
def sesion_aislada():
    conexion = motor.connect()
    transaccion = conexion.begin()
    sesion = Session(bind=conexion, join_transaction_mode="create_savepoint",
                     autoflush=False, expire_on_commit=False)

    def _sesion():
        yield sesion

    app.dependency_overrides[obtener_sesion] = _sesion
    try:
        yield sesion
    finally:
        app.dependency_overrides.pop(obtener_sesion, None)
        sesion.close()
        transaccion.rollback()
        conexion.close()


@pytest.fixture
def cliente(sesion_aislada):
    return TestClient(app)


@pytest.fixture
def admin(sesion_aislada) -> Usuario:
    u = Usuario(correo="prueba.cargas@unmsm.edu.pe",
                contrasena_hash=hash_clave("clave-de-cargas-1"), nombre="Prueba cargas")
    sesion_aislada.add(u)
    sesion_aislada.flush()
    return u


@pytest.fixture
def auth(admin) -> dict:
    token, _ = crear_token(admin.id_usuario, admin.rol)
    return {"Authorization": "Bearer " + token}
