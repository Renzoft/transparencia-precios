"""Esquema inicial, creado por crear_base_datos.sql.

Esta revisión no ejecuta nada. Marca como punto de partida la base que ya construyó
crear_base_datos.sql y que verificar_bd.py comprobó regla por regla. Así hay una sola
fuente de verdad del esquema inicial, y Alembic se encarga solo de lo que cambie después.

En una base ya creada se aplica con «alembic stamp 0001», no con «upgrade».

Revision ID: 0001
Revises:
Create Date: 2026-10-13
"""
from collections.abc import Sequence

revision: str = "0001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
