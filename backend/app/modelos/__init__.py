"""Las 15 tablas de la base de datos, agrupadas en las seis áreas del Diccionario de Datos.

Importar este paquete registra todas las tablas en Base.metadata, que es lo que leen
Alembic y la prueba que compara los modelos contra la base real.
"""
from app.modelos.base import Base
from app.modelos.catalogo import Producto, Variedad
from app.modelos.mercados import Mercado, ModoDesplazamiento, Tarifa
from app.modelos.precios import PrecioMercado, PrecioSerie
from app.modelos.prediccion import (FactorExplicacion, MetricaModelo, ModeloVersion,
                                    Prediccion)
from app.modelos.seguridad import CargaArchivo, CargaRechazo, Usuario
from app.modelos.uso import IndicadorUso

__all__ = [
    "Base",
    "Usuario", "CargaArchivo", "CargaRechazo",
    "Producto", "Variedad",
    "Mercado", "ModoDesplazamiento", "Tarifa",
    "PrecioSerie", "PrecioMercado",
    "ModeloVersion", "MetricaModelo", "Prediccion", "FactorExplicacion",
    "IndicadorUso",
]
