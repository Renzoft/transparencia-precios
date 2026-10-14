"""Esquema inicial, creado por crear_base_datos.sql.

Esta revisión no ejecuta nada. Marca como punto de partida la base que ya construyó
crear_base_datos.sql y que verificar_bd.py comprobó regla por regla. Así hay una sola
fuente de verdad del esquema inicial, y Alembic se encarga solo de lo que cambie después.

Regla del proyecto: cada migración posterior se refleja también en
crear_base_datos.sql, que sigue siendo el esquema completo. Por eso una base recién
creada con ese script ya está al día y se marca con «alembic stamp head»; una base
existente se pone al día con «alembic upgrade head».

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
