"""Dependencias compartidas por los endpoints.

admin_actual es la que restringe al administrador las funciones de gestión (R1,
RNF001): cualquier endpoint que la declare responde 401 sin un token válido.
"""
from typing import Annotated

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.base_datos import obtener_sesion
from app.core.errores import ErrorAPI
from app.core.seguridad import leer_token
from app.modelos import Usuario

SesionBD = Annotated[Session, Depends(obtener_sesion)]

# auto_error=False: si falta el token, el 401 lo arma esta API con su formato de error
# y no FastAPI con el suyo.
_esquema_bearer = HTTPBearer(auto_error=False)


def _no_autenticado() -> ErrorAPI:
    return ErrorAPI(401, "NO_AUTENTICADO", "La sesión no es válida o expiró. "
                                           "Vuelve a iniciar sesión.")


def admin_actual(
    sesion: SesionBD,
    credenciales: Annotated[HTTPAuthorizationCredentials | None,
                            Depends(_esquema_bearer)],
) -> Usuario:
    if credenciales is None:
        raise _no_autenticado()
    try:
        contenido = leer_token(credenciales.credentials)
        id_usuario = int(contenido["sub"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise _no_autenticado() from None

    # Se consulta la base en cada petición: si el administrador fue desactivado después
    # de iniciar sesión, su token deja de servir en ese mismo momento, no ocho horas
    # después.
    usuario = sesion.get(Usuario, id_usuario)
    if usuario is None or not usuario.activo or usuario.rol != "administrador":
        raise _no_autenticado()
    return usuario


AdminActual = Annotated[Usuario, Depends(admin_actual)]
