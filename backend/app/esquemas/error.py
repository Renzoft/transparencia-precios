"""Cuerpo de error del contrato (openapi.yaml: Error, DetalleError).

Lo genera app.core.errores; este modelo solo existe para que la documentación de /docs
describa el formato real. Sin él, FastAPI anunciaría su propio formato de error para el
422, que la API no usa.
"""
from pydantic import BaseModel


class DetalleError(BaseModel):
    campo: str
    problema: str


class CuerpoError(BaseModel):
    codigo: str
    mensaje: str
    detalles: list[DetalleError] | None = None


class Error(BaseModel):
    error: CuerpoError


def respuestas(*codigos: int) -> dict:
    """Respuestas de error para declarar en un endpoint: respuestas(401, 422)."""
    descripciones = {
        400: "La petición está malformada y no se puede interpretar",
        401: "Falta el token, es inválido o expiró",
        404: "El recurso no existe",
        409: "La operación choca con el estado actual del recurso",
        422: "Los campos se interpretan bien pero su contenido no es válido",
        429: "Se superó el límite de peticiones que protege la cuota del servicio de rutas",
        503: "El servicio externo que se necesita no está disponible",
    }
    return {c: {"model": Error, "description": descripciones[c]} for c in codigos}
