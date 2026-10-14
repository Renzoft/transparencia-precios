"""Nombres de variedad iguales a los del SISAP.

El catálogo inicial lo armó cargar_precios.py con nombres descriptivos propios. Cuatro no
coincidían con los que usa el SISAP, que es como vienen en la cabecera de los archivos
que sube el administrador. Sin esta corrección, un archivo de limón se habría tomado
como una variedad nueva y la serie histórica habría quedado partida en dos.

Nombres verificados en el árbol de productos del portal del SISAP el 2026-10-14.
Es una migración de datos, no de esquema: crear_base_datos.sql no cambia; el que cambia
es cargar_precios.py, que ya crea las variedades con estos nombres.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-14
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# (nombre anterior, nombre del SISAP)
CAMBIOS = [
    ("Limón sutil", "Limon sutil bolsa"),
    ("Azúcar rubia a granel", "Azucar rubia nacional (granel)"),
    ("Aceite vegetal botella 900 ml", "Aceite clásico botella 900 ml"),
    ("Carne de pollo eviscerado", "Carne de pollo (eviscerado)"),
]

_renombrar = sa.text("UPDATE variedad SET nombre = :nuevo WHERE nombre = :viejo")


def upgrade() -> None:
    for viejo, nuevo in CAMBIOS:
        op.execute(_renombrar.bindparams(viejo=viejo, nuevo=nuevo))


def downgrade() -> None:
    for viejo, nuevo in CAMBIOS:
        op.execute(_renombrar.bindparams(viejo=nuevo, nuevo=viejo))
