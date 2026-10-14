"""Punto de entrada de la API.

Se ejecuta desde backend/ con:  .venv/Scripts/python.exe -m uvicorn app.main:app --reload
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import VERSION
from app.core.config import configuracion
from app.core.errores import registrar_manejadores
from app.rutas import cargas, mercados, salud, sesiones

# Todos los endpoints del contrato cuelgan de este prefijo (openapi.yaml, «servers»).
PREFIJO_API = "/api/v1"

# En desarrollo, el panel corre en localhost con un puerto que elige Flutter.
LOCALHOST = r"https?://(localhost|127\.0\.0\.1)(:\d+)?"


def crear_app() -> FastAPI:
    app = FastAPI(
        title="API del aplicativo móvil de transparencia de precios",
        version=VERSION,
        description="Contrato completo en openapi.yaml, en la raíz del repositorio.",
    )
    registrar_manejadores(app)
    # CORS: el panel de administración es una aplicación web en otro origen, y el
    # navegador bloquea sus peticiones a la API salvo que la API lo autorice. Se autoriza
    # una lista cerrada de orígenes, nunca «cualquiera», porque estas peticiones llevan el
    # token del administrador.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=configuracion.lista_cors,
        allow_origin_regex=LOCALHOST if configuracion.entorno == "desarrollo" else None,
        allow_methods=["GET", "POST", "PATCH"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.include_router(salud.router)
    app.include_router(sesiones.router, prefix=PREFIJO_API)
    app.include_router(cargas.router, prefix=PREFIJO_API)
    app.include_router(mercados.router, prefix=PREFIJO_API)
    return app


app = crear_app()
