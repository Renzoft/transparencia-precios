"""Caminos de borde que las demás pruebas no recorren.

No están aquí por subir la cobertura: dos son controles de seguridad (el secreto de los
tokens y el límite de bcrypt al guardar una contraseña) y uno es la detección real de
una base caída, que test_salud.py solo simula.
"""
import pytest
from pydantic import ValidationError
from sqlalchemy import create_engine

from app.core import base_datos
from app.core.config import Configuracion
from app.core.errores import _problema
from app.core.seguridad import hash_clave


def test_un_secreto_jwt_corto_impide_arrancar():
    # Con un secreto corto cualquiera podría adivinarlo y fabricar tokens válidos.
    with pytest.raises(ValidationError, match="32 caracteres"):
        Configuracion(pgpassword="x", jwt_secreto="corto")


def test_no_se_guarda_una_clave_de_mas_de_72_bytes():
    # bcrypt ignoraría todo lo que pase de 72 bytes: dos claves distintas que compartan
    # el comienzo valdrían lo mismo. Mejor rechazarla al guardarla.
    with pytest.raises(ValueError, match="72 bytes"):
        hash_clave("ñ" * 40)


def test_detecta_de_verdad_una_base_inaccesible(monkeypatch):
    # Un puerto donde no escucha nadie: la conexión falla de verdad, sin simularla.
    caido = create_engine("postgresql+psycopg://nadie:nada@127.0.0.1:1/ninguna",
                          connect_args={"connect_timeout": 2})
    monkeypatch.setattr(base_datos, "motor", caido)
    assert base_datos.base_responde() is False


def test_un_error_de_validacion_desconocido_tiene_texto_generico():
    assert _problema({"type": "tipo_que_no_existe", "msg": "x"}) == "no es un valor válido"


def test_una_plantilla_sin_sus_datos_no_rompe_la_respuesta():
    # Si Pydantic no manda el límite, se devuelve la frase sin el número.
    assert _problema({"type": "string_too_short", "ctx": {}}) == "debe tener al menos"
