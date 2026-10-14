"""Punto de entrada de la API.

Se ejecuta desde backend/ con:  .venv/Scripts/python.exe -m uvicorn app.main:app --reload
"""
from fastapi import FastAPI

from app import VERSION
from app.core.errores import registrar_manejadores
from app.rutas import salud, sesiones

# Todos los endpoints del contrato cuelgan de este prefijo (openapi.yaml, «servers»).
PREFIJO_API = "/api/v1"


def crear_app() -> FastAPI:
    app = FastAPI(
        title="API del aplicativo móvil de transparencia de precios",
        version=VERSION,
        description="Contrato completo en openapi.yaml, en la raíz del repositorio.",
    )
    registrar_manejadores(app)
    app.include_router(salud.router)
    app.include_router(sesiones.router, prefix=PREFIJO_API)
    return app


app = crear_app()
