# Aplicativo móvil del consumidor

Aplicación Flutter para Android (Documento de Arquitectura, AD04). El consumidor la usa
sin registrarse. Por ahora cubre el inicio del CU05: armar la lista de compras.

| Pantalla del prototipo | Archivo |
|---|---|
| C6 Mi lista de compras — vacía · C7 Mi lista de compras | `lib/pantallas/mi_lista.dart` |
| Agregar un producto (no está en el prototipo; usa piezas de C1 y C2) | `lib/pantallas/agregar_producto.dart` |
| cmp/Nav inferior | `lib/pantallas/inicio.dart` |

La lista se guarda en el teléfono (`lib/lista.dart`), no en el servidor. Colores,
tipografía y radios salen de las mismas variables de Figma que el panel (`lib/tema.dart`).

## Ejecutar

Primero la API, desde `backend/`:

```bash
python -m uvicorn app.main:app --reload
```

Después el emulador y la aplicación, desde `app/`:

```bash
flutter emulators --launch Pixel_5_API_34
```

```bash
flutter run
```

Desde el emulador, la API local se busca en `http://10.0.2.2:8000`: así ve el emulador a
la computadora. Para otra dirección: `--dart-define=API_URL=https://...`

## Pruebas

```bash
flutter test
```

Simulan la API con respuestas en el formato del contrato `openapi.yaml`, así que no
necesitan el backend encendido.
