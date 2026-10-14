"""La huella de un archivo deja de bloquearlo si su carga anterior se descartó.

Antes, la restricción uq_carga_hash impedía volver a subir un archivo para siempre, aunque
su carga se hubiera descartado. Descartar por error obligaba a exportar otro archivo del
SISAP con un rango de fechas distinto. Ahora la unicidad solo cuenta las cargas
pendientes y confirmadas, que son las que de verdad representan ese archivo.

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-14
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | Sequence[str] | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_constraint("uq_carga_hash", "carga_archivo", type_="unique")
    op.create_index("uq_carga_hash", "carga_archivo", ["hash_archivo"], unique=True,
                    postgresql_where=sa.text("estado <> 'descartada'"))


def downgrade() -> None:
    # Falla si ya hay un archivo subido dos veces (una descartada y otra no): es la
    # situación que esta migración vino a permitir.
    op.drop_index("uq_carga_hash", table_name="carga_archivo")
    op.create_unique_constraint("uq_carga_hash", "carga_archivo", ["hash_archivo"])
