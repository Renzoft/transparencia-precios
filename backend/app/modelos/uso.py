"""Área de uso: indicador_uso, la fuente de los indicadores de la tesis (R18).

No contiene ningún dato que identifique al consumidor (RN12, RNF003).
"""
from datetime import datetime
from decimal import Decimal

from sqlalchemy import (BigInteger, Computed, DateTime, ForeignKey, Index, Integer,
                        Numeric, String, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.modelos.base import Base


class IndicadorUso(Base):
    __tablename__ = "indicador_uso"
    __table_args__ = (Index("ix_indicador_fecha", "ocurrido_en"),)

    id_indicador_uso: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_mercado: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("mercado.id_mercado", ondelete="RESTRICT",
                               name="fk_indicador_mercado"))
    ocurrido_en: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                  server_default=text("now()"))
    segundos_hasta_eleccion: Mapped[int] = mapped_column(Integer)
    tipo_referencia: Mapped[str] = mapped_column(String(20))
    costo_elegido: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    costo_referencia: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    # Columna generada por la base.
    ahorro_neto: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), Computed("costo_referencia - costo_elegido", persisted=True))
