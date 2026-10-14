"""Pruebas contra la base real transparencia_precios.

No usan datos inventados: comprueban que la API ve lo mismo que dejaron cargado
crear_base_datos.sql y cargar_precios.py.
"""
import pytest
from sqlalchemy import text
from sqlalchemy.exc import ProgrammingError

from app.core.base_datos import FabricaSesion, motor


def test_conecta_como_el_rol_de_la_aplicacion():
    with motor.connect() as cn:
        usuario = cn.execute(text("SELECT current_user")).scalar_one()
    # La API nunca debe conectarse como postgres: app_precios no puede alterar
    # precios ya cargados (RNF010), postgres sí.
    assert usuario == "app_precios"


def test_lee_los_precios_cargados():
    with FabricaSesion() as s:
        n = s.execute(text("SELECT count(*) FROM precio_serie")).scalar_one()
    assert n == 34357


def test_las_tildes_llegan_sanas():
    # El dato semilla con tilde que ya se dañó una vez por la codificación de Windows.
    with FabricaSesion() as s:
        nombres = set(s.execute(text("SELECT nombre FROM modo_desplazamiento")).scalars())
    assert "transporte público" in nombres


def test_el_rol_no_puede_modificar_precios():
    # Si esta prueba falla, la API tendría permiso para alterar precios cargados.
    with FabricaSesion() as s:
        with pytest.raises(ProgrammingError, match="(?i)permiso|permission"):
            s.execute(text("UPDATE precio_serie SET precio_kg = precio_kg "
                           "WHERE id_precio_serie = (SELECT min(id_precio_serie) "
                           "FROM precio_serie)"))
        s.rollback()
