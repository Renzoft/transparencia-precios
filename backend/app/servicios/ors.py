"""Cliente de OpenRouteService (RNF017): matriz de distancias y búsqueda de direcciones.

Se usa la biblioteca estándar (urllib): son dos llamadas REST con JSON y no justifican
otra dependencia. La clave va en la cabecera Authorization y nunca sale del servidor:
por eso la aplicación móvil no llama a OpenRouteService directamente.

Ni las coordenadas ni las direcciones se escriben en la bitácora (RNF003): si una
llamada falla, solo se registra qué tipo de falla fue.
"""
import json
import logging
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as TiempoAgotado

from app.core.config import configuracion

registro = logging.getLogger("transparencia_precios")

# El RNF008 da 3 segundos al servicio de rutas; la búsqueda de direcciones no tiene un
# límite fijado y se le dan unos más, porque sin ella no hay punto de partida.
ESPERA_RUTAS_S = 3.0
ESPERA_DIRECCIONES_S = 6.0

_hilos = ThreadPoolExecutor(max_workers=8, thread_name_prefix="ors")


class ServicioNoDisponible(Exception):
    """OpenRouteService no está configurado, no respondió a tiempo o respondió un error."""


def configurado() -> bool:
    return configuracion.ors_clave is not None


def _pedir(ruta: str, *, cuerpo: dict | None = None, consulta: dict | None = None,
           espera: float) -> dict:
    if not configurado():
        raise ServicioNoDisponible("sin clave")
    url = configuracion.ors_url.rstrip("/") + ruta
    if consulta:
        url += "?" + urllib.parse.urlencode(consulta)
    peticion = urllib.request.Request(
        url, method="POST" if cuerpo is not None else "GET",
        data=json.dumps(cuerpo).encode() if cuerpo is not None else None,
        headers={"Authorization": configuracion.ors_clave.get_secret_value(),
                 "Content-Type": "application/json", "Accept": "application/json"})

    def llamar() -> dict:
        with urllib.request.urlopen(peticion, timeout=espera) as r:
            return json.load(r)

    # El tiempo de urlopen es por operación de red, no total; el total se controla aquí.
    try:
        return _hilos.submit(llamar).result(timeout=espera)
    except TiempoAgotado:
        registro.warning("OpenRouteService no respondió en %.0f s (%s)", espera, ruta)
        raise ServicioNoDisponible("tiempo agotado") from None
    except Exception as e:      # HTTPError, URLError, JSON mal formado…
        registro.warning("Falló la llamada a OpenRouteService (%s): %s", ruta,
                         type(e).__name__)
        raise ServicioNoDisponible(type(e).__name__) from None


def matriz(perfil: str, puntos: list[tuple[float, float]]) -> tuple[list, list]:
    """Distancias (km) y duraciones (s) desde el primer punto hasta cada uno de los demás,
    en una sola petición. Los puntos van como (latitud, longitud)."""
    r = _pedir("/v2/matrix/" + perfil, espera=ESPERA_RUTAS_S, cuerpo={
        "locations": [[lon, lat] for lat, lon in puntos],     # ORS pide longitud primero
        "sources": [0],
        "destinations": list(range(1, len(puntos))),
        "metrics": ["distance", "duration"],
        "units": "km",
    })
    try:
        distancias, duraciones = r["distances"][0], r["durations"][0]
    except (KeyError, IndexError, TypeError):
        registro.warning("OpenRouteService devolvió una matriz incompleta")
        raise ServicioNoDisponible("matriz incompleta") from None
    if len(distancias) != len(puntos) - 1 or len(duraciones) != len(puntos) - 1:
        registro.warning("OpenRouteService devolvió una matriz de otro tamaño")
        raise ServicioNoDisponible("matriz de otro tamaño")
    return distancias, duraciones


def buscar_direccion(texto: str, rectangulo: tuple[float, float, float, float],
                     cantidad: int) -> list[dict]:
    """Direcciones que coinciden con el texto dentro del rectángulo
    (lat_min, lat_max, lon_min, lon_max). Cada una: etiqueta, latitud y longitud."""
    lat_min, lat_max, lon_min, lon_max = rectangulo
    r = _pedir("/geocode/search", espera=ESPERA_DIRECCIONES_S, consulta={
        "text": texto, "size": cantidad, "boundary.country": "PE",
        "boundary.rect.min_lat": lat_min, "boundary.rect.max_lat": lat_max,
        "boundary.rect.min_lon": lon_min, "boundary.rect.max_lon": lon_max,
    })
    try:
        return [{"etiqueta": f["properties"]["label"],
                 "latitud": f["geometry"]["coordinates"][1],
                 "longitud": f["geometry"]["coordinates"][0]}
                for f in r.get("features", [])]
    except (KeyError, IndexError, TypeError, AttributeError):
        registro.warning("OpenRouteService devolvió direcciones con otro formato")
        raise ServicioNoDisponible("formato de direcciones") from None
