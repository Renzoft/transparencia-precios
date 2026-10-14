"""Servicio de rutas: distancia y tiempo de viaje hasta cada mercado (RNF017).

Es el adaptador que prevé el Documento de Arquitectura: el resto de la API pide
trayectos y no sabe de dónde salen. Se piden a OpenRouteService en una sola petición de
matriz. Si no hay clave configurada, o el servicio no responde en 3 segundos, la
distancia se estima en línea recta y el resultado se marca como aproximado (CU05, EX4;
RNF008).
"""
from dataclasses import dataclass
from math import asin, cos, radians, sin, sqrt

from app.servicios import ors

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


# Perfil de OpenRouteService para cada modo. OpenRouteService no calcula rutas de
# transporte público: para ese modo se usa la ruta en auto, que sigue las mismas
# calles que el bus pero da un tiempo menor que el real. Queda declarado como supuesto.
PERFIL = {
    "a pie": "foot-walking",
    "transporte público": "driving-car",
    "taxi": "driving-car",
    "auto particular": "driving-car",
}


def _en_linea_recta(origen: Punto, destinos: list[Punto]) -> list[Trayecto]:
    return [Trayecto(linea_recta(origen, d), None) for d in destinos]


def trayectos(origen: Punto, destinos: list[Punto], modo: str) -> tuple[list[Trayecto], bool]:
    """Un trayecto por destino, en el mismo orden, y si la distancia es aproximada."""
    if not destinos:
        return [], not ors.configurado()
    try:
        distancias, duraciones = ors.matriz(
            PERFIL[modo], [(p.latitud, p.longitud) for p in [origen, *destinos]])
    except ors.ServicioNoDisponible:
        return _en_linea_recta(origen, destinos), True

    resultado, aproximada = [], False
    for d, km, segundos in zip(destinos, distancias, duraciones):
        if km is None or segundos is None:
            # Sin ruta hasta ese mercado (punto fuera de la red de calles): línea recta.
            resultado.append(Trayecto(linea_recta(origen, d), None))
            aproximada = True
        else:
            resultado.append(Trayecto(km, max(1, round(segundos / 60))))
    return resultado, aproximada
