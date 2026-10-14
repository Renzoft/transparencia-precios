"""Endpoint de salud, para el monitor externo de disponibilidad (RNF007).

No forma parte del contrato de la API: no aparece en openapi.yaml ni en /docs, porque
no es una función del aplicativo sino de su operación. Por eso cuelga de la raíz y no de
/api/v1, igual que en la mayoría de servicios.
"""
from fastapi import APIRouter

from app import VERSION
from app.core.config import configuracion

router = APIRouter()


@router.get("/salud", include_in_schema=False)
def salud():
    return {
        "estado": "ok",
        "servicio": "transparencia-precios",
        "version": VERSION,
        "entorno": configuracion.entorno,
    }
