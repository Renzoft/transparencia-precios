"""Área del modelo predictivo: modelo_version, metrica_modelo, prediccion y
factor_explicacion.

Hay dos modelos vigentes a la vez, uno por propósito: «nivel» da el precio
pronosticado y «tendencia» la dirección del cambio (Diseño del Modelo Predictivo,
sección 7). Una fila de prediccion lleva las dos salidas.
"""
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (BigInteger, Boolean, Computed, Date, DateTime, ForeignKey,
                        Index, Numeric, SmallInteger, String, UniqueConstraint, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.modelos.base import Base


class ModeloVersion(Base):
    """Única fuente de verdad sobre qué versión de cada modelo está en uso (RNF015)."""
    __tablename__ = "modelo_version"
    __table_args__ = (
        UniqueConstraint("nombre_archivo", name="uq_modelo_archivo"),
        # Una sola versión vigente por propósito.
        Index("uq_modelo_vigente", "proposito", unique=True,
              postgresql_where=text("vigente")),
    )

    id_modelo_version: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    nombre_archivo: Mapped[str] = mapped_column(String(255))
    algoritmo: Mapped[str] = mapped_column(String(60))
    proposito: Mapped[str] = mapped_column(String(12))        # nivel | tendencia
    fecha_entrenamiento: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    datos_desde: Mapped[date] = mapped_column(Date)
    datos_hasta: Mapped[date] = mapped_column(Date)
    vigente: Mapped[bool] = mapped_column(Boolean, server_default=text("false"))


class MetricaModelo(Base):
    """Desempeño por variedad y horizonte (R7). id_variedad nulo = métrica global."""
    __tablename__ = "metrica_modelo"
    __table_args__ = (
        UniqueConstraint("id_modelo_version", "id_variedad", "horizonte_semanas",
                         name="uq_metrica", postgresql_nulls_not_distinct=True),
    )

    id_metrica_modelo: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_modelo_version: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("modelo_version.id_modelo_version", ondelete="CASCADE",
                               name="fk_metrica_modelo"))
    id_variedad: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("variedad.id_variedad", ondelete="RESTRICT",
                               name="fk_metrica_variedad"))
    horizonte_semanas: Mapped[int] = mapped_column(SmallInteger)
    mae: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    wape: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    mase: Mapped[Decimal | None] = mapped_column(Numeric(7, 4))
    exactitud_direccional: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))


class Prediccion(Base):
    """Pronóstico a nivel de Lima Metropolitana por variedad (R6, RN02)."""
    __tablename__ = "prediccion"
    __table_args__ = (
        UniqueConstraint("id_variedad", "fecha_objetivo", "horizonte_semanas",
                         "id_modelo_version", name="uq_prediccion"),
        # Impide mostrar dos pronósticos distintos del mismo producto y semana (RNF009).
        Index("uq_prediccion_vigente", "id_variedad", "fecha_objetivo",
              "horizonte_semanas", unique=True, postgresql_where=text("vigente")),
        Index("ix_prediccion_vigente", "id_variedad", "horizonte_semanas",
              postgresql_where=text("vigente")),
    )

    id_prediccion: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_variedad: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("variedad.id_variedad", ondelete="RESTRICT",
                               name="fk_prediccion_variedad"))
    id_modelo_version: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("modelo_version.id_modelo_version", ondelete="RESTRICT",
                               name="fk_prediccion_modelo"))
    id_modelo_tendencia: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("modelo_version.id_modelo_version", ondelete="RESTRICT",
                               name="fk_prediccion_modelo_tendencia"))
    fecha_generacion: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                       server_default=text("now()"))
    fecha_ultimo_dato: Mapped[date] = mapped_column(Date)     # se muestra (R9)
    horizonte_semanas: Mapped[int] = mapped_column(SmallInteger)
    # Columna generada por la base: la API la lee, nunca la escribe.
    fecha_objetivo: Mapped[date] = mapped_column(
        Date, Computed("fecha_ultimo_dato + (horizonte_semanas * 7)", persisted=True))
    precio_estimado_kg: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    tendencia: Mapped[str | None] = mapped_column(String(12))
    confianza_tendencia: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    vigente: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))


class FactorExplicacion(Base):
    """Hasta tres factores por predicción, sin lenguaje causal (R10, RN05)."""
    __tablename__ = "factor_explicacion"
    __table_args__ = (UniqueConstraint("id_prediccion", "orden", name="uq_factor_orden"),)

    id_factor_explicacion: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_prediccion: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("prediccion.id_prediccion", ondelete="CASCADE",
                               name="fk_factor_prediccion"))
    orden: Mapped[int] = mapped_column(SmallInteger)
    descripcion: Mapped[str] = mapped_column(String(200))
    contribucion: Mapped[Decimal] = mapped_column(Numeric(8, 4))
