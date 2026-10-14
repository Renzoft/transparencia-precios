"""Carga de precios del CU01, de punta a punta y contra la base real.

Cada prueba corre dentro de una transacción que se deshace al final (ver conftest.py),
así que se puede confirmar cargas e insertar precios sin dejar nada en la base.

Los números esperados salen de los archivos reales y de lo que ya hay cargado: la base
tiene precios hasta el 30/09/2026 y los archivos cubren del 01/09 al 13/10. En el de
ciudades del tomate eso da 43 registros mayoristas (30 de septiembre, ya cargados, y 13
de octubre) y 18 minoristas (13 y 5): 18 nuevos y 43 duplicados.

Cada respuesta se valida además contra el esquema del contrato.
"""
import re

import pytest
from sqlalchemy import func, select

from app.modelos import CargaArchivo, PrecioSerie, Producto, Variedad
from pruebas.contrato import validar_respuesta
from pruebas.test_lector_sisap import MAYORISTA_TOMATE, PAPA, TOMATE

URL = "/api/v1/cargas"


def subir(cliente, auth, contenido: bytes, fuente="SISAP minorista", nombre="reporte.xls"):
    r = cliente.post(URL, headers=auth, data={"fuente": fuente},
                     files={"archivo": (nombre, contenido, "application/vnd.ms-excel")})
    validar_respuesta("POST", "/cargas", r)
    return r


def resolver(cliente, auth, id_carga, estado):
    r = cliente.patch("%s/%d" % (URL, id_carga), headers=auth, json={"estado": estado})
    validar_respuesta("PATCH", "/cargas/{id}", r)
    return r


def detalle(cliente, auth, id_carga):
    r = cliente.get("%s/%d" % (URL, id_carga), headers=auth)
    validar_respuesta("GET", "/cargas/{id}", r)
    return r


def precios_de(sesion, id_carga):
    return sesion.scalar(select(func.count()).select_from(PrecioSerie)
                         .where(PrecioSerie.id_carga_archivo == id_carga))


def _texto(ruta):
    return ruta.read_bytes().decode("latin-1")


# ------------------------------------------------------------- paso 1: subir el archivo
def test_subir_devuelve_el_resumen_sin_guardar_precios(cliente, auth, sesion_aislada):
    r = subir(cliente, auth, TOMATE.read_bytes(), nombre="tomate.xls")
    assert r.status_code == 201
    c = r.json()
    assert c["estado"] == "pendiente"
    assert c["nombre_archivo"] == "tomate.xls"
    assert c["periodo"] == {"desde": "2026-09-01", "hasta": "2026-10-13"}
    assert (c["registros_validos"], c["registros_rechazados"]) == (18, 43)
    assert c["rechazos"] == [{"motivo": "duplicado", "cantidad": 43}]
    assert c["catalogo_nuevo"] == {"productos": [], "variedades": []}
    # El contrato es explícito: subir no guarda precios.
    assert precios_de(sesion_aislada, c["id_carga_archivo"]) == 0


def test_se_guarda_el_archivo_original(cliente, auth, sesion_aislada):
    contenido = TOMATE.read_bytes()
    c = subir(cliente, auth, contenido).json()
    carga = sesion_aislada.get(CargaArchivo, c["id_carga_archivo"])
    assert carga.contenido_archivo == contenido


def test_el_mismo_archivo_dos_veces_responde_409(cliente, auth):
    primera = subir(cliente, auth, TOMATE.read_bytes()).json()
    r = subir(cliente, auth, TOMATE.read_bytes(), nombre="otro-nombre.xls")
    assert r.status_code == 409
    assert r.json()["error"]["codigo"] == "ARCHIVO_YA_CARGADO"
    assert str(primera["id_carga_archivo"]) in r.json()["error"]["mensaje"]


def test_archivo_sin_registros_nuevos_no_guarda_nada(cliente, auth, sesion_aislada):
    # Solo septiembre: todo está ya en la base. CU01, EX3.
    t = re.sub(r"<tr class=contenido><td>\d\d/10/2026</td>.*?</tr>", "", _texto(TOMATE))
    antes = sesion_aislada.scalar(select(func.count()).select_from(CargaArchivo))
    r = subir(cliente, auth, t.encode("latin-1"))
    assert r.status_code == 422
    assert r.json()["error"]["mensaje"] == "El archivo no contiene registros válidos"
    assert r.json()["error"]["detalles"] == [{"campo": "archivo", "problema": "43 duplicado"}]
    assert sesion_aislada.scalar(select(func.count()).select_from(CargaArchivo)) == antes


@pytest.mark.parametrize("contenido, fuente", [
    (b"no soy un archivo del SISAP", "SISAP minorista"),
    (b"", "SISAP minorista"),
    (TOMATE.read_bytes(), "SISAP mayorista"),
    (TOMATE.read_bytes(), "precios por mercado"),
], ids=["texto cualquiera", "archivo vacío", "fuente equivocada", "fuente sin formato"])
def test_formato_no_valido_responde_400(cliente, auth, contenido, fuente):
    r = subir(cliente, auth, contenido, fuente)
    assert r.status_code == 400
    e = r.json()["error"]
    assert (e["codigo"], e["mensaje"]) == ("FORMATO_NO_VALIDO",
                                           "El archivo no corresponde al formato esperado")
    assert e["detalles"][0]["campo"] == "archivo"


def test_archivo_demasiado_grande(cliente, auth):
    r = subir(cliente, auth, b"x" * (5 * 1024 * 1024 + 1))
    assert r.status_code == 422
    assert r.json()["error"]["codigo"] == "ARCHIVO_DEMASIADO_GRANDE"


def test_fuente_desconocida_y_archivo_faltante(cliente, auth):
    r = cliente.post(URL, headers=auth, data={"fuente": "otra cosa"},
                     files={"archivo": ("a.xls", b"x", "application/vnd.ms-excel")})
    assert r.status_code == 422
    assert r.json()["error"]["detalles"][0]["campo"] == "fuente"
    r = cliente.post(URL, headers=auth, data={"fuente": "SISAP minorista"})
    assert r.status_code == 422
    assert r.json()["error"]["detalles"] == [{"campo": "archivo", "problema": "es obligatorio"}]


# ---------------------------------------------------- paso 2: confirmar o descartar
def test_confirmar_guarda_los_precios(cliente, auth, sesion_aislada):
    c = subir(cliente, auth, TOMATE.read_bytes()).json()
    r = resolver(cliente, auth, c["id_carga_archivo"], "confirmada")
    assert r.status_code == 200
    assert r.json()["estado"] == "confirmada"
    assert r.json()["precios_guardados"] == 18
    assert precios_de(sesion_aislada, c["id_carga_archivo"]) == 18
    d = detalle(cliente, auth, c["id_carga_archivo"]).json()
    # Ya confirmada, el catálogo nuevo no aplica: el campo se omite (el contrato no
    # admite null en él).
    assert d["estado"] == "confirmada" and "catalogo_nuevo" not in d


def test_el_modulo_mayorista_guarda_el_volumen(cliente, auth, sesion_aislada):
    c = subir(cliente, auth, MAYORISTA_TOMATE.read_bytes(), "SISAP mayorista").json()
    assert (c["registros_validos"], c["registros_rechazados"]) == (13, 30)
    resolver(cliente, auth, c["id_carga_archivo"], "confirmada")
    volumenes = sesion_aislada.scalars(
        select(PrecioSerie.volumen_t).where(PrecioSerie.id_carga_archivo == c["id_carga_archivo"]))
    assert all(v is not None for v in volumenes)


def test_descartar_no_guarda_nada(cliente, auth, sesion_aislada):
    c = subir(cliente, auth, TOMATE.read_bytes()).json()
    r = resolver(cliente, auth, c["id_carga_archivo"], "descartada")
    assert r.json()["precios_guardados"] == 0
    assert precios_de(sesion_aislada, c["id_carga_archivo"]) == 0


def test_una_carga_se_resuelve_una_sola_vez(cliente, auth):
    c = subir(cliente, auth, TOMATE.read_bytes()).json()
    resolver(cliente, auth, c["id_carga_archivo"], "descartada")
    r = resolver(cliente, auth, c["id_carga_archivo"], "confirmada")
    assert r.status_code == 409
    assert r.json()["error"]["codigo"] == "CARGA_YA_RESUELTA"
    # Y el mismo archivo tampoco se puede volver a subir: su huella ya está registrada.
    r = subir(cliente, auth, TOMATE.read_bytes())
    assert r.status_code == 409 and "descartada" in r.json()["error"]["mensaje"]


def test_al_confirmar_se_recalcula_lo_que_falta(cliente, auth, sesion_aislada):
    # Se sube el de ciudades, pero antes de confirmarlo se carga el del módulo mayorista,
    # que trae los mismos 13 días de octubre. Al confirmar el primero, esos 13 ya no son
    # nuevos: se guardan solo los 5 minoristas y la carga lo dice así.
    ciudades = subir(cliente, auth, TOMATE.read_bytes()).json()
    assert ciudades["registros_validos"] == 18
    mayorista = subir(cliente, auth, MAYORISTA_TOMATE.read_bytes(), "SISAP mayorista").json()
    resolver(cliente, auth, mayorista["id_carga_archivo"], "confirmada")

    r = resolver(cliente, auth, ciudades["id_carga_archivo"], "confirmada")
    assert r.json()["precios_guardados"] == 5
    d = detalle(cliente, auth, ciudades["id_carga_archivo"]).json()
    assert (d["registros_validos"], d["registros_rechazados"]) == (5, 56)
    assert d["rechazos"] == [{"motivo": "duplicado", "cantidad": 56}]


def test_variedad_nueva_de_un_producto_existente(cliente, auth, sesion_aislada):
    t = _texto(TOMATE).replace("<td colspan=10>Tomate</td>", "<td colspan=10>Tomate marzano</td>", 1)
    c = subir(cliente, auth, t.encode("latin-1")).json()
    # Nada de esta variedad existe aún, así que todo es nuevo.
    assert (c["registros_validos"], c["registros_rechazados"]) == (61, 0)
    assert c["catalogo_nuevo"] == {"productos": [], "variedades": ["Tomate marzano"]}
    # Al subir no se crea nada: si se descartara, el catálogo quedaría intacto.
    assert sesion_aislada.scalar(select(Variedad).where(Variedad.nombre == "Tomate marzano")) is None

    resolver(cliente, auth, c["id_carga_archivo"], "confirmada")
    v = sesion_aislada.scalar(select(Variedad).where(Variedad.nombre == "Tomate marzano"))
    assert sesion_aislada.get(Producto, v.id_producto).nombre == "Tomate"
    assert (v.unidad_origen, float(v.factor_a_kg)) == ("kilogramo", 1.0)


def test_producto_nuevo(cliente, auth, sesion_aislada):
    t = _texto(TOMATE).replace("<td colspan=10>Tomate</td>", "<td colspan=10>Camote amarillo</td>", 1)
    c = subir(cliente, auth, t.encode("latin-1")).json()
    assert c["catalogo_nuevo"] == {"productos": ["Camote"], "variedades": ["Camote amarillo"]}
    d = detalle(cliente, auth, c["id_carga_archivo"]).json()
    assert d["catalogo_nuevo"] == c["catalogo_nuevo"]          # el detalle lo repite
    resolver(cliente, auth, c["id_carga_archivo"], "confirmada")
    assert sesion_aislada.scalar(select(Producto).where(Producto.nombre == "Camote")) is not None


def test_el_nombre_se_reconoce_sin_importar_tildes_ni_mayusculas(cliente, auth):
    t = _texto(PAPA).replace("<td colspan=10>Papa amarilla</td>",
                             "<td colspan=10>PAPA  AMARÍLLA</td>", 1)
    c = subir(cliente, auth, t.encode("latin-1")).json()
    assert c["catalogo_nuevo"] == {"productos": [], "variedades": []}


# ------------------------------------------------------------------------ consultas
def test_historial_muestra_lo_mas_reciente_primero(cliente, auth):
    c = subir(cliente, auth, TOMATE.read_bytes()).json()
    r = cliente.get(URL + "?limite=5", headers=auth)
    validar_respuesta("GET", "/cargas", r)
    assert len(r.json()) == 5
    assert r.json()[0]["id_carga_archivo"] == c["id_carga_archivo"]


def test_el_historial_incluye_las_cargas_historicas(cliente, auth):
    # Las diez de cargar_precios.py no tienen archivo guardado: su periodo sale de los
    # precios que dejaron.
    r = cliente.get(URL + "?limite=200", headers=auth)
    validar_respuesta("GET", "/cargas", r)
    historicas = [c for c in r.json() if c["periodo"] and c["periodo"]["desde"] < "2020-01-01"]
    assert len(historicas) >= 9


@pytest.mark.parametrize("url", [URL + "?limite=0", URL + "?limite=201", URL + "/0",
                                 URL + "/abc"])
def test_parametros_fuera_de_rango_responden_422(cliente, auth, url):
    assert cliente.get(url, headers=auth).status_code == 422


def test_estado_no_admitido(cliente, auth):
    c = subir(cliente, auth, TOMATE.read_bytes()).json()
    r = cliente.patch("%s/%d" % (URL, c["id_carga_archivo"]), headers=auth,
                      json={"estado": "pendiente"})
    assert r.status_code == 422


def test_carga_inexistente_responde_404(cliente, auth):
    assert detalle(cliente, auth, 999_999_999).status_code == 404
    assert resolver(cliente, auth, 999_999_999, "confirmada").status_code == 404


def test_todo_exige_sesion_de_administrador(cliente):
    respuestas = [
        cliente.post(URL, data={"fuente": "SISAP minorista"},
                     files={"archivo": ("a.xls", b"x", "application/vnd.ms-excel")}),
        cliente.get(URL),
        cliente.get(URL + "/1"),
        cliente.patch(URL + "/1", json={"estado": "confirmada"}),
    ]
    assert [r.status_code for r in respuestas] == [401, 401, 401, 401]


def test_confirmar_cuando_otra_carga_ya_guardo_todo(cliente, auth, sesion_aislada):
    # El módulo mayorista trae 13 días de octubre. Antes de confirmarlo se confirma el
    # de ciudades, que trae esos mismos 13 mayoristas. Al confirmar el primero ya no
    # queda nada por guardar: se confirma igual, con cero precios y todo como duplicado.
    mayorista = subir(cliente, auth, MAYORISTA_TOMATE.read_bytes(), "SISAP mayorista").json()
    ciudades = subir(cliente, auth, TOMATE.read_bytes()).json()
    resolver(cliente, auth, ciudades["id_carga_archivo"], "confirmada")

    r = resolver(cliente, auth, mayorista["id_carga_archivo"], "confirmada")
    assert r.json()["precios_guardados"] == 0
    d = detalle(cliente, auth, mayorista["id_carga_archivo"]).json()
    assert (d["registros_validos"], d["registros_rechazados"]) == (0, 43)
