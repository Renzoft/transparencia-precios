// Panel de administración del aplicativo de transparencia de precios (Flutter Web).
//
// Se ejecuta desde la carpeta panel/ con:
//   flutter run -d chrome --web-port 5000
// La API se busca en http://localhost:8000; para otra dirección:
//   flutter run -d chrome --dart-define=API_URL=https://...

import 'package:flutter/material.dart';

import 'api.dart';
import 'pantallas/inicio_sesion.dart';
import 'tema.dart';

void main() => runApp(PanelAdministracion(api: ClienteApi()));

class PanelAdministracion extends StatelessWidget {
  const PanelAdministracion({super.key, required this.api});
  final ClienteApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transparencia de precios · Administración',
      debugShowCheckedModeBanner: false,
      theme: temaPanel(),
      home: PantallaInicioSesion(api: api),
    );
  }
}
