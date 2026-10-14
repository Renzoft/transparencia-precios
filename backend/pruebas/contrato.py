"""Lectura del contrato openapi.yaml para las pruebas.

El contrato es la fuente de verdad de la API (Hito 2, «Diseño de la API REST»). Estas
utilidades lo cargan y traducen sus esquemas a JSON Schema, para validar contra ellos
las respuestas reales de la API.
"""
from functools import cache
from pathlib import Path

import jsonschema
from openapi_spec_validator.readers import read_from_filename

RUTA_CONTRATO = Path(__file__).resolve().parents[2] / "openapi.yaml"
PREFIJO = "/api/v1"
METODOS = {"get", "post", "put", "patch", "delete"}

# Rutas de operación que no forman parte del contrato a propósito.
FUERA_DEL_CONTRATO = {"/salud"}


@cache
def contrato() -> dict:
    spec, _ = read_from_filename(str(RUTA_CONTRATO))
    return spec


def operaciones(spec: dict) -> dict[tuple[str, str], dict]:
    """{(MÉTODO, ruta sin prefijo): operación} de un documento OpenAPI."""
    out = {}
    for ruta, item in spec.get("paths", {}).items():
        for metodo, op in item.items():
            if metodo in METODOS:
                out[(metodo.upper(), ruta)] = op
    return out


def _resolver(nodo, raiz: dict):
    """Sigue los $ref hasta llegar al objeto real."""
    while isinstance(nodo, dict) and "$ref" in nodo:
        partes = nodo["$ref"].lstrip("#/").split("/")
        nodo = raiz
        for p in partes:
            nodo = nodo[p]
    return nodo


def a_jsonschema(nodo, raiz: dict | None = None):
    """Traduce un esquema de OpenAPI 3.0 a JSON Schema: resuelve $ref y nullable."""
    raiz = raiz or contrato()
    nodo = _resolver(nodo, raiz)
    if isinstance(nodo, list):
        return [a_jsonschema(n, raiz) for n in nodo]
    if not isinstance(nodo, dict):
        return nodo
    out = {k: a_jsonschema(v, raiz) for k, v in nodo.items()
           if k not in ("nullable", "description", "example", "format")}
    if nodo.get("nullable"):
        return {"anyOf": [out, {"type": "null"}]}
    return out


def esquema_respuesta(metodo: str, ruta: str, codigo: int) -> dict:
    """El esquema JSON que el contrato fija para una respuesta concreta."""
    spec = contrato()
    op = spec["paths"][ruta][metodo.lower()]
    resp = _resolver(op["responses"][str(codigo)], spec)
    return a_jsonschema(resp["content"]["application/json"]["schema"])


def validar_respuesta(metodo: str, ruta: str, respuesta) -> None:
    """Falla si el cuerpo real de la respuesta no cumple el esquema del contrato."""
    esquema = esquema_respuesta(metodo, ruta, respuesta.status_code)
    jsonschema.validate(respuesta.json(), esquema)
