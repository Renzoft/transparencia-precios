"""CORS: el navegador solo deja que el panel llame a la API si la API lo autoriza.

Se autoriza una lista cerrada de orígenes, porque esas peticiones llevan el token del
administrador. En desarrollo se admite además cualquier puerto de localhost, donde
Flutter levanta el panel.
"""
from fastapi.testclient import TestClient

from app import main
from app.core.config import configuracion


def preflight(cliente, origen):
    # Lo que envía el navegador antes de un POST con token desde otro origen.
    return cliente.options("/api/v1/sesiones", headers={
        "Origin": origen, "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization,content-type"})


def test_en_desarrollo_el_panel_en_localhost_puede_llamar_a_la_api():
    c = TestClient(main.crear_app())
    r = preflight(c, "http://localhost:5000")
    assert r.status_code == 200
    assert r.headers["access-control-allow-origin"] == "http://localhost:5000"


def test_un_sitio_ajeno_no_puede_llamar_a_la_api():
    c = TestClient(main.crear_app())
    r = preflight(c, "https://sitio-ajeno.com")
    assert "access-control-allow-origin" not in r.headers


def test_en_produccion_solo_pasan_los_origenes_configurados(monkeypatch):
    monkeypatch.setattr(configuracion, "entorno", "produccion")
    monkeypatch.setattr(configuracion, "cors_origenes", "https://panel.ejemplo.pe/")
    c = TestClient(main.crear_app())
    assert preflight(c, "https://panel.ejemplo.pe").headers[
        "access-control-allow-origin"] == "https://panel.ejemplo.pe"
    # En producción, localhost ya no se admite.
    assert "access-control-allow-origin" not in preflight(c, "http://localhost:5000").headers
