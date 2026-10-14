"""Mercados minoristas del CU02, contra la base real y dentro de una transacción que se
deshace al terminar (ver conftest.py): ningún mercado de prueba queda guardado.

Los nombres llevan «(prueba)» para no chocar con los mercados reales que el
administrador ya registró: «Mercado de Magdalena» existe de verdad en la base.

Cada respuesta se valida además contra el esquema del contrato.
"""
import pytest

from pruebas.contrato import validar_respuesta

URL = "/api/v1/mercados"

MAGDALENA = {
    "nombre": "Mercado de Magdalena (prueba)", "distrito": "Magdalena del Mar",
    "direccion": "Jr. Leoncio Prado 1200", "latitud": -12.0912, "longitud": -77.0712,
    "horario_atencion": "6:00 – 18:00",
}


def crear(cliente, auth, **cambios):
    r = cliente.post(URL, headers=auth, json={**MAGDALENA, **cambios})
    validar_respuesta("POST", "/mercados", r)
    return r


def editar(cliente, auth, id_mercado, **campos):
    r = cliente.patch("%s/%d" % (URL, id_mercado), headers=auth, json=campos)
    validar_respuesta("PATCH", "/mercados/{id}", r)
    return r


def listar(cliente, headers=None, **consulta):
    r = cliente.get(URL, headers=headers or {}, params=consulta)
    validar_respuesta("GET", "/mercados", r)
    return r


# ------------------------------------------------------------------ registrar
def test_registrar_un_mercado(cliente, auth):
    r = crear(cliente, auth)
    assert r.status_code == 201
    m = r.json()
    assert m["activo"] is True
    assert {k: m[k] for k in MAGDALENA} == MAGDALENA


def test_las_coordenadas_se_guardan_con_seis_decimales(cliente, auth):
    m = crear(cliente, auth, latitud=-12.09123456789, longitud=-77.07129999).json()
    assert (m["latitud"], m["longitud"]) == (-12.091235, -77.0713)


def test_mismo_nombre_y_distrito_es_repetido_aunque_cambien_tildes_y_mayusculas(cliente, auth):
    primero = crear(cliente, auth).json()
    r = crear(cliente, auth, nombre="MERCADO DE MAGDALENA (PRUEBA) ", distrito="magdalena del mar",
              direccion="Otra dirección 123")
    assert r.status_code == 409
    e = r.json()["error"]
    assert (e["codigo"], e["mensaje"]) == ("MERCADO_YA_REGISTRADO",
                                           "El mercado ya se encuentra registrado")
    assert str(primero["id_mercado"]) in e["detalles"][0]["problema"]


def test_el_mismo_nombre_en_otro_distrito_no_es_repetido(cliente, auth):
    crear(cliente, auth)
    r = crear(cliente, auth, distrito="Jesús María", latitud=-12.0757, longitud=-77.0476)
    assert r.status_code == 201


@pytest.mark.parametrize("caso, latitud, longitud, campo_esperado", [
    ("Arequipa", -16.3989, -71.5350, "latitud"),
    ("signo olvidado en la latitud", 12.0912, -77.0712, "latitud"),
    ("longitud fuera del rectángulo", -12.0912, -76.20, "longitud"),
])
def test_coordenadas_fuera_de_lima(cliente, auth, caso, latitud, longitud, campo_esperado):
    r = crear(cliente, auth, latitud=latitud, longitud=longitud)
    assert r.status_code == 422
    e = r.json()["error"]
    assert e["mensaje"] == "Las coordenadas no corresponden a Lima Metropolitana"   # EX2
    assert e["detalles"][0]["campo"] == campo_esperado


def test_coordenadas_intercambiadas_se_avisan_como_tales(cliente, auth):
    r = crear(cliente, auth, latitud=-77.0712, longitud=-12.0912)
    assert r.status_code == 422
    assert r.json()["error"]["detalles"] == [
        {"campo": "latitud", "problema": "parece estar intercambiada con la longitud"}]


def test_el_callao_esta_dentro(cliente, auth):
    r = crear(cliente, auth, nombre="Mercado Central del Callao (prueba)", distrito="Callao",
              latitud=-12.0566, longitud=-77.1181)
    assert r.status_code == 201


def test_campos_obligatorios_vacios_o_faltantes(cliente, auth):
    r = cliente.post(URL, headers=auth, json={"nombre": "   ", "latitud": -12.09,
                                              "longitud": -77.07})
    assert r.status_code == 422
    detalles = {d["campo"]: d["problema"] for d in r.json()["error"]["detalles"]}
    assert detalles == {"nombre": "es obligatorio", "distrito": "es obligatorio",
                        "direccion": "es obligatorio"}


def test_el_horario_es_opcional(cliente, auth):
    datos = {k: v for k, v in MAGDALENA.items() if k != "horario_atencion"}
    r = cliente.post(URL, headers=auth, json=datos)
    assert r.status_code == 201 and r.json()["horario_atencion"] is None


# --------------------------------------------------------------------- consultar
def test_el_consumidor_no_ve_los_desactivados(cliente, auth):
    m = crear(cliente, auth).json()
    editar(cliente, auth, m["id_mercado"], activo=False)
    nombres = [x["nombre"] for x in listar(cliente).json()]
    assert MAGDALENA["nombre"] not in nombres
    r = cliente.get("%s/%d" % (URL, m["id_mercado"]))
    assert r.status_code == 404                                   # RN11


def test_el_administrador_si_los_ve(cliente, auth):
    m = crear(cliente, auth).json()
    editar(cliente, auth, m["id_mercado"], activo=False)
    todos = listar(cliente, auth, incluir_inactivos="true").json()
    assert any(x["id_mercado"] == m["id_mercado"] and not x["activo"] for x in todos)
    r = cliente.get("%s/%d" % (URL, m["id_mercado"]), headers=auth)
    validar_respuesta("GET", "/mercados/{id}", r)
    assert r.status_code == 200 and r.json()["activo"] is False


def test_pedir_los_inactivos_sin_sesion_responde_401(cliente):
    assert listar(cliente, incluir_inactivos="true").status_code == 401


def test_un_token_invalido_no_se_ignora_en_silencio(cliente):
    r = listar(cliente, {"Authorization": "Bearer token-falso"})
    assert r.status_code == 401


def test_filtrar_por_distrito_sin_importar_tildes(cliente, auth):
    crear(cliente, auth)
    crear(cliente, auth, nombre="Mercado N.° 1 de Surquillo (prueba)", distrito="Surquillo",
          latitud=-12.1124, longitud=-77.0228)
    r = listar(cliente, distrito="MAGDALENA DEL MAR")
    nombres = [m["nombre"] for m in r.json()]
    assert MAGDALENA["nombre"] in nombres
    assert all(m["distrito"] == "Magdalena del Mar" for m in r.json())


def test_detalle_publico_de_un_mercado_activo(cliente, auth):
    m = crear(cliente, auth).json()
    r = cliente.get("%s/%d" % (URL, m["id_mercado"]))
    validar_respuesta("GET", "/mercados/{id}", r)
    assert r.status_code == 200 and r.json()["nombre"] == MAGDALENA["nombre"]


# ------------------------------------------------------------- modificar (FA1)
def test_modificar_solo_lo_que_cambia(cliente, auth):
    m = crear(cliente, auth).json()
    r = editar(cliente, auth, m["id_mercado"], direccion="Av. Brasil 2500")
    assert r.status_code == 200
    assert r.json()["direccion"] == "Av. Brasil 2500"
    assert r.json()["nombre"] == MAGDALENA["nombre"]             # lo demás, intacto


def test_cambiar_solo_la_latitud_se_valida_con_la_longitud_que_ya_tenia(cliente, auth):
    m = crear(cliente, auth).json()
    assert editar(cliente, auth, m["id_mercado"], latitud=-12.10).status_code == 200
    assert editar(cliente, auth, m["id_mercado"], latitud=-16.39).status_code == 422


def test_renombrar_como_otro_mercado_del_mismo_distrito_responde_409(cliente, auth):
    crear(cliente, auth)
    otro = crear(cliente, auth, nombre="Mercado Modelo (prueba)", latitud=-12.0950).json()
    r = editar(cliente, auth, otro["id_mercado"], nombre="mercado de magdalena (prueba)")
    assert r.status_code == 409


def test_renombrar_cambiando_solo_mayusculas_no_choca_consigo_mismo(cliente, auth):
    m = crear(cliente, auth).json()
    assert editar(cliente, auth, m["id_mercado"], nombre="MERCADO DE MAGDALENA (PRUEBA)").status_code == 200


def test_borrar_el_horario_con_null(cliente, auth):
    m = crear(cliente, auth).json()
    assert editar(cliente, auth, m["id_mercado"], horario_atencion=None).json()[
        "horario_atencion"] is None


@pytest.mark.parametrize("cuerpo", [{}, {"nombre": None}, {"nombre": "  "}])
def test_modificacion_no_valida(cliente, auth, cuerpo):
    m = crear(cliente, auth).json()
    assert editar(cliente, auth, m["id_mercado"], **cuerpo).status_code == 422


def test_desactivar_conserva_el_mercado(cliente, auth, sesion_aislada):
    from app.modelos import Mercado
    m = crear(cliente, auth).json()
    r = editar(cliente, auth, m["id_mercado"], activo=False)
    assert r.status_code == 200 and r.json()["activo"] is False
    assert sesion_aislada.get(Mercado, m["id_mercado"]) is not None   # no se borró


def test_mercado_inexistente(cliente, auth):
    assert editar(cliente, auth, 999_999_999, activo=False).status_code == 404
    assert cliente.get(URL + "/999999999").status_code == 404


def test_registrar_y_modificar_exigen_sesion(cliente):
    assert cliente.post(URL, json=MAGDALENA).status_code == 401
    assert cliente.patch(URL + "/1", json={"activo": False}).status_code == 401
