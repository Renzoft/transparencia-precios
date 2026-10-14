from fastapi.testclient import TestClient

from app import VERSION
from app.main import app

cliente = TestClient(app)


def test_salud_responde_ok():
    r = cliente.get("/salud")
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["estado"] == "ok"
    assert cuerpo["version"] == VERSION


def test_salud_queda_fuera_del_contrato():
    # El contrato de la API es openapi.yaml; un endpoint de operación no debe colarse.
    assert "/salud" not in app.openapi()["paths"]
