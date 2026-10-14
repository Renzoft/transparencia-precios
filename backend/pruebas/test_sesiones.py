"""Inicio de sesión del administrador y protección de los endpoints (R1, RNF001).

Las pruebas crean su propio administrador en la base real, con una clave conocida, y
lo borran al terminar. El administrador verdadero no se toca.
"""
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import delete

from app.core.base_datos import FabricaSesion
from app.core.config import configuracion
from app.core.dependencias import AdminActual
from app.core.errores import ErrorAPI, manejar_error_api
from app.core.seguridad import ALGORITMO, crear_token, hash_clave
from app.main import app
from app.modelos import Usuario

cliente = TestClient(app)

CORREO = "prueba.sesion@unmsm.edu.pe"
CLAVE = "clave-de-prueba-123"
MENSAJE = "Usuario o contraseña incorrectos"


@pytest.fixture
def admin():
    with FabricaSesion() as s:
        s.execute(delete(Usuario).where(Usuario.correo == CORREO))
        u = Usuario(correo=CORREO, contrasena_hash=hash_clave(CLAVE), nombre="Prueba")
        s.add(u)
        s.commit()
        s.refresh(u)
        id_usuario = u.id_usuario
    yield id_usuario
    with FabricaSesion() as s:
        s.execute(delete(Usuario).where(Usuario.id_usuario == id_usuario))
        s.commit()


def entrar(correo, clave):
    return cliente.post("/api/v1/sesiones", json={"correo": correo, "contrasena": clave})


# ------------------------------------------------------------------ inicio de sesión
def test_credenciales_correctas_devuelven_token(admin):
    r = entrar(CORREO, CLAVE)
    assert r.status_code == 201
    cuerpo = r.json()
    assert cuerpo["tipo"] == "Bearer"
    assert cuerpo["usuario"] == {"nombre": "Prueba", "rol": "administrador"}

    contenido = jwt.decode(cuerpo["token"], configuracion.jwt_secreto.get_secret_value(),
                           algorithms=[ALGORITMO])
    assert contenido["sub"] == str(admin)


def test_el_token_dura_ocho_horas(admin):
    antes = datetime.now(UTC)
    expira = datetime.fromisoformat(entrar(CORREO, CLAVE).json()["expira_en"])
    # Se toma la hora antes de la petición, así que se tolera lo que ella demore.
    assert abs((expira - antes) - timedelta(hours=8)) < timedelta(minutes=1)


def test_el_correo_no_distingue_mayusculas(admin):
    assert entrar(CORREO.upper(), CLAVE).status_code == 201


def test_el_token_no_lleva_datos_personales(admin):
    token = entrar(CORREO, CLAVE).json()["token"]
    contenido = jwt.decode(token, options={"verify_signature": False})
    assert set(contenido) == {"sub", "rol", "iat", "exp"}


@pytest.mark.parametrize("caso, correo, clave", [
    ("clave equivocada", CORREO, "otra-clave-999"),
    ("correo inexistente", "nadie@unmsm.edu.pe", CLAVE),
])
def test_credenciales_malas_responden_igual(admin, caso, correo, clave):
    r = entrar(correo, clave)
    assert r.status_code == 401
    # Mismo cuerpo exista o no el correo: el contrato prohíbe dar pistas.
    assert r.json() == {"error": {"codigo": "CREDENCIALES_INVALIDAS", "mensaje": MENSAJE}}
    assert r.headers["WWW-Authenticate"] == "Bearer"


def test_cuenta_desactivada_no_entra(admin):
    with FabricaSesion() as s:
        s.get(Usuario, admin).activo = False
        s.commit()
    r = entrar(CORREO, CLAVE)
    assert r.status_code == 401
    assert r.json()["error"]["mensaje"] == MENSAJE


def test_clave_de_mas_de_72_bytes_no_rompe_el_servidor(admin):
    # 40 eñes son 40 caracteres, dentro del máximo del contrato, pero 80 bytes:
    # bcrypt 5 lanzaría un error y la API respondería 500 si no se controlara.
    r = entrar(CORREO, "ñ" * 40)
    assert r.status_code == 401


# ---------------------------------------------------- protección de los endpoints
# Todavía no hay endpoints de administración: se monta uno mínimo solo para probar
# la dependencia que todos ellos van a usar.
protegida = FastAPI()
protegida.add_exception_handler(ErrorAPI, manejar_error_api)


@protegida.get("/solo-admin")
def solo_admin(usuario: AdminActual):
    return {"correo": usuario.correo}


cliente_protegido = TestClient(protegida)


def pedir(token=None):
    cabeceras = {"Authorization": "Bearer " + token} if token else {}
    return cliente_protegido.get("/solo-admin", headers=cabeceras)


def test_con_token_valido_pasa(admin):
    token = entrar(CORREO, CLAVE).json()["token"]
    r = pedir(token)
    assert r.status_code == 200
    assert r.json() == {"correo": CORREO}


def test_sin_token_responde_401(admin):
    r = pedir()
    assert r.status_code == 401
    assert r.json()["error"]["codigo"] == "NO_AUTENTICADO"


def test_token_basura_responde_401(admin):
    assert pedir("esto-no-es-un-token").status_code == 401


def test_token_vencido_responde_401(admin):
    ahora = datetime.now(UTC)
    vencido = jwt.encode({"sub": str(admin), "rol": "administrador",
                          "iat": ahora - timedelta(hours=9),
                          "exp": ahora - timedelta(hours=1)},
                         configuracion.jwt_secreto.get_secret_value(), algorithm=ALGORITMO)
    assert pedir(vencido).status_code == 401


def test_token_firmado_con_otra_clave_responde_401(admin):
    falso = jwt.encode({"sub": str(admin), "rol": "administrador",
                        "exp": datetime.now(UTC) + timedelta(hours=1)},
                       "un-secreto-que-no-es-el-de-la-api-" + "x" * 20,
                       algorithm=ALGORITMO)
    assert pedir(falso).status_code == 401


def test_token_sin_firma_responde_401(admin):
    # El ataque clásico contra JWT: declarar «alg: none» y omitir la firma.
    sin_firma = jwt.encode({"sub": str(admin), "rol": "administrador",
                            "exp": datetime.now(UTC) + timedelta(hours=1)},
                           key=None, algorithm="none")
    assert pedir(sin_firma).status_code == 401


def test_desactivar_al_admin_invalida_su_token_al_instante(admin):
    token, _ = crear_token(admin, "administrador")
    assert pedir(token).status_code == 200
    with FabricaSesion() as s:
        s.get(Usuario, admin).activo = False
        s.commit()
    assert pedir(token).status_code == 401


# ------------------------------------------------------ comando para fijar la clave
from app.gestion import fijar_clave  # noqa: E402


def test_fijar_clave_permite_entrar_con_la_nueva(admin, monkeypatch):
    monkeypatch.setenv("ADMIN_CLAVE", "una-clave-nueva-456")
    assert fijar_clave.main([CORREO]) == 0
    assert entrar(CORREO, "una-clave-nueva-456").status_code == 201
    assert entrar(CORREO, CLAVE).status_code == 401   # la anterior ya no sirve


@pytest.mark.parametrize("caso, clave, correo, codigo", [
    ("sin variable", None, CORREO, 2),
    ("clave corta", "corta", CORREO, 1),
    ("más de 72 bytes", "ñ" * 40, CORREO, 1),
    ("correo que no existe", "una-clave-valida-789", "nadie@unmsm.edu.pe", 1),
])
def test_fijar_clave_rechaza_y_no_cambia_nada(admin, monkeypatch, caso, clave, correo, codigo):
    if clave is None:
        monkeypatch.delenv("ADMIN_CLAVE", raising=False)
    else:
        monkeypatch.setenv("ADMIN_CLAVE", clave)
    assert fijar_clave.main([correo]) == codigo
    assert entrar(CORREO, CLAVE).status_code == 201   # la clave original sigue igual


def test_fijar_clave_sin_correo_muestra_el_uso():
    assert fijar_clave.main([]) == 2
