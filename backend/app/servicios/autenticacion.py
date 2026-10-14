"""Inicio de sesión del administrador (R1, CU01 paso 1 y excepción EX1)."""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errores import ErrorAPI
from app.core.seguridad import HASH_FICTICIO, crear_token, verificar_clave
from app.esquemas.sesion import SesionToken, UsuarioResumen
from app.modelos import Usuario

# Mensaje literal de la excepción EX1 del CU01.
MENSAJE_CREDENCIALES = "Usuario o contraseña incorrectos"


def credenciales_invalidas() -> ErrorAPI:
    return ErrorAPI(401, "CREDENCIALES_INVALIDAS", MENSAJE_CREDENCIALES)


def iniciar_sesion(sesion: Session, correo: str, clave: str) -> SesionToken:
    # El correo se compara sin distinguir mayúsculas: «Renzo@...» es la misma persona.
    usuario = sesion.scalar(
        select(Usuario).where(func.lower(Usuario.correo) == correo.strip().lower()))

    # Se verifica la contraseña aunque el correo no exista, contra un hash ficticio,
    # para que el tiempo de respuesta no revele qué correos están registrados.
    clave_ok = verificar_clave(clave, usuario.contrasena_hash if usuario else HASH_FICTICIO)

    # Correo inexistente, contraseña errada y cuenta desactivada responden lo mismo:
    # el contrato prohíbe dar pistas sobre cuál de las tres ocurrió.
    if usuario is None or not clave_ok or not usuario.activo:
        raise credenciales_invalidas()

    token, expira = crear_token(usuario.id_usuario, usuario.rol)
    return SesionToken(token=token, expira_en=expira,
                       usuario=UsuarioResumen(nombre=usuario.nombre, rol=usuario.rol))
