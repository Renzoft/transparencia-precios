"""Endpoints de /mercados (CU02, R4).

Consultar es público: el consumidor necesita los mercados para comparar (CU05).
Registrar, modificar y desactivar es solo del administrador.
"""
from typing import Annotated

from fastapi import APIRouter, Path, Query

from app.core.dependencias import AdminActual, AdminOpcional, SesionBD
from app.core.errores import ErrorAPI
from app.esquemas.error import Error, respuestas
from app.esquemas.mercado import Mercado, MercadoActualizar, MercadoCrear
from app.servicios import mercados

router = APIRouter()

IdMercado = Annotated[int, Path(alias="id", ge=1, description="Identificador del recurso")]
REPETIDO = {"model": Error, "description": "Ya existe un mercado con ese nombre en ese distrito"}


@router.get("/mercados", response_model=list[Mercado], tags=["Catálogo"],
            operation_id="listarMercados", summary="Mercados activos",
            responses=respuestas(401, 422))
def listar_mercados(sesion: SesionBD, admin: AdminOpcional,
                    distrito: Annotated[str | None, Query(max_length=80)] = None,
                    incluir_inactivos: bool = False) -> list[Mercado]:
    if incluir_inactivos and admin is None:
        raise ErrorAPI(401, "NO_AUTENTICADO",
                       "Ver los mercados desactivados requiere iniciar sesión como "
                       "administrador.")
    return mercados.listar(sesion, distrito, incluir_inactivos)


@router.post("/mercados", status_code=201, response_model=Mercado, tags=["Administración"],
             operation_id="crearMercado", summary="Registra un mercado minorista",
             responses={**respuestas(401, 422), 409: REPETIDO})
def crear_mercado(_: AdminActual, sesion: SesionBD, datos: MercadoCrear) -> Mercado:
    mercado = mercados.crear(sesion, datos)
    sesion.commit()
    return mercado


@router.get("/mercados/{id}", response_model=Mercado, tags=["Catálogo"],
            operation_id="obtenerMercado", summary="Detalle de un mercado",
            responses=respuestas(401, 404, 422))
def obtener_mercado(sesion: SesionBD, admin: AdminOpcional, id_mercado: IdMercado) -> Mercado:
    return mercados.obtener(sesion, id_mercado, es_admin=admin is not None)


@router.patch("/mercados/{id}", response_model=Mercado, tags=["Administración"],
              operation_id="actualizarMercado", summary="Modifica o desactiva un mercado",
              responses={**respuestas(401, 404, 422), 409: REPETIDO})
def actualizar_mercado(_: AdminActual, sesion: SesionBD, id_mercado: IdMercado,
                       datos: MercadoActualizar) -> Mercado:
    mercado = mercados.actualizar(sesion, id_mercado, datos)
    sesion.commit()
    return mercado
