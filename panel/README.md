# Panel de administración

Aplicación Flutter Web para el administrador (Documento de Arquitectura, AD04). Por ahora
cubre el CU01: iniciar sesión y cargar los precios del SISAP.

| Pantalla del prototipo | Archivo |
|---|---|
| A1 Iniciar sesión · A2 Credenciales no válidas | `lib/pantallas/inicio_sesion.dart` |
| A3 Menú de administración | `lib/pantallas/menu.dart` |
| A4 Carga de precios | `lib/pantallas/carga_precios.dart` |
| A5 Resumen de la carga | `lib/pantallas/resumen_carga.dart` |

Colores, tipografía y radios salen de las variables de los prototipos en Figma
(`lib/tema.dart`).

## Ejecutar

Primero la API, desde `backend/`:

```bash
python -m uvicorn app.main:app --reload
```

Después el panel, desde `panel/`:

```bash
flutter run -d chrome --web-port 5000
```

Para apuntar a otra API: `--dart-define=API_URL=https://...`

## Pruebas

```bash
flutter test
```

Simulan la API con respuestas en el formato del contrato `openapi.yaml`, así que no
necesitan el backend encendido.
