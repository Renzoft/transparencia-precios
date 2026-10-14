"""POST /sesiones: inicio de sesión del administrador (R1)."""
from fastapi import APIRouter

from app.core.dependencias import SesionBD
from app.esquemas.error import respuestas
from app.esquemas.sesion import SesionCrear, SesionToken
from app.servicios import autenticacion

router = APIRouter(tags=["Autenticación"])


@router.post("/sesiones", status_code=201, response_model=SesionToken,
             operation_id="crearSesion", summary="Inicia sesión y devuelve el token",
             responses=respuestas(401, 422))
def crear_sesion(datos: SesionCrear, sesion: SesionBD) -> SesionToken:
    return autenticacion.iniciar_sesion(sesion, datos.correo, datos.contrasena)
