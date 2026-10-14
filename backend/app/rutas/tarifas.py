"""Endpoints de /modos-desplazamiento y /tarifas (CU02, R5).

Los modos son públicos: el consumidor elige uno al comparar mercados (CU05). Las
tarifas solo las consulta y registra el administrador.
"""
from fastapi import APIRouter

from app.core.dependencias import AdminActual, SesionBD
from app.esquemas.error import Error, respuestas
from app.esquemas.tarifa import ModoDesplazamiento, Tarifa, TarifaCrear
from app.servicios import tarifas

router = APIRouter()


@router.get("/modos-desplazamiento", response_model=list[ModoDesplazamiento],
            tags=["Catálogo"], operation_id="listarModosDesplazamiento",
            summary="Modos de desplazamiento disponibles")
def listar_modos(sesion: SesionBD) -> list[ModoDesplazamiento]:
    return tarifas.listar_modos(sesion)


# exclude_unset: tarifa_cerrada solo aparece en la respuesta del registro.
@router.get("/tarifas", response_model=list[Tarifa], response_model_exclude_unset=True,
            tags=["Administración"], operation_id="listarTarifas",
            summary="Tarifas vigentes e históricas", responses=respuestas(401, 422))
def listar_tarifas(_: AdminActual, sesion: SesionBD, vigentes: bool = False) -> list[Tarifa]:
    return tarifas.listar(sesion, vigentes)


@router.post("/tarifas", status_code=201, response_model=Tarifa, tags=["Administración"],
             operation_id="crearTarifa",
             summary="Registra una nueva vigencia y cierra la anterior",
             responses={**respuestas(401, 422),
                        409: {"model": Error, "description": "La vigencia se solapa con "
                              "una tarifa existente del mismo modo"}})
def crear_tarifa(_: AdminActual, sesion: SesionBD, datos: TarifaCrear) -> Tarifa:
    tarifa = tarifas.crear(sesion, datos)
    sesion.commit()
    return tarifa
