"""Clase base de todos los modelos.

La fuente de verdad del esquema es crear_base_datos.sql, no estos modelos. Aquí se
calca lo que SQLAlchemy y Alembic necesitan para trabajar y para comparar: columnas,
tipos, nulidad, claves, unicidades e índices.

Las restricciones CHECK y la restricción de exclusión de tarifas no se repiten aquí.
Las impone la base de datos, que es donde tienen que vivir para que ningún cliente
—ni esta API ni pgAdmin— pueda saltárselas, y las verifica verificar_bd.py.
Repetirlas obligaría a mantener dos copias de cada regla.
"""
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
