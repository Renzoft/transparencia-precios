"""Servicio de rutas: distancia y tiempo de viaje hasta cada mercado (RNF017).

Es el adaptador que prevé el Documento de Arquitectura: el resto de la API pide
trayectos y no sabe de dónde salen. La consulta a OpenRouteService se conecta en una
pieza posterior del CU05; mientras tanto, y también cuando ese servicio no responda en
3 segundos, la distancia se estima en línea recta y el resultado se marca como
aproximado (CU05, EX4; RNF008).
"""
from dataclasses import dataclass
from math import asin, cos, radians, sin, sqrt

# Radio medio de la Tierra (IUGG), en kilómetros.
RADIO_TIERRA_KM = 6371.0088


@dataclass(frozen=True)
class Punto:
    latitud: float
    longitud: float


@dataclass(frozen=True)
class Trayecto:
    distancia_km: float
    duracion_min: int | None      # None si la distancia es en línea recta


def linea_recta(a: Punto, b: Punto) -> float:
    """Distancia sobre la superficie de la Tierra (fórmula del haversine), en km."""
    dlat = radians(b.latitud - a.latitud)
    dlon = radians(b.longitud - a.longitud)
    h = sin(dlat / 2) ** 2 + cos(radians(a.latitud)) * cos(radians(b.latitud)) * sin(dlon / 2) ** 2
    return 2 * RADIO_TIERRA_KM * asin(sqrt(h))


def trayectos(origen: Punto, destinos: list[Punto], modo: str) -> tuple[list[Trayecto], bool]:
    """Un trayecto por destino, en el mismo orden, y si la distancia es aproximada."""
    return [Trayecto(linea_recta(origen, d), None) for d in destinos], True
