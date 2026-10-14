"""Todas las respuestas de error deben tener el formato del contrato.

    {"error": {"codigo": "...", "mensaje": "...", "detalles": [...]}}

Se prueban los cuatro orígenes: datos que no cumplen el esquema, un cuerpo que ni
siquiera es JSON, errores del protocolo HTTP y fallas no previstas.
"""
import logging

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.errores import registrar_manejadores
from app.main import app

cliente = TestClient(app)


def es_formato_del_contrato(cuerpo: dict) -> bool:
    if set(cuerpo) != {"error"}:
        return False
    e = cuerpo["error"]
    if not {"codigo", "mensaje"} <= set(e) <= {"codigo", "mensaje", "detalles"}:
        return False
    if not (e["codigo"].isupper() and e["mensaje"]):
        return False
    return all(set(d) == {"campo", "problema"} for d in e.get("detalles", []))


def login(**cuerpo):
    return cliente.post("/api/v1/sesiones", json=cuerpo)


# ------------------------------------------------------------------------- 422
def test_clave_corta_responde_422_en_espanol():
    r = login(correo="a@unmsm.edu.pe", contrasena="123")
    assert r.status_code == 422
    assert es_formato_del_contrato(r.json())
    assert r.json()["error"]["codigo"] == "DATOS_NO_VALIDOS"
    assert r.json()["error"]["detalles"] == [
        {"campo": "contrasena", "problema": "debe tener al menos 8 caracteres"}]


def test_el_error_no_devuelve_la_clave_enviada():
    # FastAPI, por defecto, repite en la respuesta el valor que no pasó la validación.
    secreta = "MiClave"   # 7 caracteres: falla por corta
    r = login(correo="a@unmsm.edu.pe", contrasena=secreta)
    assert r.status_code == 422
    assert secreta not in r.text


def test_correo_mal_escrito():
    r = login(correo="esto-no-es-un-correo", contrasena="clave-valida-123")
    assert r.status_code == 422
    assert r.json()["error"]["detalles"] == [
        {"campo": "correo", "problema": "no es un correo electrónico válido"}]


def test_campos_faltantes_se_listan_todos():
    r = login()
    assert r.status_code == 422
    campos = {d["campo"]: d["problema"] for d in r.json()["error"]["detalles"]}
    assert campos == {"correo": "es obligatorio", "contrasena": "es obligatorio"}


# ------------------------------------------------------------------------- 400
def test_json_roto_responde_400_sin_detalles():
    r = cliente.post("/api/v1/sesiones", content=b'{"correo":',
                     headers={"Content-Type": "application/json"})
    assert r.status_code == 400
    assert es_formato_del_contrato(r.json())
    assert r.json()["error"]["codigo"] == "PETICION_MALFORMADA"
    assert "detalles" not in r.json()["error"]


# ----------------------------------------------------------------- 404 y 405
def test_ruta_inexistente_responde_404():
    r = cliente.get("/api/v1/no-existe")
    assert r.status_code == 404
    assert es_formato_del_contrato(r.json())
    assert r.json()["error"]["codigo"] == "RECURSO_NO_ENCONTRADO"


def test_metodo_no_admitido_responde_405_y_dice_cual_si():
    r = cliente.get("/api/v1/sesiones")       # solo admite POST
    assert r.status_code == 405
    assert es_formato_del_contrato(r.json())
    assert "POST" in r.headers["Allow"]


# ------------------------------------------------------------------------- 500
# Una falla real no se puede provocar a voluntad en la API; se monta una ruta que falla.
falla = FastAPI()
registrar_manejadores(falla)


@falla.get("/explota")
def explota():
    raise RuntimeError("detalle interno: tabla precio_serie, clave 1234")


def test_falla_inesperada_responde_500_sin_revelar_nada(caplog):
    c = TestClient(falla, raise_server_exceptions=False)
    with caplog.at_level(logging.ERROR, logger="transparencia_precios"):
        r = c.get("/explota")
    assert r.status_code == 500
    assert es_formato_del_contrato(r.json())
    assert r.json()["error"]["codigo"] == "ERROR_INTERNO"
    # Al cliente no le llega nada interno...
    assert "precio_serie" not in r.text and "RuntimeError" not in r.text
    # ...pero el detalle sí queda en el registro del servidor, para poder investigarlo.
    assert "precio_serie" in caplog.text
