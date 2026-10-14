"""Los modelos SQLAlchemy deben ser un calco exacto de la base real.

La comparación la hace Alembic, la misma herramienta que generará las migraciones: si
aquí dice que no hay diferencias, una migración autogenerada tampoco encontraría ninguna.
Se comprobó que detecta un largo de columna distinto, una nulidad cambiada y un índice
olvidado.
"""
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import func, select

from app.core.base_datos import FabricaSesion, motor
from app.modelos import Base, ModoDesplazamiento, PrecioSerie, Variedad

TABLAS_DEL_DICCIONARIO = {
    "usuario", "carga_archivo", "carga_rechazo", "producto", "variedad",
    "precio_serie", "precio_mercado", "mercado", "modo_desplazamiento", "tarifa",
    "modelo_version", "metrica_modelo", "prediccion", "factor_explicacion",
    "indicador_uso",
}


def test_hay_un_modelo_por_cada_tabla_del_diccionario():
    assert set(Base.metadata.tables) == TABLAS_DEL_DICCIONARIO


def test_los_modelos_coinciden_con_la_base_real():
    with motor.connect() as cn:
        diferencias = compare_metadata(MigrationContext.configure(cn), Base.metadata)
    # La tabla de control de Alembic no es parte del diccionario de datos.
    diferencias = [d for d in diferencias
                   if not (d[0] == "remove_table" and d[1].name == "alembic_version")]
    assert diferencias == []


def test_el_orm_lee_datos_reales():
    with FabricaSesion() as s:
        n = s.scalar(select(func.count()).select_from(PrecioSerie))
        variedades = s.scalar(select(func.count()).select_from(Variedad))
        modos = set(s.scalars(select(ModoDesplazamiento.nombre)))
    assert n == 34357
    assert variedades == 10
    assert modos == {"a pie", "transporte público", "taxi", "auto particular"}
