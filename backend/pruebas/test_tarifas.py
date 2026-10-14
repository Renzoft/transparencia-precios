"""Modos de desplazamiento y tarifas del CU02, contra la base real y dentro de una
transacción que se deshace al terminar (ver conftest.py).

Cada prueba parte de un estado conocido: el fixture «limpio» quita, dentro de esa
transacción, las tarifas de los modos con costo. Así las pruebas no dependen de las
tarifas reales que el administrador haya registrado, y tampoco las tocan.

Cada respuesta se valida además contra el esquema del contrato.
"""
from datetime import timedelta

import pytest
from sqlalchemy import delete, select

from app.modelos import ModoDesplazamiento, Tarifa
from app.servicios.tarifas import hoy
from pruebas.contrato import validar_respuesta

URL = "/api/v1/tarifas"


@pytest.fixture
def modo(sesion_aislada) -> dict:
    """Identificador de cada modo por su nombre."""
    return {m.nombre: m.id_modo_desplazamiento
            for m in sesion_aislada.scalars(select(ModoDesplazamiento))}


@pytest.fixture
def limpio(sesion_aislada, modo):
    sesion_aislada.execute(delete(Tarifa).where(Tarifa.id_modo_desplazamiento != modo["a pie"]))
    sesion_aislada.flush()


def dia(n: int = 0) -> str:
    return (hoy() + timedelta(days=n)).isoformat()


def registrar(cliente, auth, id_modo, tipo, monto, desde):
    r = cliente.post(URL, headers=auth, json={"id_modo_desplazamiento": id_modo,
                                              "tipo_cobro": tipo, "monto": monto,
                                              "vigente_desde": desde})
    validar_respuesta("POST", "/tarifas", r)
    return r


def pasaje(cliente, auth, modo, monto=2.50, desde=None):
    return registrar(cliente, auth, modo["transporte público"], "fijo", monto,
                     desde or dia())


def listar(cliente, auth, **consulta):
    r = cliente.get(URL, headers=auth, params=consulta)
    validar_respuesta("GET", "/tarifas", r)
    return r


# ---------------------------------------------------------- modos de desplazamiento
def test_los_cuatro_modos_son_publicos(cliente):
    r = cliente.get("/api/v1/modos-desplazamiento")
    validar_respuesta("GET", "/modos-desplazamiento", r)
    assert r.status_code == 200
    assert [m["nombre"] for m in r.json()] == ["a pie", "transporte público", "taxi",
                                               "auto particular"]


def test_un_modo_inactivo_no_se_lista_ni_admite_tarifas(cliente, auth, sesion_aislada, modo,
                                                         limpio):
    sesion_aislada.get(ModoDesplazamiento, modo["taxi"]).activo = False
    sesion_aislada.flush()
    nombres = [m["nombre"] for m in cliente.get("/api/v1/modos-desplazamiento").json()]
    assert "taxi" not in nombres
    r = registrar(cliente, auth, modo["taxi"], "por_km", 1.80, dia())
    assert r.status_code == 422 and r.json()["error"]["codigo"] == "MODO_NO_VALIDO"


def test_modo_inexistente(cliente, auth):
    r = registrar(cliente, auth, 999, "fijo", 1.00, dia())
    assert r.status_code == 422
    assert r.json()["error"]["detalles"][0]["campo"] == "id_modo_desplazamiento"


# ---------------------------------------------------------------- registrar tarifas
def test_primera_tarifa_de_un_modo(cliente, auth, modo, limpio):
    r = pasaje(cliente, auth, modo)
    assert r.status_code == 201
    t = r.json()
    assert (t["monto"], t["tipo_cobro"], t["vigente_desde"]) == (2.5, "fijo", dia())
    assert t["vigente_hasta"] is None and t["tarifa_cerrada"] is None


def test_una_tarifa_nueva_cierra_la_anterior(cliente, auth, modo, limpio):
    primera = pasaje(cliente, auth, modo).json()
    r = pasaje(cliente, auth, modo, monto=3.00, desde=dia(1))
    assert r.status_code == 201 and r.json()["tarifa_cerrada"] == primera["id_tarifa"]

    historia = {t["id_tarifa"]: t for t in listar(cliente, auth).json()}
    assert historia[primera["id_tarifa"]]["vigente_hasta"] == dia(1)     # se cerró
    assert historia[primera["id_tarifa"]]["monto"] == 2.5                # no se editó


def test_dos_cambios_el_mismo_dia_se_rechazan_sin_tocar_nada(cliente, auth, modo, limpio):
    primera = pasaje(cliente, auth, modo).json()
    r = pasaje(cliente, auth, modo, monto=3.00)
    assert r.status_code == 409
    e = r.json()["error"]
    assert (e["codigo"], e["mensaje"]) == ("TARIFA_SOLAPADA",
                                           "Ya existe una tarifa vigente para ese modo en "
                                           "esa fecha.")
    assert str(primera["id_tarifa"]) in e["detalles"][0]["problema"]
    vigentes = listar(cliente, auth, vigentes="true").json()
    assert [t["monto"] for t in vigentes
            if t["id_modo_desplazamiento"] == modo["transporte público"]] == [2.5]


def test_una_vigencia_anterior_a_la_abierta_se_rechaza(cliente, auth, modo, limpio):
    pasaje(cliente, auth, modo, desde=dia(10))
    assert pasaje(cliente, auth, modo, desde=dia(5)).status_code == 409


def test_la_base_tambien_impide_el_solape(cliente, auth, sesion_aislada, modo, limpio):
    # Una vigencia ya cerrada en el futuro, sin ninguna abierta: el servicio no tiene qué
    # cerrar, y la nueva [hoy+5, ∞) choca con [hoy+10, hoy+20). Lo detecta la restricción
    # de exclusión de la base.
    sesion_aislada.add(Tarifa(id_modo_desplazamiento=modo["taxi"], tipo_cobro="por_km",
                              monto=2, vigente_desde=hoy() + timedelta(days=10),
                              vigente_hasta=hoy() + timedelta(days=20)))
    sesion_aislada.flush()
    r = registrar(cliente, auth, modo["taxi"], "por_km", 1.80, dia(5))
    assert r.status_code == 409 and r.json()["error"]["codigo"] == "TARIFA_SOLAPADA"


def test_no_se_registra_una_tarifa_en_el_pasado(cliente, auth, modo, limpio):
    r = pasaje(cliente, auth, modo, desde=dia(-1))
    assert r.status_code == 422
    assert r.json()["error"]["detalles"][0]["campo"] == "vigente_desde"


def test_a_pie_siempre_cuesta_cero(cliente, auth, modo):
    r = registrar(cliente, auth, modo["a pie"], "fijo", 0, dia(1))
    assert r.status_code == 422
    assert r.json()["error"]["codigo"] == "TARIFA_NO_MODIFICABLE"            # RN07


@pytest.mark.parametrize("nombre, tipo", [("transporte público", "por_km"),
                                          ("taxi", "fijo"), ("auto particular", "fijo")])
def test_cada_modo_tiene_su_tipo_de_cobro(cliente, auth, modo, limpio, nombre, tipo):
    r = registrar(cliente, auth, modo[nombre], tipo, 1.50, dia())
    assert r.status_code == 422
    assert r.json()["error"]["detalles"] == [
        {"campo": "tipo_cobro",
         "problema": "para %s debe ser «%s»" % (nombre, "fijo" if tipo == "por_km"
                                                   else "por_km")}]


@pytest.mark.parametrize("monto, problema", [
    (-1, "debe ser mayor o igual que 0"),                                    # EX4
    ("dos soles", "debe ser un número"),                                     # EX4
    (2.505, "no puede tener más de 2 decimales"),
    (1_000_000, "debe ser menor o igual que 999999.99"),
])
def test_montos_no_validos(cliente, auth, modo, limpio, monto, problema):
    r = pasaje(cliente, auth, modo, monto=monto)
    assert r.status_code == 422
    assert r.json()["error"]["detalles"] == [{"campo": "monto", "problema": problema}]


def test_un_monto_de_cero_es_valido(cliente, auth, modo, limpio):
    assert registrar(cliente, auth, modo["auto particular"], "por_km", 0,
                     dia()).status_code == 201


# ------------------------------------------------------------------ consultar tarifas
def test_vigentes_son_las_que_rigen_hoy(cliente, auth, modo, limpio):
    hoy_taxi = registrar(cliente, auth, modo["taxi"], "por_km", 1.80, dia()).json()
    futura = registrar(cliente, auth, modo["taxi"], "por_km", 2.00, dia(10)).json()
    pasaje(cliente, auth, modo)

    ids = {t["id_tarifa"] for t in listar(cliente, auth, vigentes="true").json()}
    assert hoy_taxi["id_tarifa"] in ids          # cerrada a futuro, pero rige hoy
    assert futura["id_tarifa"] not in ids        # programada: todavía no rige
    todas = {t["id_tarifa"] for t in listar(cliente, auth).json()}
    assert {hoy_taxi["id_tarifa"], futura["id_tarifa"]} <= todas


def test_la_tarifa_a_pie_figura_entre_las_vigentes(cliente, auth, modo):
    vigentes = listar(cliente, auth, vigentes="true").json()
    a_pie = [t for t in vigentes if t["id_modo_desplazamiento"] == modo["a pie"]]
    assert [(t["monto"], t["tipo_cobro"]) for t in a_pie] == [(0.0, "fijo")]


def test_la_lista_no_trae_tarifa_cerrada(cliente, auth, modo, limpio):
    pasaje(cliente, auth, modo)
    assert all("tarifa_cerrada" not in t and "vigente_hasta" in t
               for t in listar(cliente, auth).json())


def test_las_tarifas_exigen_sesion(cliente, modo):
    assert cliente.get(URL).status_code == 401
    r = cliente.post(URL, json={"id_modo_desplazamiento": modo["taxi"],
                                "tipo_cobro": "por_km", "monto": 1, "vigente_desde": dia()})
    assert r.status_code == 401


def test_hoy_es_la_fecha_de_lima():
    from datetime import datetime, timezone
    assert hoy() == (datetime.now(timezone.utc) - timedelta(hours=5)).date()
