"""Área de catálogo: producto y variedad."""
from decimal import Decimal

from sqlalchemy import (BigInteger, Boolean, ForeignKey, Numeric, String,
                        UniqueConstraint, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.modelos.base import Base


class Producto(Base):
    __tablename__ = "producto"
    __table_args__ = (UniqueConstraint("nombre", name="uq_producto_nombre"),)

    id_producto: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    nombre: Mapped[str] = mapped_column(String(120))
    activo: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))


class Variedad(Base):
    """Nivel al que se registran los precios y se generan las predicciones."""
    __tablename__ = "variedad"
    __table_args__ = (UniqueConstraint("id_producto", "nombre",
                                       name="uq_variedad_producto_nombre"),)

    id_variedad: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_producto: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("producto.id_producto", ondelete="RESTRICT",
                               name="fk_variedad_producto"))
    nombre: Mapped[str] = mapped_column(String(120))
    unidad_origen: Mapped[str] = mapped_column(String(20))
    factor_a_kg: Mapped[Decimal] = mapped_column(Numeric(10, 4))   # RN10
    activo: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))
