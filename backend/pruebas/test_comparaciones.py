"""Catálogo y costo total de compra del CU05, contra la base real y dentro de una
transacción que se deshace al terminar (ver conftest.py).

El escenario se arma dentro de esa transacción: se desactivan los mercados reales, se
reemplazan las tarifas por unas conocidas y se crean tres mercados de prueba alrededor
de un punto de partida, con precios por mercado. Nada de eso queda guardado.

Cada respuesta se valida además contra el esquema del contrato.
"""
import secrets
from datetime import date, timedelta

import pytest
from sqlalchemy import delete, select, update

from app.modelos import (CargaArchivo, Mercado, ModoDesplazamiento, PrecioMercado,
                         Tarifa, Variedad)
from app.servicios.rutas import Punto, linea_recta
from app.servicios.tarifas import hoy
from pruebas.contrato import validar_respuesta

URL = "/api/v1/comparaciones"
ORIGEN = {"latitud": -12.0900, "longitud": -77.0500}

# 0.009° de latitud son casi exactamente 1 km.
A = (-12.0810, -77.0500)       # ~1 km
B = (-12.0720, -77.0500)       # ~2 km
C = (-12.0450, -77.0500)       # ~5 km: fuera del radio por defecto


def km(punto) -> float:
    return linea_recta(Punto(ORIGEN["latitud"], ORIGEN["longitud"]), Punto(*punto))


@pytest.fixture
def escenario(sesion_aislada, admin):
    s = sesion_aislada
    s.execute(update(Mercado).values(activo=False))                  # los reales, fuera
    modos = {m.nombre: m.id_modo_desplazamiento for m in s.scalars(select(ModoDesplazamiento))}
    s.execute(delete(Tarifa).where(Tarifa.id_modo_desplazamiento != modos["a pie"]))
    desde = hoy() - timedelta(days=1)
    s.add_all([
        Tarifa(id_modo_desplazamiento=modos["transporte público"], tipo_cobro="fijo",
               monto=2.50, vigente_desde=desde),
        Tarifa(id_modo_desplazamiento=modos["taxi"], tipo_cobro="por_km", monto=1.14,
               vigente_desde=desde),
    ])                                                              # auto: sin tarifa

    def mercado(nombre, punto, activo=True):
        m = Mercado(nombre=nombre + " (prueba)", distrito="Lince", direccion="Av. 1",
                    latitud=punto[0], longitud=punto[1], activo=activo)
        s.add(m)
        return m

    a, b, c = mercado("Mercado A", A), mercado("Mercado B", B), mercado("Mercado C", C)
    inactivo = mercado("Mercado inactivo", A, activo=False)
    carga = CargaArchivo(id_usuario=admin.id_usuario, nombre_archivo="prueba.xls",
                         hash_archivo=secrets.token_hex(32), fuente="precios por mercado",
                         registros_validos=4, registros_rechazados=0, estado="confirmada")
    s.add(carga)
    s.flush()

    var = {v.nombre: v.id_variedad for v in s.scalars(select(Variedad))}
    papa, arroz = var["Papa amarilla"], var["Arroz superior"]

    def precio(m, variedad, monto, dias_atras=0):
        s.add(PrecioMercado(id_mercado=m.id_mercado, id_variedad=variedad,
                            id_carga_archivo=carga.id_carga_archivo,
                            fecha=date(2026, 10, 12) - timedelta(days=dias_atras),
                            precio_kg=monto))

    precio(a, papa, 3.00, dias_atras=7)          # precio viejo: no debe usarse (RN03)
    precio(a, papa, 2.00)
    precio(a, arroz, 4.00)
    precio(b, papa, 1.50)                        # en B no hay arroz
    precio(c, papa, 1.00)
    precio(c, arroz, 1.00)
    precio(inactivo, papa, 0.10)
    s.flush()
    return {"modos": modos, "papa": papa, "arroz": arroz, "a": a, "b": b, "c": c,
            "inactivo": inactivo}


def comparar(cliente, **cuerpo):
    r = cliente.post(URL, json=cuerpo)
    validar_respuesta("POST", "/comparaciones", r)
    return r


def lista(e, papa=2.0, arroz=1.0):
    return [{"id_variedad": e["papa"], "cantidad_kg": papa},
            {"id_variedad": e["arroz"], "cantidad_kg": arroz}]


def por_nombre(r) -> dict:
    return {m["nombre"].replace(" (prueba)", ""): m for m in r.json()["mercados"]}


# ------------------------------------------------------------------------ catálogo
def test_productos_activos_y_busqueda_sin_tildes(cliente):
    r = cliente.get("/api/v1/productos")
    validar_respuesta("GET", "/productos", r)
    assert "Papa" in [p["nombre"] for p in r.json()]
    r = cliente.get("/api/v1/productos", params={"buscar": "AZUCAR"})
    assert [p["nombre"] for p in r.json()] == ["Azúcar"]
    assert cliente.get("/api/v1/productos", params={"buscar": "caviar"}).json() == []


def test_variedades_de_un_producto_con_su_unidad(cliente, sesion_aislada):
    papa = sesion_aislada.scalars(select(Variedad).where(Variedad.nombre == "Papa amarilla")).one()
    r = cliente.get("/api/v1/productos/%d/variedades" % papa.id_producto)
    validar_respuesta("GET", "/productos/{id}/variedades", r)
    v = next(x for x in r.json() if x["nombre"] == "Papa amarilla")
    assert (v["unidad_origen"], v["factor_a_kg"]) == ("kilogramo", 1.0)


def test_variedades_de_un_producto_inexistente(cliente):
    r = cliente.get("/api/v1/productos/999999/variedades")
    validar_respuesta("GET", "/productos/{id}/variedades", r)
    assert r.status_code == 404


# ------------------------------------------------------------------- costo total
def test_costo_total_por_mercado_en_taxi(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["taxi"],
                 items=lista(e))
    assert r.status_code == 201
    j = r.json()
    assert j["distancia_aproximada"] is True                      # EX4: línea recta
    m = por_nombre(r)
    assert set(m) == {"Mercado A", "Mercado B"}                   # C fuera de 3 km
    a = m["Mercado A"]
    assert a["costo_productos"] == 8.00                           # 2 kg × 2.00 + 1 × 4.00
    assert a["costo_desplazamiento"] == round(1.14 * km(A) * 2, 2)  # ida y vuelta
    assert a["costo_total"] == round(a["costo_productos"] + a["costo_desplazamiento"], 2)
    assert a["distancia_km"] == round(km(A), 2)
    assert "duracion_min" not in a                                # sin servicio de rutas
    assert a["sin_precio"] == [] and m["Mercado B"]["sin_precio"] == [e["arroz"]]


def test_el_precio_vigente_es_el_mas_reciente(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["a pie"],
                 items=[{"id_variedad": e["papa"], "cantidad_kg": 1}])
    assert por_nombre(r)["Mercado A"]["costo_productos"] == 2.00   # no 3.00 (RN03)


def test_un_mercado_al_que_le_faltan_precios_no_queda_primero(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["taxi"],
                 items=lista(e))
    nombres = [x["nombre"] for x in r.json()["mercados"]]
    m = por_nombre(r)
    assert m["Mercado B"]["costo_total"] < m["Mercado A"]["costo_total"]
    assert nombres == ["Mercado A (prueba)", "Mercado B (prueba)"]


def test_el_pasaje_fijo_se_paga_ida_y_vuelta_sin_importar_la_distancia(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["transporte público"],
                 items=lista(e))
    assert {x["costo_desplazamiento"] for x in r.json()["mercados"]} == {5.00}


def test_a_pie_no_cuesta(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["a pie"],
                 items=lista(e))
    assert {x["costo_desplazamiento"] for x in r.json()["mercados"]} == {0.0}


def test_el_radio_amplia_la_busqueda_y_excluye_los_inactivos(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["a pie"],
                 radio_km=6, items=lista(e))
    assert set(por_nombre(r)) == {"Mercado A", "Mercado B", "Mercado C"}


def test_sin_mercados_en_el_radio(cliente, escenario):
    e = escenario
    lejos = {"latitud": -12.40, "longitud": -76.78}
    r = comparar(cliente, origen=lejos, id_modo_desplazamiento=e["modos"]["a pie"],
                 items=lista(e))
    assert r.status_code == 201                                   # EX3 lo dice la app
    assert r.json()["mercados"] == [] and "referencia" not in r.json()


def test_ahorro_frente_al_promedio_de_los_cercanos(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["a pie"],
                 items=lista(e))
    j = r.json()
    totales = [m["costo_total"] for m in j["mercados"]]
    assert j["referencia"] == {"tipo": "promedio de cercanos",
                               "costo_total": round(sum(totales) / len(totales), 2)}
    for m in j["mercados"]:
        assert m["ahorro_neto"] == round(j["referencia"]["costo_total"] - m["costo_total"], 2)


def test_ahorro_frente_al_mercado_habitual_aunque_este_lejos(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["taxi"],
                 id_mercado_habitual=e["c"].id_mercado, items=lista(e))
    j = r.json()
    costo_c = round(2.00 + round(1.14 * km(C) * 2, 2), 2)          # 2 × 1.00 + 1 × 1.00 = 3
    assert j["referencia"]["tipo"] == "mercado habitual"
    assert j["referencia"]["id_mercado"] == e["c"].id_mercado
    assert j["referencia"]["costo_total"] == pytest.approx(costo_c + 1.00, abs=0.011)
    assert "Mercado C" not in por_nombre(r)                       # no está en el radio


def test_la_recomendacion_aun_no_esta_disponible(cliente, escenario):
    e = escenario
    j = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["a pie"],
                 items=lista(e)).json()
    assert j["recomendacion"]["disponible"] is False
    assert j["recomendacion"]["productos_sin_tendencia"] == 2


# --------------------------------------------------------------------- validaciones
def test_un_modo_sin_tarifa(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["auto particular"],
                 items=lista(e))
    assert r.status_code == 422
    assert r.json()["error"]["codigo"] == "TARIFA_NO_CONFIGURADA"


def test_mercado_habitual_inactivo(cliente, escenario):
    e = escenario
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["a pie"],
                 id_mercado_habitual=e["inactivo"].id_mercado, items=lista(e))
    assert r.status_code == 422
    assert r.json()["error"]["detalles"][0]["campo"] == "id_mercado_habitual"


def test_variedades_repetidas_o_inexistentes(cliente, escenario):
    e = escenario
    items = [{"id_variedad": e["papa"], "cantidad_kg": 1},
             {"id_variedad": e["papa"], "cantidad_kg": 2},
             {"id_variedad": 999999, "cantidad_kg": 1}]
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=e["modos"]["a pie"],
                 items=items)
    assert r.status_code == 422
    assert [d["campo"] for d in r.json()["error"]["detalles"]] == [
        "items.1.id_variedad", "items.2.id_variedad"]


@pytest.mark.parametrize("cambio, campo", [
    ({"items": []}, "items"),                                     # EX1 lo dice la app
    ({"items": [{"id_variedad": 1, "cantidad_kg": 0}]}, "items.0.cantidad_kg"),
    ({"radio_km": 25}, "radio_km"),
    ({"origen": {"latitud": 95, "longitud": -77}}, "origen.latitud"),
])
def test_datos_no_validos(cliente, escenario, cambio, campo):
    e = escenario
    cuerpo = {"origen": ORIGEN, "id_modo_desplazamiento": e["modos"]["a pie"],
              "items": lista(e), **cambio}
    r = comparar(cliente, **cuerpo)
    assert r.status_code == 422
    assert campo in [d["campo"] for d in r.json()["error"]["detalles"]]


def test_la_respuesta_de_error_no_repite_la_ubicacion(cliente, escenario):
    # RNF003: la ubicación del consumidor no se devuelve ni se registra.
    r = cliente.post(URL, json={"origen": {"latitud": 95.123456, "longitud": -77.0},
                                "id_modo_desplazamiento": 1, "items": []})
    assert "95.123456" not in r.text


def test_modo_inexistente(cliente, escenario):
    r = comparar(cliente, origen=ORIGEN, id_modo_desplazamiento=99, items=lista(escenario))
    assert r.status_code == 422 and r.json()["error"]["codigo"] == "MODO_NO_VALIDO"
