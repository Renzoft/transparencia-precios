// Pruebas de la dirección de partida escrita (CU05, EX2; R12): buscarla, elegirla y
// calcular desde ella en lugar de desde el GPS.

import 'dart:convert';

import 'package:app_consumidor/api.dart';
import 'package:app_consumidor/pantallas/punto_de_partida.dart';
import 'package:app_consumidor/tema.dart';
import 'package:app_consumidor/ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object cuerpo, int estado) => http.Response.bytes(
  utf8.encode(jsonEncode(cuerpo)),
  estado,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class ApiFalsa {
  final peticiones = <http.Request>[];
  http.Response Function()? direcciones;

  late final api = ClienteApi(
    cliente: MockClient((r) async {
      peticiones.add(r);
      if (r.url.path == '/api/v1/direcciones') {
        return direcciones?.call() ??
            json([
              {
                'etiqueta': 'Avenida Brasil 1240, Jesús María, Lima',
                'latitud': -12.0757,
                'longitud': -77.0476,
              },
            ], 200);
      }
      return json([
        {
          'id_modo_desplazamiento': 1,
          'nombre': 'a pie',
          'activo': true,
          'tarifa': {'tipo_cobro': 'fijo', 'monto': 0},
        },
      ], 200);
    }),
  );
}

Future<List<Partida>> abrir(WidgetTester t, ApiFalsa f, ResultadoUbicacion gps) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidos = <Partida>[];
  await t.pumpWidget(
    MaterialApp(
      theme: temaApp(),
      home: PantallaPuntoDePartida(
        api: f.api,
        obtenerUbicacion: () async => gps,
        alCalcular: (_, p) => pedidos.add(p),
      ),
    ),
  );
  await t.pumpAndSettle();
  return pedidos;
}

const sinPermiso = ResultadoUbicacion.falla(FallaUbicacion.sinPermiso);

Future<void> buscarYElegir(WidgetTester t, String enlace) async {
  await t.tap(find.text(enlace));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField), 'Av. Brasil 1240, Jesús María');
  await t.tap(find.text('Buscar'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => usarInter = false);

  testWidgets('EX2: sin GPS, se calcula desde la dirección escrita', (t) async {
    final f = ApiFalsa();
    final pedidos = await abrir(t, f, sinPermiso);
    await buscarYElegir(t, 'Ingresar una dirección');

    final busqueda = f.peticiones.last;
    expect(busqueda.method, 'POST');                         // no va en la URL (RNF003)
    expect(busqueda.url.query, isEmpty);
    expect(jsonDecode(busqueda.body), {'texto': 'Av. Brasil 1240, Jesús María'});

    await t.tap(find.text('Avenida Brasil 1240, Jesús María, Lima'));
    await t.pumpAndSettle();
    expect(find.text('Avenida Brasil 1240, Jesús María, Lima'), findsOneWidget); // en C8
    expect(find.text('No autorizaste el uso de tu ubicación'), findsNothing);

    await t.tap(find.text('A pie'));
    await t.pump();
    await t.tap(find.text('Calcular'));
    await t.pump();
    final o = pedidos.single.origen;
    expect((o.latitud, o.longitud), (-12.0757, -77.0476));
  });

  testWidgets('con GPS, «Usar otra dirección» la reemplaza y se puede volver al GPS', (
    t,
  ) async {
    final f = ApiFalsa();
    final pedidos = await abrir(t, f, const ResultadoUbicacion.ok(Punto(-12.09, -77.07)));
    await buscarYElegir(t, 'Usar otra dirección');
    await t.tap(find.text('Avenida Brasil 1240, Jesús María, Lima'));
    await t.pumpAndSettle();
    await t.tap(find.text('Usar mi ubicación'));
    await t.pumpAndSettle();
    expect(find.text('Tu ubicación actual'), findsOneWidget);
    await t.tap(find.text('A pie'));
    await t.pump();
    await t.tap(find.text('Calcular'));
    await t.pump();
    expect(pedidos.single.origen.latitud, -12.09);
  });

  testWidgets('sin resultados sugiere agregar el distrito', (t) async {
    final f = ApiFalsa()..direcciones = () => json([], 200);
    await abrir(t, f, sinPermiso);
    await buscarYElegir(t, 'Ingresar una dirección');
    expect(find.textContaining('Prueba agregando el distrito'), findsOneWidget);
  });

  testWidgets('si el servicio no está disponible lo dice', (t) async {
    final f = ApiFalsa()
      ..direcciones = () => json({
        'error': {
          'codigo': 'SERVICIO_NO_DISPONIBLE',
          'mensaje': 'La búsqueda de direcciones no está disponible en este momento. '
              'Usa tu ubicación o inténtalo más tarde.',
        },
      }, 503);
    await abrir(t, f, sinPermiso);
    await buscarYElegir(t, 'Ingresar una dirección');
    expect(
      find.textContaining('La búsqueda de direcciones no está disponible'),
      findsOneWidget,
    );
  });

  testWidgets('un texto muy corto no llega a la API', (t) async {
    final f = ApiFalsa();
    await abrir(t, f, sinPermiso);
    await t.tap(find.text('Ingresar una dirección'));
    await t.pumpAndSettle();
    final antes = f.peticiones.length;
    await t.enterText(find.byType(TextField), 'av');
    await t.tap(find.text('Buscar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe la dirección con al menos 3 caracteres.'), findsOneWidget);
    expect(f.peticiones.length, antes);
  });
}
