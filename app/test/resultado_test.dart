// Pruebas de C9 · Calculando y C10 · Resultado por mercado (CU05, pasos 9 a 13; EX3,
// EX4). La API se simula con respuestas en el formato del contrato.

import 'dart:async';
import 'dart:convert';

import 'package:app_consumidor/api.dart';
import 'package:app_consumidor/lista.dart';
import 'package:app_consumidor/pantallas/punto_de_partida.dart';
import 'package:app_consumidor/pantallas/resultado.dart';
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

Map<String, dynamic> mercado(
  int id,
  String nombre,
  double productos,
  double viaje, {
  List<int> sinPrecio = const [],
  int? minutos,
}) => {
  'id_mercado': id,
  'nombre': nombre,
  'distrito': 'Magdalena del Mar',
  'distancia_km': 0.8,
  'duracion_min': ?minutos,
  'costo_productos': productos,
  'costo_desplazamiento': viaje,
  'costo_total': productos + viaje,
  'sin_precio': sinPrecio,
};

Map<String, dynamic> respuesta(List<Map> mercados, {bool aproximada = true}) => {
  'generado_en': '2026-10-14T20:00:00Z',
  'distancia_aproximada': aproximada,
  'mercados': mercados,
  'recomendacion': {
    'disponible': false,
    'motivo': 'La recomendación de cuándo comprar todavía no está disponible.',
    'productos_sin_tendencia': 2,
  },
};

final items = [
  ItemLista(
    idVariedad: 1,
    nombre: 'Papa amarilla',
    unidad: 'kilogramo',
    factorAKg: 1,
    cantidad: 2,
  ),
  ItemLista(
    idVariedad: 9,
    nombre: 'Aceite',
    unidad: 'litro',
    factorAKg: 0.92,
    cantidad: 1,
  ),
];

final partida = Partida(
  const Punto(-12.095, -77.065),
  ModoDesplazamiento(3, 'taxi', tipoCobro: 'por_km', monto: 1.14),
  3,
);

Future<List<http.Request>> abrir(
  WidgetTester t,
  FutureOr<http.Response> Function() responder, {
  bool esperar = true,
}) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final peticiones = <http.Request>[];
  final api = ClienteApi(
    cliente: MockClient((r) async {
      peticiones.add(r);
      return responder();
    }),
  );
  await t.pumpWidget(
    MaterialApp(
      theme: temaApp(),
      home: PantallaResultado(api: api, items: items, partida: partida),
    ),
  );
  if (esperar) await t.pumpAndSettle();
  return peticiones;
}

void main() {
  setUp(() => usarInter = false);

  testWidgets('envía la partida y la lista en kg, como pide el contrato', (t) async {
    final peticiones = await abrir(t, () => json(respuesta([]), 201));
    expect(jsonDecode(peticiones.single.body), {
      'origen': {'latitud': -12.095, 'longitud': -77.065},
      'id_modo_desplazamiento': 3,
      'radio_km': 3,
      'items': [
        {'id_variedad': 1, 'cantidad_kg': 2.0},
        {'id_variedad': 9, 'cantidad_kg': 0.92}, // 1 litro × 0.92 (RN10)
      ],
    });
  });

  testWidgets('C9: mientras calcula lo dice', (t) async {
    final respuestaApi = Completer<http.Response>();
    await abrir(t, () => respuestaApi.future, esperar: false);
    await t.pump();
    expect(find.text('Calculando tu costo total'), findsOneWidget);
    respuestaApi.complete(json(respuesta([]), 201));
    await t.pumpAndSettle();
    expect(find.text('Calculando tu costo total'), findsNothing);
  });

  testWidgets('C10: el desglose de cada mercado y el más barato', (t) async {
    await abrir(
      t,
      () => json(
        respuesta([
          mercado(1, 'Mercado Ciudad de Dios', 41.20, 5.00, minutos: 12),
          mercado(2, 'Mercado de Magdalena', 43.10, 5.00),
        ], aproximada: false),
        201,
      ),
    );
    expect(find.text('2 productos · 2 mercados en 3 km'), findsOneWidget);
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Más barato'), findsOneWidget);
    expect(find.text('S/ 46.20'), findsOneWidget);
    expect(find.text('el más barato'), findsOneWidget);
    expect(find.text('Magdalena del Mar · 0.8 km · 12 min'), findsOneWidget);
    expect(find.text('Productos  S/ 41.20'), findsOneWidget);
    expect(find.text('Desplazamiento  S/ 5.00'), findsNWidgets(2));
    expect(find.text('+ S/ 1.90'), findsOneWidget); // 48.10 − 46.20
    expect(find.textContaining('aproximadas'), findsNothing);
  });

  testWidgets('EX4: avisa que la distancia es aproximada y omite el tiempo', (t) async {
    await abrir(
      t,
      () => json(respuesta([mercado(1, 'Mercado de Magdalena', 0, 1.81)]), 201),
    );
    expect(find.text('Las distancias son aproximadas, en línea recta.'), findsOneWidget);
    expect(find.text('Magdalena del Mar · 0.8 km'), findsOneWidget);
  });

  testWidgets('sin precios: no hay «más barato» y dice qué productos faltan', (t) async {
    await abrir(
      t,
      () => json(
        respuesta([
          mercado(1, 'Mercado de Magdalena', 0, 1.81, sinPrecio: [1, 9]),
          mercado(2, 'Mercado de Lince', 0, 3.00, sinPrecio: [1, 9]),
        ]),
        201,
      ),
    );
    expect(find.text('Más barato'), findsNothing);
    expect(find.textContaining('+ S/'), findsNothing);
    expect(
      find.text('Sin precio en este mercado: Papa amarilla, Aceite'),
      findsNWidgets(2),
    );
    expect(find.text('Desplazamiento  S/ 1.81'), findsOneWidget);
  });

  testWidgets('EX3: sin mercados en el radio, sugiere ampliarlo', (t) async {
    await abrir(t, () => json(respuesta([]), 201));
    expect(find.text('No se encontraron mercados cercanos'), findsOneWidget);
    expect(find.text('Ampliar el radio'), findsOneWidget);
  });

  testWidgets('si la API falla, lo dice y deja volver a intentar', (t) async {
    var veces = 0;
    await abrir(t, () {
      veces++;
      return veces == 1
          ? json({
              'error': {
                'codigo': 'TARIFA_NO_CONFIGURADA',
                'mensaje':
                    'El modo de desplazamiento elegido todavía no tiene una tarifa.',
              },
            }, 422)
          : json(respuesta([mercado(1, 'Mercado de Magdalena', 0, 1.81)]), 201);
    });
    expect(
      find.text('El modo de desplazamiento elegido todavía no tiene una tarifa.'),
      findsOneWidget,
    );
    await t.tap(find.text('Volver a intentar'));
    await t.pumpAndSettle();
    expect(find.text('Mercado de Magdalena'), findsOneWidget);
  });
}
