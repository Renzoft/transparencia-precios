"""Integración con OpenRouteService (RNF017, RNF008) y búsqueda de direcciones (EX2).

OpenRouteService se simula reemplazando urlopen: así se prueba lo que la API le envía
(clave, perfil, coordenadas en el orden que pide) y cómo reacciona a cada respuesta,
incluidas las fallas, sin gastar la cuota real ni depender de internet.
"""
import io
import json
import logging
import time
import urllib.error

import pytest
from pydantic import SecretStr

from app.core.config import configuracion
from app.servicios import ors, rutas
from app.servicios.rutas import Punto
from pruebas.contrato import validar_respuesta
from pruebas.test_comparaciones import A, B, ORIGEN, comparar, escenario, lista  # noqa: F401

CLAVE = "clave-de-prueba"
MAGDALENA = Punto(-12.0912, -77.0712)
SURQUILLO = Punto(-12.1124, -77.0228)


class OrsFalso:
    """Responde como OpenRouteService y guarda lo que recibió."""

    def __init__(self, responder):
        self.responder = responder
        self.peticiones = []

    def __call__(self, peticion, timeout):
        self.peticiones.append(peticion)
        r = self.responder(peticion)
        if isinstance(r, Exception):
            raise r
        return io.BytesIO(json.dumps(r).encode())

    @property
    def cuerpo(self):
        return json.loads(self.peticiones[-1].data)


@pytest.fixture
def con_clave(monkeypatch):
    monkeypatch.setattr(configuracion, "ors_clave", SecretStr(CLAVE))


def instalar(monkeypatch, responder) -> OrsFalso:
    falso = OrsFalso(responder)
    monkeypatch.setattr(ors.urllib.request, "urlopen", falso)
    return falso


def matriz_ok(peticion):
    n = len(json.loads(peticion.data)["destinations"])
    return {"distances": [[1.25 * (i + 1) for i in range(n)]],
            "durations": [[300.0 * (i + 1) for i in range(n)]]}


# -------------------------------------------------------------------- distancias
def test_sin_clave_no_llama_y_usa_linea_recta(monkeypatch):
    falso = instalar(monkeypatch, matriz_ok)
    t, aproximada = rutas.trayectos(MAGDALENA, [SURQUILLO], "taxi")
    assert aproximada and t[0].duracion_min is None
    assert t[0].distancia_km == pytest.approx(rutas.linea_recta(MAGDALENA, SURQUILLO))
    assert falso.peticiones == []


def test_una_sola_matriz_con_la_clave_el_perfil_y_longitud_primero(monkeypatch, con_clave):
    falso = instalar(monkeypatch, matriz_ok)
    t, aproximada = rutas.trayectos(MAGDALENA, [MAGDALENA, SURQUILLO], "a pie")
    assert not aproximada
    assert [(x.distancia_km, x.duracion_min) for x in t] == [(1.25, 5), (2.5, 10)]
    p = falso.peticiones
    assert len(p) == 1                                            # una petición, no tres
    assert p[0].full_url.endswith("/v2/matrix/foot-walking")
    assert p[0].get_header("Authorization") == CLAVE
    assert falso.cuerpo["locations"][0] == [-77.0712, -12.0912]   # [longitud, latitud]
    assert falso.cuerpo["sources"] == [0] and falso.cuerpo["destinations"] == [1, 2]


@pytest.mark.parametrize("modo, perfil", [("taxi", "driving-car"),
                                          ("auto particular", "driving-car"),
                                          ("transporte público", "driving-car")])
def test_perfil_de_cada_modo(monkeypatch, con_clave, modo, perfil):
    falso = instalar(monkeypatch, matriz_ok)
    rutas.trayectos(MAGDALENA, [SURQUILLO], modo)
    assert falso.peticiones[0].full_url.endswith("/v2/matrix/" + perfil)


def test_un_mercado_sin_ruta_va_en_linea_recta(monkeypatch, con_clave):
    instalar(monkeypatch, lambda p: {"distances": [[1.0, None]], "durations": [[60.0, None]]})
    t, aproximada = rutas.trayectos(MAGDALENA, [MAGDALENA, SURQUILLO], "taxi")
    assert aproximada
    assert (t[0].distancia_km, t[0].duracion_min) == (1.0, 1)
    assert t[1].duracion_min is None


@pytest.mark.parametrize("falla", [
    urllib.error.HTTPError("u", 403, "Forbidden", {}, None),     # clave inválida o sin cuota
    urllib.error.URLError("sin internet"),
    {"error": "otra cosa"},                                      # respuesta sin matriz
    {"distances": [[1.0]], "durations": [[60.0]]},               # matriz de otro tamaño
])
def test_si_falla_se_degrada_a_linea_recta(monkeypatch, con_clave, falla):
    instalar(monkeypatch, lambda p: falla)
    t, aproximada = rutas.trayectos(MAGDALENA, [MAGDALENA, SURQUILLO], "taxi")
    assert aproximada and all(x.duracion_min is None for x in t)


def test_si_no_responde_a_tiempo_no_espera_mas(monkeypatch, con_clave):
    monkeypatch.setattr(ors, "ESPERA_RUTAS_S", 0.2)
    instalar(monkeypatch, lambda p: time.sleep(1) or matriz_ok(p))
    inicio = time.monotonic()
    _, aproximada = rutas.trayectos(MAGDALENA, [SURQUILLO], "taxi")
    assert aproximada and time.monotonic() - inicio < 0.8          # RNF008


def test_la_bitacora_no_guarda_coordenadas(monkeypatch, con_clave, caplog):
    instalar(monkeypatch, lambda p: urllib.error.URLError("sin internet"))
    with caplog.at_level(logging.WARNING):
        rutas.trayectos(MAGDALENA, [SURQUILLO], "taxi")
    assert caplog.records and "-12.09" not in caplog.text and "-77.07" not in caplog.text


def test_comparacion_con_rutas_por_calle(cliente, escenario, monkeypatch, con_clave):
    instalar(monkeypatch, matriz_ok)
    j = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=escenario["modos"]["taxi"],
                 items=lista(escenario)).json()
    assert j["distancia_aproximada"] is False
    assert all("duracion_min" in m for m in j["mercados"])
    a = next(m for m in j["mercados"] if m["nombre"].startswith("Mercado A"))
    assert a["costo_desplazamiento"] == round(1.14 * a["distancia_km"] * 2, 2)


# -------------------------------------------------------------------- direcciones
URL = "/api/v1/direcciones"


def direcciones_ok(peticion):
    return {"features": [{"properties": {"label": "Avenida Brasil 1240, Jesús María, Lima"},
                          "geometry": {"coordinates": [-77.0476, -12.0757]}}]}


def buscar(cliente, texto):
    r = cliente.post(URL, json={"texto": texto})
    validar_respuesta("POST", "/direcciones", r)
    return r


def test_buscar_una_direccion(cliente, monkeypatch, con_clave):
    falso = instalar(monkeypatch, direcciones_ok)
    r = buscar(cliente, "  Av. Brasil 1240, Jesús María ")
    assert r.status_code == 200
    assert r.json() == [{"etiqueta": "Avenida Brasil 1240, Jesús María, Lima",
                         "latitud": -12.0757, "longitud": -77.0476}]
    url = falso.peticiones[0].full_url
    assert "/geocode/search?" in url and "text=Av.+Brasil+1240" in url
    assert "boundary.rect.min_lat=-12.55" in url and "boundary.country=PE" in url


def test_sin_resultados_es_una_lista_vacia(cliente, monkeypatch, con_clave):
    instalar(monkeypatch, lambda p: {"features": []})
    assert buscar(cliente, "calle que no existe").json() == []


def test_sin_servicio_responde_503(cliente, monkeypatch):
    falso = instalar(monkeypatch, direcciones_ok)
    r = buscar(cliente, "Av. Brasil 1240")                       # sin clave
    assert r.status_code == 503
    assert r.json()["error"]["codigo"] == "SERVICIO_NO_DISPONIBLE"
    assert falso.peticiones == []


def test_si_el_servicio_falla_responde_503(cliente, monkeypatch, con_clave):
    instalar(monkeypatch, lambda p: urllib.error.HTTPError("u", 500, "x", {}, None))
    assert buscar(cliente, "Av. Brasil 1240").status_code == 503


@pytest.mark.parametrize("texto", ["", "ab", "x" * 201])
def test_texto_no_valido(cliente, texto):
    assert buscar(cliente, texto).status_code == 422


def test_la_respuesta_de_error_no_repite_la_direccion(cliente):
    r = cliente.post(URL, json={"texto": "Jr. Secreto 123" + "x" * 200})
    assert "Secreto" not in r.text


# ------------------------------------------------------------- límite de peticiones
def test_limite_de_comparaciones(cliente, escenario):
    cuerpo = {"origen": ORIGEN, "id_modo_desplazamiento": escenario["modos"]["a pie"],
              "items": lista(escenario)}
    codigos = [cliente.post("/api/v1/comparaciones", json=cuerpo).status_code
               for _ in range(11)]
    assert codigos == [201] * 10 + [429]
    r = cliente.post("/api/v1/comparaciones", json=cuerpo)
    validar_respuesta("POST", "/comparaciones", r)
    assert r.json()["error"]["codigo"] == "DEMASIADAS_PETICIONES"


def test_limite_de_direcciones(cliente, monkeypatch, con_clave):
    instalar(monkeypatch, direcciones_ok)
    codigos = [buscar(cliente, "Av. Brasil 1240").status_code for _ in range(21)]
    assert codigos == [200] * 20 + [429]


def test_el_limite_se_libera_al_pasar_la_ventana():
    from app.core.limite import LimitePeticiones
    limite = LimitePeticiones(maximo=1, ventana_s=0.1)
    assert limite.permitir("a") and not limite.permitir("a")
    assert limite.permitir("b")                                   # otro cliente, otra cuenta
    time.sleep(0.15)
    assert limite.permitir("a")


def test_direcciones_con_otro_formato_responde_503(cliente, monkeypatch, con_clave):
    instalar(monkeypatch, lambda p: {"features": [{"properties": {}}]})
    assert buscar(cliente, "Av. Brasil 1240").status_code == 503
