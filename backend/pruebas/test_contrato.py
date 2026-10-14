"""La API debe cumplir el contrato openapi.yaml.

Tres niveles, de lo más estructural a lo más real:

1. La API no expone ninguna operación que el contrato no declare.
2. Cada operación implementada coincide con el contrato en ruta, método,
   identificador, código de éxito, códigos de error y campos de entrada.
3. Las respuestas que la API devuelve de verdad validan contra los esquemas del
   contrato. Esto es lo que importa: un esquema bien declarado no sirve de nada si la
   respuesta real no lo cumple.

Las operaciones del contrato que aún no están implementadas no son un fallo: se
construyen en las actividades «Implementación del CU01» a «CU06» del cronograma.
"""
import pytest
from openapi_spec_validator import validate
from fastapi.testclient import TestClient
from sqlalchemy import delete

from app.core.base_datos import FabricaSesion
from app.core.seguridad import hash_clave
from app.main import app
from app.modelos import Usuario
from pruebas.contrato import (FUERA_DEL_CONTRATO, PREFIJO, a_jsonschema, contrato,
                              operaciones, validar_respuesta)

cliente = TestClient(app)


def implementadas() -> dict:
    """Operaciones que la API expone, con la ruta sin el prefijo /api/v1."""
    out = {}
    for (metodo, ruta), op in operaciones(app.openapi()).items():
        if ruta in FUERA_DEL_CONTRATO:
            continue
        assert ruta.startswith(PREFIJO), "%s %s no cuelga de %s" % (metodo, ruta, PREFIJO)
        out[(metodo, ruta[len(PREFIJO):])] = op
    return out


# ------------------------------------------------------------- 0. el contrato mismo
def test_el_contrato_es_un_openapi_valido():
    validate(contrato())


def test_la_api_genera_un_openapi_valido():
    validate(app.openapi())


# ------------------------------------------------------------------- 1. nada de más
def test_la_api_no_expone_nada_fuera_del_contrato():
    sobrantes = set(implementadas()) - set(operaciones(contrato()))
    assert not sobrantes, "operaciones que el contrato no declara: %s" % sorted(sobrantes)


# ----------------------------------------------- 2. cada operación como dice el contrato
def _codigos(op: dict) -> set[str]:
    return set(op.get("responses", {}))


@pytest.mark.parametrize("clave", sorted(implementadas()), ids=lambda c: "%s %s" % c)
def test_operacion_coincide_con_el_contrato(clave):
    real, pactada = implementadas()[clave], operaciones(contrato())[clave]

    assert real.get("operationId") == pactada.get("operationId"), (
        "operationId: la API tiene %r y el contrato %r"
        % (real.get("operationId"), pactada.get("operationId")))
    assert _codigos(real) == _codigos(pactada), (
        "códigos de respuesta: la API declara %s y el contrato %s"
        % (sorted(_codigos(real)), sorted(_codigos(pactada))))

    # Campos de entrada: mismos nombres, mismos obligatorios y mismos límites.
    if "requestBody" in pactada:
        esq_p = a_jsonschema(pactada["requestBody"]["content"]["application/json"]["schema"])
        esq_r = a_jsonschema(real["requestBody"]["content"]["application/json"]["schema"],
                             app.openapi())
        assert set(esq_r["properties"]) == set(esq_p["properties"])
        assert set(esq_r.get("required", [])) == set(esq_p.get("required", []))
        for campo, p in esq_p["properties"].items():
            r = esq_r["properties"][campo]
            for limite in ("minLength", "maxLength", "minimum", "maximum", "enum"):
                if limite in p:
                    assert r.get(limite) == p[limite], (
                        "%s.%s: la API tiene %r y el contrato %r"
                        % (campo, limite, r.get(limite), p[limite]))


def test_avance_de_la_implementacion():
    # No falla: informa cuánto del contrato está construido.
    total = operaciones(contrato())
    hechas = implementadas()
    pendientes = sorted(set(total) - set(hechas))
    print("\nOperaciones implementadas: %d de %d" % (len(hechas), len(total)))
    for metodo, ruta in pendientes:
        print("  pendiente: %-6s %s" % (metodo, ruta))
    assert len(hechas) <= len(total)


# ------------------------------------------------ 3. las respuestas reales lo cumplen
CORREO = "prueba.contrato@unmsm.edu.pe"
CLAVE = "clave-del-contrato-1"


@pytest.fixture
def admin():
    with FabricaSesion() as s:
        s.execute(delete(Usuario).where(Usuario.correo == CORREO))
        s.add(Usuario(correo=CORREO, contrasena_hash=hash_clave(CLAVE), nombre="Contrato"))
        s.commit()
    yield
    with FabricaSesion() as s:
        s.execute(delete(Usuario).where(Usuario.correo == CORREO))
        s.commit()


@pytest.mark.parametrize("caso, cuerpo, codigo", [
    ("credenciales correctas", {"correo": CORREO, "contrasena": CLAVE}, 201),
    ("credenciales incorrectas", {"correo": CORREO, "contrasena": "otra-clave-9"}, 401),
    ("datos no válidos", {"correo": "no-es-correo", "contrasena": "123"}, 422),
])
def test_respuestas_reales_de_post_sesiones(admin, caso, cuerpo, codigo):
    r = cliente.post(PREFIJO + "/sesiones", json=cuerpo)
    assert r.status_code == codigo
    validar_respuesta("POST", "/sesiones", r)
