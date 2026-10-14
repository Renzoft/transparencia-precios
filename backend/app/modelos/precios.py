"""Área de precios: precio_serie y precio_mercado.

Las dos tablas tienen orígenes distintos (Documento de Diseño, sección 5.1):
precio_serie es la serie histórica de Lima que alimenta el modelo; precio_mercado es
el precio vigente de cada mercado, que alimenta el costo total. Ninguna se modifica ni
se borra desde la API: el rol app_precios no tiene esos permisos (RNF010).
"""
from datetime import date
from decimal import Decimal

from sqlalchemy import (BigInteger, Date, ForeignKey, Index, Numeric, String,
                        UniqueConstraint, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.modelos.base import Base


class PrecioSerie(Base):
    __tablename__ = "precio_serie"
    __table_args__ = (
        UniqueConstraint("id_variedad", "fecha", "ambito", name="uq_precio_serie"),
        Index("ix_precio_serie_consulta", "id_variedad", "ambito", text("fecha DESC")),
    )

    id_precio_serie: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_variedad: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("variedad.id_variedad", ondelete="RESTRICT",
                               name="fk_precio_serie_variedad"))
    id_carga_archivo: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("carga_archivo.id_carga_archivo", ondelete="RESTRICT",
                               name="fk_precio_serie_carga"))
    fecha: Mapped[date] = mapped_column(Date)
    ambito: Mapped[str] = mapped_column(String(20))   # minorista_lima | mayorista_lima
    precio_kg: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    volumen_t: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))  # solo mayorista


class PrecioMercado(Base):
    __tablename__ = "precio_mercado"
    __table_args__ = (
        UniqueConstraint("id_mercado", "id_variedad", "fecha", name="uq_precio_mercado"),
        Index("ix_precio_mercado_consulta", "id_mercado", "id_variedad",
              text("fecha DESC")),
    )

    id_precio_mercado: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_mercado: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("mercado.id_mercado", ondelete="RESTRICT",
                               name="fk_precio_mercado_mercado"))
    id_variedad: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("variedad.id_variedad", ondelete="RESTRICT",
                               name="fk_precio_mercado_variedad"))
    id_carga_archivo: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("carga_archivo.id_carga_archivo", ondelete="RESTRICT",
                               name="fk_precio_mercado_carga"))
    fecha: Mapped[date] = mapped_column(Date)
    precio_kg: Mapped[Decimal] = mapped_column(Numeric(10, 2))
