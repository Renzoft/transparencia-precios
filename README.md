# transparencia-precios

Código del aplicativo móvil para mejorar la transparencia de precios en mercados
minoristas de Lima Metropolitana, mediante predicción con Machine Learning y cálculo
del costo total de compra.

Tesis de Renzo Alexander Munayco Vivanco — Ingeniería de Software, UNMSM.

## Estructura

```
openapi.yaml    contrato de la API: lo que el backend debe cumplir
base_datos/     crear_base_datos.sql, el esquema de la base
backend/        API REST en Python con FastAPI
  app/
    core/       configuración, conexión a la base, seguridad
    modelos/    las 15 tablas en SQLAlchemy
    esquemas/   lo que entra y sale de la API
    servicios/  reglas de negocio
    rutas/      endpoints, uno por módulo
    gestion/    comandos de mantenimiento
  migraciones/ cambios de esquema con Alembic
  pruebas/      pruebas con pytest
panel/          panel de administración en Flutter Web (ver panel/README.md)
app/            aplicativo móvil del consumidor en Flutter (ver app/README.md)
```

## Poner en marcha el backend

Requisitos: Python 3.13 y PostgreSQL 16 o superior con la base `transparencia_precios`
ya creada.

Desde la carpeta `backend`, en Git Bash. En bash las rutas van con `/`, no con `\`.

```bash
# 1. Entorno virtual (una sola vez)
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements-dev.txt

# 2. Credenciales (una sola vez): copiar y completar la contraseña
cp .env.example .env

# 3. Levantar la API
.venv/Scripts/python.exe -m uvicorn app.main:app --reload
```

Con la API levantada:

- <http://localhost:8000/salud> — comprueba que el servicio responde
- <http://localhost:8000/docs> — documentación interactiva de los endpoints

## Base de datos

El esquema completo está en `base_datos/crear_base_datos.sql`. Los cambios posteriores se
hacen con Alembic **y además** se copian a ese script, para que siga describiendo la base
entera.

Alembic cambia la estructura, así que entra con el rol `postgres` y no con el de la API.
La clave se escribe en la terminal y no se guarda en ningún archivo:

```bash
read -s -p "Clave de postgres: " MIG_PGPASSWORD && export MIG_PGPASSWORD
python -m alembic upgrade head     # base existente: aplica lo que falte
python -m alembic stamp head       # base recién creada con el .sql: solo la marca
unset MIG_PGPASSWORD
```

## Pruebas

```bash
.venv/Scripts/python.exe -m pytest
```

Las pruebas incluyen una comparación contra `openapi.yaml`: la API no puede exponer
nada que el contrato no declare, y sus respuestas reales deben validar contra los
esquemas del contrato.

## Cobertura

El Documento de Arquitectura exige al menos 70 % de cobertura. Se mide por líneas y por
ramas, y las pruebas fallan si se baja de ese mínimo (`backend/.coveragerc`):

```bash
python -m pytest --cov --cov-report=term-missing --cov-report=html
```

El informe navegable queda en `backend/htmlcov/index.html`.
