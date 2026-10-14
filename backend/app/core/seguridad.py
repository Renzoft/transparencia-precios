"""Contraseñas y tokens del administrador (RNF001).

Contraseñas con bcrypt; sesión con un token JWT firmado con HS256 y vigencia de ocho
horas. El token lleva el identificador del usuario y su rol, nada más: ni correo ni
nombre, porque un JWT se puede leer sin la clave, solo no se puede falsificar.
"""
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt

from app.core.config import configuracion

ALGORITMO = "HS256"

# bcrypt solo considera los primeros 72 bytes, y desde la versión 5 se niega a recibir
# más. Una contraseña de 72 caracteres con tildes o eñes puede pasar de 72 bytes.
LIMITE_BCRYPT = 72


def hash_clave(clave: str) -> str:
    datos = clave.encode("utf-8")
    if len(datos) > LIMITE_BCRYPT:
        raise ValueError("La contraseña no puede superar 72 bytes")
    return bcrypt.hashpw(datos, bcrypt.gensalt()).decode()


def verificar_clave(clave: str, hash_guardado: str) -> bool:
    datos = clave.encode("utf-8")
    if len(datos) > LIMITE_BCRYPT:
        # Ninguna contraseña guardada puede ser tan larga, así que no coincide.
        return False
    return bcrypt.checkpw(datos, hash_guardado.encode())


# Hash de una contraseña que nadie conoce. Cuando el correo no existe, se verifica la
# contraseña contra este hash de todos modos: así la respuesta tarda lo mismo que con un
# correo real, y el tiempo no delata qué correos están registrados.
HASH_FICTICIO = hash_clave("correo-inexistente-sin-clave-valida")


def crear_token(id_usuario: int, rol: str) -> tuple[str, datetime]:
    ahora = datetime.now(UTC)
    expira = ahora + timedelta(hours=configuracion.jwt_horas)
    carga = {"sub": str(id_usuario), "rol": rol, "iat": ahora, "exp": expira}
    token = jwt.encode(carga, configuracion.jwt_secreto.get_secret_value(),
                       algorithm=ALGORITMO)
    return token, expira


def leer_token(token: str) -> dict:
    """Devuelve el contenido del token o lanza jwt.InvalidTokenError.

    Cubre firma falsa, token vencido y token mal formado. El algoritmo se fija aquí y
    no se toma del token, para que nadie pueda presentar uno sin firma.
    """
    return jwt.decode(token, configuracion.jwt_secreto.get_secret_value(),
                      algorithms=[ALGORITMO], options={"require": ["exp", "sub"]})
