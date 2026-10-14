"""Lector de los archivos que exporta el SISAP (CU01, pasos 8 y 9).

El SISAP ofrece «Exportar a Excel», pero lo que entrega es un .xls que por dentro es una
tabla HTML en Latin-1. Este módulo lo interpreta y devuelve los registros listos para
guardar y los rechazos contados por motivo. No toca la base de datos: los duplicados
contra lo ya cargado y el catálogo los resuelve el servicio de cargas.

Formatos admitidos, comprobados con archivos reales descargados el 2026-10-13:

  Módulo «Ciudades» (fuente «SISAP minorista»)
    Una variedad de Lima con precio mayorista y minorista por día. Los precios vienen
    por unidad de venta (un cajón de 27 kg, un kilo, una botella de 900 ml) junto con
    su equivalencia en kilogramos o litros, y se convierten a precio por kilogramo.

  Módulo «Mercados mayoristas» (fuente «SISAP mayorista»)
    Una variedad con precio mayorista por kilogramo y volumen ingresado en toneladas.

Si el archivo no tiene exactamente esa estructura se rechaza entero (excepción EX2):
es preferible pedir otro archivo a guardar precios leídos de columnas equivocadas.
"""
import re
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from html.parser import HTMLParser

MINORISTA = "minorista_lima"
MAYORISTA = "mayorista_lima"

FUENTE_CIUDADES = "SISAP minorista"
FUENTE_MAYORISTA = "SISAP mayorista"

# Los cinco motivos que admite carga_rechazo (crear_base_datos.sql, ck_rechazo_motivo).
DUPLICADO = "duplicado"
FALTANTE = "dato faltante"
PRECIO_INVALIDO = "precio no válido"
UNIDAD_DESCONOCIDA = "unidad desconocida"
FECHA_FUERA = "fecha fuera de rango"

MENSAJE_FORMATO = "El archivo no corresponde al formato esperado"   # CU01, EX2


class FormatoNoValido(Exception):
    """El archivo no es uno de los formatos del SISAP que se admiten (EX2)."""

    def __init__(self, motivo: str):
        super().__init__(motivo)
        self.motivo = motivo


@dataclass(frozen=True)
class Registro:
    fecha: date
    ambito: str
    precio_kg: Decimal
    volumen_t: Decimal | None = None


@dataclass
class Lectura:
    fuente: str
    variedad: str                      # nombre tal como lo escribe el SISAP
    desde: date
    hasta: date
    registros: list[Registro] = field(default_factory=list)
    rechazos: Counter = field(default_factory=Counter)
    unidades: dict[str, tuple[str, Decimal]] = field(default_factory=dict)
    mercado: str | None = None         # solo en el módulo mayorista


# ------------------------------------------------------------- lectura del HTML
class _Tabla(HTMLParser):
    """Extrae los títulos <h1>, los párrafos <p> y las filas de la tabla del reporte."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.titulos: list[str] = []
        self.parrafos: list[str] = []
        self.encabezados: list[list[str]] = []
        self.filas: list[list[str]] = []
        self.es_reporte = False
        self._fila: list[str] | None = None
        self._clase_fila = ""
        self._celda: list[str] | None = None
        self._texto: list[str] | None = None

    def handle_starttag(self, etiqueta, atributos):
        a = dict(atributos)
        if etiqueta == "div" and "reporteData" in (a.get("class") or ""):
            self.es_reporte = True
        elif etiqueta in ("h1", "p"):
            self._texto = []
        elif etiqueta == "tr":
            self._fila, self._clase_fila = [], a.get("class") or ""
        elif etiqueta == "td" and self._fila is not None:
            self._celda = []
        elif etiqueta == "br" and self._celda is not None:
            self._celda.append(" ")

    def handle_endtag(self, etiqueta):
        if etiqueta in ("h1", "p") and self._texto is not None:
            texto = " ".join("".join(self._texto).split())
            (self.titulos if etiqueta == "h1" else self.parrafos).append(texto)
            self._texto = None
        elif etiqueta == "td" and self._celda is not None:
            self._fila.append(" ".join("".join(self._celda).split()))
            self._celda = None
        elif etiqueta == "tr" and self._fila is not None:
            destino = self.encabezados if "encabezado" in self._clase_fila else (
                self.filas if "contenido" in self._clase_fila else None)
            if destino is not None:
                destino.append(self._fila)
            self._fila = None

    def handle_data(self, datos):
        if self._celda is not None:
            self._celda.append(datos)
        elif self._texto is not None:
            self._texto.append(datos)


def _decodificar(contenido: bytes) -> str:
    # El SISAP exporta en Latin-1. Se intenta UTF-8 primero: si alguien reenvía el
    # archivo convertido, leerlo como Latin-1 dañaría las tildes de los nombres.
    try:
        return contenido.decode("utf-8")
    except UnicodeDecodeError:
        return contenido.decode("latin-1")


# --------------------------------------------------------------- valores sueltos
_MILES = re.compile(r"^\d{1,3}(,\d{3})+(\.\d+)?$")


def _numero(texto: str) -> Decimal | None:
    """Número del SISAP o None si la celda está vacía. ValueError si no es número."""
    t = texto.strip()
    if t in ("", "...", "-"):
        return None
    if _MILES.match(t):
        t = t.replace(",", "")
    try:
        valor = Decimal(t)
    except Exception:
        raise ValueError(texto) from None
    if not valor.is_finite():
        raise ValueError(texto)
    return valor


def _fecha(texto: str) -> date:
    return datetime.strptime(texto.strip(), "%d/%m/%Y").date()


def _periodo(titulos: list[str]) -> tuple[date, date]:
    for t in titulos:
        m = re.fullmatch(r"(\d{2}/\d{2}/\d{4})\s*-\s*(\d{2}/\d{2}/\d{4})", t)
        if m:
            return _fecha(m.group(1)), _fecha(m.group(2))
    raise FormatoNoValido("no se encontró el periodo del reporte")


def _por_kilo(precio: Decimal, equivalencia: Decimal) -> Decimal:
    # Mismo redondeo que usó cargar_precios.py, para que un precio cargado por el panel
    # sea idéntico al que ya está en la serie histórica.
    return Decimal(str(round(float(precio) / float(equivalencia), 2)))


# ------------------------------------------------------------------ los dos módulos
def _leer_ciudades(t: _Tabla, lectura: Lectura, hoy: date) -> None:
    e = t.encabezados
    if len(e) != 4 or e[0][:1] != ["Fecha"]:
        raise FormatoNoValido("la cabecera no es la del módulo de ciudades")
    if len(e[0]) != 2 or len(e[1]) != 1:
        raise FormatoNoValido("el archivo debe traer una sola región y una sola variedad")
    if e[0][1] != "Lima":
        raise FormatoNoValido("el archivo es de la región «%s»; solo se admiten precios "
                              "de Lima" % e[0][1])
    esperado_3 = ["Unidad de medida", "Equiv. (kg./lt)", "Mayorista",
                  "Unidad de medida", "Equiv. (kg./lt)", "Minorista"]
    esperado_4 = ["Precio min.", "Precio prom.", "Precio max."] * 2
    if e[2] != esperado_3 or e[3] != esperado_4:
        raise FormatoNoValido("faltan o sobran columnas de precios: se necesitan las seis "
                              "variables (mínimo, promedio y máximo, mayorista y minorista)")
    lectura.variedad = e[1][0]

    vistos: set[tuple[date, str]] = set()
    for fila in t.filas:
        if len(fila) != 11:
            raise FormatoNoValido("una fila tiene %d columnas en lugar de 11" % len(fila))
        try:
            dia = _fecha(fila[0])
        except ValueError:
            lectura.rechazos[FALTANTE] += 1
            continue
        if not (lectura.desde <= dia <= lectura.hasta) or dia > hoy:
            lectura.rechazos[FECHA_FUERA] += 1
            continue

        lados = ((MAYORISTA, fila[1:6]), (MINORISTA, fila[6:11]))
        if all(not c for _, celdas in lados for c in celdas):
            lectura.rechazos[FALTANTE] += 1      # una fecha sin ningún dato
            continue
        for ambito, (unidad, equiv, _minimo, promedio, _maximo) in lados:
            if not any((unidad, equiv, _minimo, promedio, _maximo)):
                continue      # ese día no se relevó ese ámbito: no es un error
            try:
                eq = _numero(equiv)
            except ValueError:
                eq = None
            if not unidad or eq is None or eq <= 0:
                lectura.rechazos[UNIDAD_DESCONOCIDA] += 1
                continue
            try:
                prom = _numero(promedio)
            except ValueError:
                lectura.rechazos[PRECIO_INVALIDO] += 1
                continue
            if prom is None:
                lectura.rechazos[FALTANTE] += 1
                continue
            if prom <= 0:
                lectura.rechazos[PRECIO_INVALIDO] += 1
                continue
            if (dia, ambito) in vistos:
                lectura.rechazos[DUPLICADO] += 1
                continue
            vistos.add((dia, ambito))
            lectura.unidades.setdefault(ambito, (unidad, eq))
            lectura.registros.append(Registro(dia, ambito, _por_kilo(prom, eq)))


def _leer_mayorista(t: _Tabla, lectura: Lectura, hoy: date) -> None:
    e = t.encabezados
    if len(e) != 2 or e[0][:1] != ["Fecha"] or len(e[0]) != 2:
        raise FormatoNoValido("el archivo debe traer una sola variedad")
    columnas = [c.split(" (")[0].strip() for c in e[1]]
    if columnas != ["Precio Máximo", "Precio Promedio", "Precio Mínimo", "Volumen"]:
        raise FormatoNoValido("se necesitan las cuatro variables: precio máximo, promedio "
                              "y mínimo, y volumen")
    lectura.variedad = e[0][1]
    for p in t.parrafos:
        if p.lower().startswith("fuente:"):
            lectura.mercado = p.split(":", 1)[1].strip()

    vistos: set[date] = set()
    for fila in t.filas:
        if len(fila) != 5:
            raise FormatoNoValido("una fila tiene %d columnas en lugar de 5" % len(fila))
        try:
            dia = _fecha(fila[0])
        except ValueError:
            lectura.rechazos[FALTANTE] += 1
            continue
        if not (lectura.desde <= dia <= lectura.hasta) or dia > hoy:
            lectura.rechazos[FECHA_FUERA] += 1
            continue
        try:
            prom = _numero(fila[2])
        except ValueError:
            lectura.rechazos[PRECIO_INVALIDO] += 1
            continue
        if prom is None:
            lectura.rechazos[FALTANTE] += 1
            continue
        if prom <= 0:
            lectura.rechazos[PRECIO_INVALIDO] += 1
            continue
        try:
            volumen = _numero(fila[4])
        except ValueError:
            lectura.rechazos[FALTANTE] += 1
            continue
        if volumen is not None and volumen < 0:
            lectura.rechazos[FALTANTE] += 1
            continue
        if dia in vistos:
            lectura.rechazos[DUPLICADO] += 1
            continue
        vistos.add(dia)
        lectura.registros.append(Registro(dia, MAYORISTA, prom, volumen))


# ---------------------------------------------------------------- punto de entrada
_MODULOS = {
    FUENTE_CIUDADES: ("Mercados mayoristas y minoristas de Lima", _leer_ciudades),
    FUENTE_MAYORISTA: ("Lima Metropolitana:", _leer_mayorista),
}


def leer(contenido: bytes, fuente: str, hoy: date | None = None) -> Lectura:
    """Interpreta un archivo del SISAP. Lanza FormatoNoValido si no se reconoce."""
    if fuente not in _MODULOS:
        raise FormatoNoValido("todavía no hay un formato definido para la fuente «%s»"
                              % fuente)
    t = _Tabla()
    try:
        t.feed(_decodificar(contenido))
        t.close()
    except Exception:
        raise FormatoNoValido("el archivo no se pudo leer como un reporte del SISAP") from None
    if not t.es_reporte or not t.titulos:
        raise FormatoNoValido("no es un reporte exportado del SISAP")

    prefijo, leer_modulo = _MODULOS[fuente]
    if not t.titulos[0].startswith(prefijo):
        otra = next((f for f, (p, _) in _MODULOS.items() if t.titulos[0].startswith(p)), None)
        if otra:
            raise FormatoNoValido("el archivo es del módulo de la fuente «%s», no de «%s»"
                                  % (otra, fuente))
        raise FormatoNoValido("el reporte no es de un módulo del SISAP que se admita")

    desde, hasta = _periodo(t.titulos)
    lectura = Lectura(fuente=fuente, variedad="", desde=desde, hasta=hasta)
    leer_modulo(t, lectura, hoy or date.today())
    if not lectura.variedad:
        raise FormatoNoValido("el archivo no indica la variedad")
    return lectura
