"""Área de mercados: mercado, modo_desplazamiento y tarifa."""
from datetime import date
from decimal import Decimal

from sqlalchemy import (BigInteger, Boolean, Date, ForeignKey, Index, Numeric,
                        SmallInteger, String, UniqueConstraint, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.modelos.base import Base


class Mercado(Base):
    """Mercados minoristas. No se borran: se desactivan (RN11)."""
    __tablename__ = "mercado"
    __table_args__ = (
        UniqueConstraint("nombre", "distrito", name="uq_mercado_nombre_distrito"),
        Index("ix_mercado_activo", "activo", postgresql_where=text("activo")),
    )

    id_mercado: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(150))
    distrito: Mapped[str] = mapped_column(String(80))
    direccion: Mapped[str] = mapped_column(String(160))
    latitud: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    longitud: Mapped[Decimal] = mapped_column(Numeric(9, 6))
    horario_atencion: Mapped[str | None] = mapped_column(String(60))
    activo: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))


class ModoDesplazamiento(Base):
    """Los cuatro modos que siembra crear_base_datos.sql."""
    __tablename__ = "modo_desplazamiento"
    __table_args__ = (UniqueConstraint("nombre", name="uq_modo_nombre"),)

    id_modo_desplazamiento: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(40))
    activo: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))


class Tarifa(Base):
    """Tarifas por vigencia: se suceden, no se editan (AD13).

    La regla de que dos tarifas del mismo modo no se solapen en el tiempo la impone la
    restricción de exclusión ex_tarifa_sin_solape, que vive solo en la base de datos.
    """
    __tablename__ = "tarifa"

    id_tarifa: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_modo_desplazamiento: Mapped[int] = mapped_column(
        SmallInteger, ForeignKey("modo_desplazamiento.id_modo_desplazamiento",
                                 ondelete="RESTRICT", name="fk_tarifa_modo"))
    tipo_cobro: Mapped[str] = mapped_column(String(10))
    monto: Mapped[Decimal] = mapped_column(Numeric(8, 2))
    vigente_desde: Mapped[date] = mapped_column(Date)
    vigente_hasta: Mapped[date | None] = mapped_column(Date)
