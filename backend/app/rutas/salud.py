"""Endpoint de salud, para el monitor externo de disponibilidad (RNF007).

No forma parte del contrato de la API: no aparece en openapi.yaml ni en /docs, porque
no es una función del aplicativo sino de su operación. Por eso cuelga de la raíz y no de
/api/v1, igual que en la mayoría de servicios.

Responde 503 si la base de datos no contesta. Sin eso, el monitor vería la API «arriba»
aunque no pudiera atender ninguna consulta real.
"""
from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app import VERSION
from app.core import base_datos
from app.core.config import configuracion

router = APIRouter()


@router.get("/salud", include_in_schema=False)
def salud():
    base_ok = base_datos.base_responde()
    cuerpo = {
        "estado": "ok" if base_ok else "degradado",
        "servicio": "transparencia-precios",
        "version": VERSION,
        "entorno": configuracion.entorno,
        "base_datos": "ok" if base_ok else "sin conexión",
    }
    return JSONResponse(cuerpo, status_code=200 if base_ok else 503)
