"""Fija la contraseña de un administrador ya registrado.

No es una función del aplicativo: es una herramienta de mantenimiento. Hace falta
porque el administrador inicial lo crea cargar_precios.py con una contraseña aleatoria
que nadie conoce, y porque al desplegar en Railway habrá que fijarla de nuevo.

La contraseña se lee de la variable ADMIN_CLAVE y no se pide por teclado, porque en
Git Bash la lectura oculta de Python no funciona bien. Desde backend/:

    read -s -p "Nueva clave: " ADMIN_CLAVE && export ADMIN_CLAVE
    .venv/Scripts/python.exe -m app.gestion.fijar_clave renzo.munayco@unmsm.edu.pe
    unset ADMIN_CLAVE
"""
import os
import sys

from sqlalchemy import func, select

from app.core.base_datos import FabricaSesion
from app.core.seguridad import LIMITE_BCRYPT, hash_clave
from app.modelos import Usuario

MINIMO = 8   # el mismo mínimo que exige el login (openapi.yaml, SesionCrear)


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("Uso: python -m app.gestion.fijar_clave <correo>")
        return 2
    correo = argv[0].strip().lower()

    clave = os.environ.get("ADMIN_CLAVE", "")
    if not clave:
        print("Falta ADMIN_CLAVE. En Git Bash:\n"
              '  read -s -p "Nueva clave: " ADMIN_CLAVE && export ADMIN_CLAVE')
        return 2
    if len(clave) < MINIMO:
        print("La clave debe tener al menos %d caracteres." % MINIMO)
        return 1
    if len(clave.encode("utf-8")) > LIMITE_BCRYPT:
        print("La clave es demasiado larga: no puede pasar de 72 bytes "
              "(las letras con tilde o eñe ocupan dos).")
        return 1

    with FabricaSesion() as sesion:
        usuario = sesion.scalar(select(Usuario).where(func.lower(Usuario.correo) == correo))
        if usuario is None:
            print("No hay ningún administrador con el correo %s." % correo)
            return 1
        usuario.contrasena_hash = hash_clave(clave)
        sesion.commit()
        print("Clave actualizada para %s." % usuario.correo)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
