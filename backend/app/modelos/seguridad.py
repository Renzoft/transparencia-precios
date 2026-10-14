"""Área de seguridad y carga de datos: usuario, carga_archivo, carga_rechazo."""
from datetime import datetime

from sqlalchemy import (CHAR, BigInteger, Boolean, DateTime, ForeignKey, Index,
                        Integer, LargeBinary, String, UniqueConstraint, text)
from sqlalchemy.orm import Mapped, deferred, mapped_column

from app.modelos.base import Base


class Usuario(Base):
    """Administradores del panel. El consumidor no se registra (RNF003)."""
    __tablename__ = "usuario"
    __table_args__ = (UniqueConstraint("correo", name="uq_usuario_correo"),)

    id_usuario: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    correo: Mapped[str] = mapped_column(String(120))
    contrasena_hash: Mapped[str] = mapped_column(CHAR(60))      # bcrypt (RNF001)
    nombre: Mapped[str] = mapped_column(String(120))
    rol: Mapped[str] = mapped_column(String(20), server_default=text("'administrador'"))
    activo: Mapped[bool] = mapped_column(Boolean, server_default=text("true"))


class CargaArchivo(Base):
    """Cada archivo cargado. El hash impide cargar dos veces el mismo."""
    __tablename__ = "carga_archivo"
    __table_args__ = (
        # Huella única salvo en las cargas descartadas, que no bloquean volver a subirla.
        Index("uq_carga_hash", "hash_archivo", unique=True,
              postgresql_where=text("estado <> 'descartada'")),
    )

    id_carga_archivo: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_usuario: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("usuario.id_usuario", ondelete="RESTRICT",
                               name="fk_carga_usuario"))
    nombre_archivo: Mapped[str] = mapped_column(String(255))
    hash_archivo: Mapped[str] = mapped_column(CHAR(64))         # SHA-256
    fuente: Mapped[str] = mapped_column(String(30))
    fecha_carga: Mapped[datetime] = mapped_column(DateTime(timezone=True),
                                                  server_default=text("now()"))
    registros_validos: Mapped[int] = mapped_column(Integer)
    registros_rechazados: Mapped[int] = mapped_column(Integer)
    estado: Mapped[str] = mapped_column(String(12), server_default=text("'pendiente'"))
    # El archivo original. «deferred»: no se trae de la base salvo que se pida, para que
    # listar el historial de cargas no arrastre el contenido de cada archivo.
    contenido_archivo: Mapped[bytes | None] = deferred(mapped_column(LargeBinary))


class CargaRechazo(Base):
    """Cuántos registros se rechazaron en una carga y por qué motivo (R3)."""
    __tablename__ = "carga_rechazo"
    __table_args__ = (UniqueConstraint("id_carga_archivo", "motivo",
                                       name="uq_rechazo_carga_motivo"),)

    id_carga_rechazo: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    id_carga_archivo: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("carga_archivo.id_carga_archivo", ondelete="CASCADE",
                               name="fk_rechazo_carga"))
    motivo: Mapped[str] = mapped_column(String(60))
    cantidad: Mapped[int] = mapped_column(Integer)
