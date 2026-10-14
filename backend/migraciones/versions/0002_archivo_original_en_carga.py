"""Guarda el archivo original de cada carga en carga_archivo.

La carga de precios se confirma en dos pasos (CU01, AD10): primero se valida y se
muestra el resumen, después el administrador confirma. Entre esos dos pasos el archivo
tiene que guardarse en algún lado, y la arquitectura prohíbe que sea la memoria del
servidor. Guardarlo en la base resuelve eso y además liga cada precio al archivo exacto
del que salió (RNF010).

Nulo en las cargas históricas iniciales, hechas desde CSV por cargar_precios.py.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-14
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("carga_archivo",
                  sa.Column("contenido_archivo", sa.LargeBinary(), nullable=True))


def downgrade() -> None:
    op.drop_column("carga_archivo", "contenido_archivo")
