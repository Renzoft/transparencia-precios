// Aplicativo móvil del consumidor (Flutter): transparencia de precios en los mercados
// minoristas de Lima Metropolitana.
//
// Se ejecuta desde la carpeta app/ con la API encendida:
//   flutter emulators --launch Pixel_5_API_34
//   flutter run
// Desde el emulador, la API local se busca en http://10.0.2.2:8000 (ver lib/api.dart).

import 'package:flutter/material.dart';

import 'api.dart';
import 'lista.dart';
import 'pantallas/inicio.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final lista = ListaCompras();
  await lista.cargar();
  runApp(AppConsumidor(api: ClienteApi(), lista: lista));
}

class AppConsumidor extends StatelessWidget {
  const AppConsumidor({super.key, required this.api, required this.lista});

  final ClienteApi api;
  final ListaCompras lista;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transparencia de precios',
      debugShowCheckedModeBanner: false,
      theme: temaApp(),
      home: PantallaInicio(api: api, lista: lista),
    );
  }
}
