# transparencia-precios

Código del aplicativo móvil para mejorar la transparencia de precios en mercados
minoristas de Lima Metropolitana, mediante predicción con Machine Learning y cálculo
del costo total de compra.

Tesis de Renzo Alexander Munayco Vivanco — Ingeniería de Software, UNMSM.

## Estructura

```
backend/        API REST en Python con FastAPI
  app/
    core/       configuración, conexión a la base, seguridad
    modelos/    las 15 tablas en SQLAlchemy
    esquemas/   lo que entra y sale de la API
    servicios/  reglas de negocio
    rutas/      endpoints, uno por módulo
  pruebas/      pruebas con pytest
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

## Pruebas

```bash
.venv/Scripts/python.exe -m pytest
```
