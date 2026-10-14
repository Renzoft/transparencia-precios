"""Endpoints de /cargas: carga de precios del CU01 (R2, R3). Solo administrador."""
from typing import Annotated

from fastapi import APIRouter, File, Form, Path, Query, UploadFile

from app.core.dependencias import AdminActual, SesionBD
from app.esquemas.carga import (CargaConfirmada, CargaEstado, CargaResumen, Fuente)
from app.esquemas.error import respuestas
from app.servicios import cargas

router = APIRouter(tags=["Administración"])

IdCarga = Annotated[int, Path(alias="id", ge=1, description="Identificador del recurso")]


@router.post("/cargas", status_code=201, response_model=CargaResumen,
             operation_id="crearCarga",
             response_model_exclude_none=True,
             summary="Sube el archivo de precios, lo valida y devuelve el resumen",
             responses={**respuestas(400, 401, 422),
                        409: {"model": respuestas(400)[400]["model"],
                              "description": "El archivo ya fue cargado antes"}})
async def crear_carga(admin: AdminActual, sesion: SesionBD,
                      archivo: Annotated[UploadFile, File()],
                      fuente: Annotated[Fuente, Form()]) -> CargaResumen:
    # Se lee un byte más del máximo: así se sabe si se pasó sin cargar en memoria un
    # archivo arbitrariamente grande.
    contenido = await archivo.read(cargas.TAMANO_MAXIMO + 1)
    resumen = cargas.crear_carga(sesion, admin, archivo.filename or "", contenido, fuente)
    sesion.commit()
    return resumen


@router.get("/cargas", response_model=list[CargaResumen], operation_id="listarCargas",
            response_model_exclude_none=True,
            summary="Historial de cargas", responses=respuestas(401, 422))
def listar_cargas(_: AdminActual, sesion: SesionBD,
                  limite: Annotated[int, Query(ge=1, le=200)] = 50) -> list[CargaResumen]:
    return cargas.listar_cargas(sesion, limite)


@router.get("/cargas/{id}", response_model=CargaResumen, operation_id="obtenerCarga",
            response_model_exclude_none=True,
            summary="Detalle de la carga con el desglose de rechazos",
            responses=respuestas(401, 404, 422))
def obtener_carga(_: AdminActual, sesion: SesionBD, id_carga: IdCarga) -> CargaResumen:
    return cargas.obtener_carga(sesion, id_carga)


@router.patch("/cargas/{id}", response_model=CargaConfirmada, operation_id="resolverCarga",
              summary="Confirma o descarta la carga pendiente",
              responses={**respuestas(401, 404, 422),
                         409: {"model": respuestas(400)[400]["model"],
                               "description": "La carga ya fue confirmada o descartada"}})
def resolver_carga(_: AdminActual, sesion: SesionBD, id_carga: IdCarga,
                   datos: CargaEstado) -> CargaConfirmada:
    resultado = cargas.resolver_carga(sesion, id_carga, datos.estado)
    sesion.commit()
    return resultado
