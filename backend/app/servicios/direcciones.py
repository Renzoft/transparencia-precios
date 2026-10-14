"""Búsqueda de direcciones (R12; CU05, EX2): el consumidor que no autoriza el GPS escribe
desde dónde saldrá, y aquí se convierte en coordenadas.

La búsqueda se limita al rectángulo de Lima Metropolitana y el Callao que ya usa el
registro de mercados: una dirección fuera de él no tendría mercados cercanos.
"""
from app.core.errores import ErrorAPI
from app.esquemas.direccion import Direccion
from app.servicios import ors
from app.servicios.mercados import LATITUD, LONGITUD

CANTIDAD = 5


def buscar(texto: str) -> list[Direccion]:
    try:
        encontradas = ors.buscar_direccion(texto, (*LATITUD, *LONGITUD), CANTIDAD)
    except ors.ServicioNoDisponible:
        raise ErrorAPI(503, "SERVICIO_NO_DISPONIBLE", "La búsqueda de direcciones no está "
                       "disponible en este momento. Usa tu ubicación o inténtalo más "
                       "tarde.") from None
    return [Direccion(**d) for d in encontradas]
