"""Lector de archivos del SISAP, probado con archivos reales exportados del portal.

Tres grupos de pruebas:

1. Los archivos reales se leen completos y con las unidades bien convertidas.
2. Lo leído coincide con lo que ya está en la base para septiembre de 2026, que se cargó
   por otra vía (cargar_precios.py). Es la prueba más fuerte: dos caminos distintos
   llegan a los mismos precios.
3. Cada motivo de rechazo y cada formato inválido se fuerza partiendo de un archivo real,
   para que la cabecera sea auténtica y solo cambie lo que se quiere probar.
"""
import re
from datetime import date
from decimal import Decimal
from pathlib import Path

import pytest
from sqlalchemy import text

from app.core.base_datos import FabricaSesion
from app.servicios.lector_sisap import (DUPLICADO, FALTANTE, FECHA_FUERA, MAYORISTA,
                                        MINORISTA, PRECIO_INVALIDO, UNIDAD_DESCONOCIDA,
                                        FormatoNoValido, leer)

ARCHIVOS = Path(__file__).parent / "archivos"
TOMATE = ARCHIVOS / "ciudades_tomate_2026-09-01_2026-10-13.xls"
PAPA = ARCHIVOS / "ciudades_papa_amarilla_2026-09-01_2026-10-13.xls"
MAYORISTA_TOMATE = ARCHIVOS / "mayorista_gran_mercado_tomate_2026-09-01_2026-10-13.xls"
HOY = date(2026, 10, 14)


def leer_real(ruta, fuente="SISAP minorista"):
    return leer(ruta.read_bytes(), fuente, hoy=HOY)


# ------------------------------------------------------------ 1. archivos reales
def test_ciudades_tomate():
    l = leer_real(TOMATE)
    assert l.variedad == "Tomate"
    assert (l.desde, l.hasta) == (date(2026, 9, 1), date(2026, 10, 13))
    assert sum(r.ambito == MAYORISTA for r in l.registros) == 43   # el mayorista es diario
    assert sum(r.ambito == MINORISTA for r in l.registros) == 18   # el minorista, lun-mié-vie
    assert not l.rechazos


def test_el_mayorista_por_cajon_se_pasa_a_kilo():
    l = leer_real(TOMATE)
    assert l.unidades[MAYORISTA] == ("Cajon chico", Decimal("27.00"))
    primero = next(r for r in l.registros if r.ambito == MAYORISTA)
    assert primero.fecha == date(2026, 9, 1)
    assert primero.precio_kg == Decimal("4.63")        # 125,00 soles el cajón / 27 kg


def test_ciudades_papa_amarilla_trae_el_nombre_de_la_variedad():
    # El tomate no permite saber si la cabecera trae producto o variedad: la papa sí.
    assert leer_real(PAPA).variedad == "Papa amarilla"


def test_modulo_mayorista_trae_volumen_y_mercado():
    l = leer_real(MAYORISTA_TOMATE, "SISAP mayorista")
    assert l.variedad == "Tomate"
    assert l.mercado == "GRAN MERCADO MAYORISTA DE LIMA"
    assert len(l.registros) == 43 and all(r.ambito == MAYORISTA for r in l.registros)
    ultimo = max(l.registros, key=lambda r: r.fecha)
    assert (ultimo.precio_kg, ultimo.volumen_t) == (Decimal("3.47"), Decimal("360.00"))


# ------------------------------------------- 2. coincide con lo que ya está en la base
def _base(variedad: str, ambito: str) -> dict[date, Decimal]:
    with FabricaSesion() as s:
        filas = s.execute(text(
            "SELECT p.fecha, p.precio_kg FROM precio_serie p JOIN variedad v USING "
            "(id_variedad) WHERE v.nombre = :v AND p.ambito = :a "
            "AND p.fecha BETWEEN '2026-09-01' AND '2026-09-30'"), {"v": variedad, "a": ambito})
        return dict(filas.all())


@pytest.mark.parametrize("ruta, fuente", [
    (TOMATE, "SISAP minorista"),
    (PAPA, "SISAP minorista"),
    (MAYORISTA_TOMATE, "SISAP mayorista"),
], ids=["ciudades tomate", "ciudades papa amarilla", "mayorista tomate"])
def test_lo_leido_coincide_con_la_serie_historica(ruta, fuente):
    l = leer_real(ruta, fuente)
    comparados = 0
    for ambito in (MAYORISTA, MINORISTA):
        en_base = _base(l.variedad, ambito)
        for r in l.registros:
            if r.ambito == ambito and r.fecha in en_base:
                assert r.precio_kg == en_base[r.fecha], (r.fecha, ambito)
                comparados += 1
    assert comparados >= 30      # al menos todo septiembre del mayorista


# ------------------------------------------------- 3. rechazos y formatos inválidos
def _texto(ruta) -> str:
    return ruta.read_bytes().decode("latin-1")


def _con_filas(ruta, filas: list[list[str]]) -> bytes:
    """El archivo real con su cabecera intacta y las filas de datos reemplazadas."""
    t = _texto(ruta)
    inicio = t.index("<tr class=contenido>") if "<tr class=contenido>" in t else \
        t.index('<tr class="contenido">')
    fin = t.index("</tbody>")
    cuerpo = "".join("<tr class=contenido>" + "".join("<td>%s</td>" % c for c in f) + "</tr>"
                     for f in filas)
    return (t[:inicio] + cuerpo + t[fin:]).encode("latin-1")


def _fila(fecha="01/09/2026", may=("Cajon chico", "27.00", "120.00", "125.00", "130.00"),
          mino=("Kilogramo", "1.00", "5.00", "7.34", "9.00")):
    return [fecha, *may, *mino]


VACIO = ("", "", "", "", "")


@pytest.mark.parametrize("caso, fila, motivo", [
    ("precio promedio vacío", _fila(mino=("Kilogramo", "1.00", "5.00", "", "9.00")), FALTANTE),
    ("precio negativo", _fila(mino=("Kilogramo", "1.00", "5.00", "-7.34", "9.00")), PRECIO_INVALIDO),
    ("precio cero", _fila(mino=("Kilogramo", "1.00", "5.00", "0.00", "9.00")), PRECIO_INVALIDO),
    ("precio que no es número", _fila(mino=("Kilogramo", "1.00", "5.00", "siete", "9.00")), PRECIO_INVALIDO),
    ("equivalencia que no es número", _fila(mino=("Kilogramo", "uno", "5.00", "7.34", "9.00")), UNIDAD_DESCONOCIDA),
    ("equivalencia cero", _fila(mino=("Kilogramo", "0.00", "5.00", "7.34", "9.00")), UNIDAD_DESCONOCIDA),
    ("sin unidad de medida", _fila(mino=("", "1.00", "5.00", "7.34", "9.00")), UNIDAD_DESCONOCIDA),
])
def test_rechazos_por_registro(caso, fila, motivo):
    l = leer(_con_filas(TOMATE, [fila]), "SISAP minorista", hoy=HOY)
    assert l.rechazos == {motivo: 1}
    # El otro lado de la misma fila, el mayorista, sigue siendo válido.
    assert [r.ambito for r in l.registros] == [MAYORISTA]


def test_fecha_fuera_del_periodo_del_reporte():
    l = leer(_con_filas(TOMATE, [_fila("15/08/2026")]), "SISAP minorista", hoy=HOY)
    assert l.rechazos == {FECHA_FUERA: 1} and not l.registros


def test_fecha_futura():
    l = leer(_con_filas(TOMATE, [_fila("13/10/2026")]), "SISAP minorista",
             hoy=date(2026, 10, 12))
    assert l.rechazos == {FECHA_FUERA: 1}


def test_fecha_ilegible():
    l = leer(_con_filas(TOMATE, [_fila("31/02/2026")]), "SISAP minorista", hoy=HOY)
    assert l.rechazos == {FALTANTE: 1}


def test_fecha_sin_ningun_dato():
    l = leer(_con_filas(TOMATE, [_fila(may=VACIO, mino=VACIO)]), "SISAP minorista", hoy=HOY)
    assert l.rechazos == {FALTANTE: 1}


def test_un_dia_sin_relevamiento_minorista_no_es_un_error():
    # El minorista se releva lunes, miércoles y viernes: los demás días vienen vacíos.
    l = leer(_con_filas(TOMATE, [_fila(mino=VACIO)]), "SISAP minorista", hoy=HOY)
    assert not l.rechazos and [r.ambito for r in l.registros] == [MAYORISTA]


def test_fila_repetida_dentro_del_archivo():
    l = leer(_con_filas(TOMATE, [_fila(), _fila()]), "SISAP minorista", hoy=HOY)
    assert l.rechazos == {DUPLICADO: 2}           # mayorista y minorista de la copia
    assert len(l.registros) == 2


def _mayorista_con(filas):
    return leer(_con_filas(MAYORISTA_TOMATE, filas), "SISAP mayorista", hoy=HOY)


def test_mayorista_volumen_no_reportado_y_separador_de_miles():
    l = _mayorista_con([["02/09/2026", "4.63", "4.49", "4.44", "..."],
                        ["01/09/2026", "4.81", "4.63", "4.44", "1,234.00"]])
    assert not l.rechazos
    volumen = {r.fecha.day: r.volumen_t for r in l.registros}
    assert volumen == {2: None, 1: Decimal("1234.00")}


@pytest.mark.parametrize("fila, motivo", [
    (["01/09/2026", "4.81", "", "4.44", "331.00"], FALTANTE),
    (["01/09/2026", "4.81", "-4.63", "4.44", "331.00"], PRECIO_INVALIDO),
    (["01/09/2026", "4.81", "abc", "4.44", "331.00"], PRECIO_INVALIDO),
    (["01/09/2026", "4.81", "4.63", "4.44", "-5.00"], FALTANTE),
    (["01/09/2026", "4.81", "4.63", "4.44", "mucho"], FALTANTE),
    (["15/08/2026", "4.81", "4.63", "4.44", "331.00"], FECHA_FUERA),
    (["sin fecha", "4.81", "4.63", "4.44", "331.00"], FALTANTE),
])
def test_rechazos_del_modulo_mayorista(fila, motivo):
    assert _mayorista_con([fila]).rechazos == {motivo: 1}


def test_mayorista_fila_repetida():
    f = ["01/09/2026", "4.81", "4.63", "4.44", "331.00"]
    assert _mayorista_con([f, f]).rechazos == {DUPLICADO: 1}


# ------------------------------------------------------- formatos que se rechazan
def _formato(contenido: bytes, fuente="SISAP minorista") -> str:
    with pytest.raises(FormatoNoValido) as e:
        leer(contenido, fuente, hoy=HOY)
    return e.value.motivo


def test_un_xlsx_de_verdad_no_es_un_reporte_del_sisap():
    # Un .xlsx real es un ZIP: empieza con «PK».
    assert "SISAP" in _formato(b"PK\x03\x04" + bytes(200))


def test_una_pagina_web_cualquiera():
    assert "SISAP" in _formato(b"<html><body><h1>Hola</h1></body></html>")


def test_fuente_equivocada():
    assert "SISAP minorista" in _formato(TOMATE.read_bytes(), "SISAP mayorista")
    assert "SISAP mayorista" in _formato(MAYORISTA_TOMATE.read_bytes(), "SISAP minorista")


def test_precios_por_mercado_aun_no_tiene_formato():
    assert "precios por mercado" in _formato(TOMATE.read_bytes(), "precios por mercado")


def test_otra_region():
    t = _texto(TOMATE).replace("<td colspan=10>Lima</td>", "<td colspan=10>Arequipa</td>", 1)
    assert "Arequipa" in _formato(t.encode("latin-1"))


def test_faltan_variables_de_precio():
    t = _texto(TOMATE).replace("<td>Precio max.</td></tr>", "</tr>", 1)
    assert "seis variables" in _formato(t.encode("latin-1"))


def test_mayorista_sin_volumen():
    t = _texto(MAYORISTA_TOMATE)
    t = re.sub(r'<td class="numero" colspan="1">Volumen.*?</td>', "", t, count=1)
    assert "cuatro variables" in _formato(t.encode("latin-1"), "SISAP mayorista")


def test_fila_con_columnas_de_menos():
    assert "columnas" in _formato(_con_filas(TOMATE, [["01/09/2026", "Cajon chico"]]))


def test_sin_periodo_en_el_titulo():
    t = _texto(TOMATE).replace("<h1>01/09/2026 - 13/10/2026</h1>", "", 1)
    assert "periodo" in _formato(t.encode("latin-1"))


def test_un_archivo_reenviado_en_utf8_conserva_las_tildes():
    # Si alguien abre el archivo y lo reenvía convertido a UTF-8, debe leerse igual.
    original = leer_real(PAPA)
    convertido = leer(_texto(PAPA).encode("utf-8"), "SISAP minorista", hoy=HOY)
    assert convertido.registros == original.registros


def test_dos_variedades_en_un_mismo_archivo():
    # El portal permite marcar varias variedades: se pide un archivo por cada una.
    t = _texto(TOMATE).replace("<td colspan=10>Tomate</td>",
                               "<td colspan=10>Tomate</td><td colspan=10>Tomate marzano</td>", 1)
    assert "una sola variedad" in _formato(t.encode("latin-1"))


def test_cabecera_incompleta():
    t = _texto(TOMATE)
    t = t.replace(re.search(r"<tr class=encabezado><td colspan=10>Tomate</td></tr>", t).group(0), "", 1)
    assert "cabecera" in _formato(t.encode("latin-1"))


def test_reporte_de_otro_modulo_del_sisap():
    t = re.sub(r"<h1>Mercados mayoristas y minoristas de Lima[^<]*</h1>",
               "<h1>Precios en chacra según región</h1>", _texto(TOMATE), count=1)
    assert "no es de un módulo" in _formato(t.encode("latin-1"))


def test_precio_no_finito():
    f = _fila(mino=("Kilogramo", "1.00", "5.00", "NaN", "9.00"))
    assert leer(_con_filas(TOMATE, [f]), "SISAP minorista", hoy=HOY).rechazos == {PRECIO_INVALIDO: 1}


def test_cabecera_sin_nombre_de_variedad():
    t = _texto(TOMATE).replace("<td colspan=10>Tomate</td>", "<td colspan=10></td>", 1)
    assert "variedad" in _formato(t.encode("latin-1"))


def test_filas_que_no_son_ni_cabecera_ni_datos_se_ignoran():
    t = _texto(TOMATE).replace("</tbody>", "<tr class=nota><td>Nota al pie</td></tr></tbody>", 1)
    assert len(leer(t.encode("latin-1"), "SISAP minorista", hoy=HOY).registros) == 61


def test_mayorista_con_dos_variedades():
    t = _texto(MAYORISTA_TOMATE).replace('<td colspan="4">Tomate</td>',
                                         '<td colspan="4">Tomate</td><td colspan="4">Otra</td>', 1)
    assert "una sola variedad" in _formato(t.encode("latin-1"), "SISAP mayorista")


def test_mayorista_fila_con_columnas_de_menos():
    with pytest.raises(FormatoNoValido, match="columnas"):
        _mayorista_con([["01/09/2026", "4.81", "4.63"]])
