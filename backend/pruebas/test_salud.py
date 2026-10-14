from fastapi.testclient import TestClient

from app import VERSION
from app.core import base_datos
from app.main import app

cliente = TestClient(app)


def test_salud_responde_ok_con_la_base_arriba():
    r = cliente.get("/salud")
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["estado"] == "ok"
    assert cuerpo["base_datos"] == "ok"
    assert cuerpo["version"] == VERSION


def test_salud_avisa_503_si_la_base_no_responde(monkeypatch):
    # Se simula la caída sin apagar PostgreSQL de verdad.
    monkeypatch.setattr(base_datos, "base_responde", lambda: False)
    r = cliente.get("/salud")
    assert r.status_code == 503
    assert r.json()["base_datos"] == "sin conexión"


def test_salud_queda_fuera_del_contrato():
    # El contrato de la API es openapi.yaml; un endpoint de operación no debe colarse.
    assert "/salud" not in app.openapi()["paths"]
