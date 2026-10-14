// Pruebas de C8 · Punto de partida y modo (CU05, pasos 6 a 8 y EX2). El GPS se simula
// con una función que devuelve la ubicación o la falla que se quiere probar.

import 'dart:async';
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

Map<String, dynamic> modo(int id, String nombre, [String? tipo, num? monto]) => {
  'id_modo_desplazamiento': id,
  'nombre': nombre,
  'activo': true,
  'tarifa': tipo == null ? null : {'tipo_cobro': tipo, 'monto': monto},
};

final api = ClienteApi(
  cliente: MockClient(
    (r) async => json([
      modo(1, 'a pie', 'fijo', 0),
      modo(2, 'transporte público', 'fijo', 2.5),
      modo(3, 'taxi', 'por_km', 1.14),
      modo(4, 'auto particular'), // sin tarifa todavía
    ], 200),
  ),
);

const enLima = ResultadoUbicacion.ok(Punto(-12.095, -77.065));

Future<List<Partida>> abrir(WidgetTester t, {ObtenerUbicacion? ubicacion}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final pedidos = <Partida>[];
  await t.pumpWidget(
    MaterialApp(
      theme: temaApp(),
      home: PantallaPuntoDePartida(
        api: api,
        obtenerUbicacion: ubicacion ?? () async => enLima,
        alCalcular: (_, p) => pedidos.add(p),
      ),
    ),
  );
  // Sin pumpAndSettle: mientras se busca la ubicación hay un indicador girando.
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return pedidos;
}

bool calcularActivo(WidgetTester t) =>
    t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Calcular')).onPressed !=
    null;

void main() {
  setUp(() => usarInter = false);

  test('cómo se describe cada tarifa, como en el prototipo', () {
    expect(
      describirTarifa(ModoDesplazamiento(1, 'a pie', tipoCobro: 'fijo', monto: 0)),
      'Sin costo',
    );
    expect(
      describirTarifa(
        ModoDesplazamiento(2, 'transporte público', tipoCobro: 'fijo', monto: 2.5),
      ),
      'S/ 2.50',
    );
    expect(
      describirTarifa(ModoDesplazamiento(3, 'taxi', tipoCobro: 'por_km', monto: 1.14)),
      'S/ 1.14 por km',
    );
  });

  testWidgets('con la ubicación y un modo elegido, «Calcular» envía la partida', (
    t,
  ) async {
    final pedidos = await abrir(t);
    expect(find.text('Tu ubicación actual'), findsOneWidget);
    expect(find.text('-12.09500, -77.06500'), findsOneWidget);
    expect(
      find.text(
        'Tu ubicación solo se usa para este cálculo y no se guarda en el servidor.',
      ),
      findsOneWidget,
    );
    expect(find.text('S/ 2.50'), findsOneWidget);
    expect(find.text('S/ 1.14 por km'), findsOneWidget);
    expect(calcularActivo(t), isFalse); // falta el modo

    await t.tap(find.text('Taxi'));
    await t.pump();
    expect(calcularActivo(t), isTrue);
    await t.tap(find.text('Calcular'));
    await t.pump();
    final p = pedidos.single;
    expect((p.origen.latitud, p.origen.longitud), (-12.095, -77.065));
    expect((p.modo.id, p.radioKm), (3, 3)); // radio por defecto (RN06)
  });

  testWidgets('el radio va de 1 a 20 km', (t) async {
    final pedidos = await abrir(t);
    expect(find.text('3 km'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await t.tap(find.byTooltip('Reducir radio'));
      await t.pump();
    }
    expect(find.text('1 km'), findsOneWidget); // no baja de 1
    for (var i = 0; i < 25; i++) {
      await t.tap(find.byTooltip('Ampliar radio'));
      await t.pump();
    }
    expect(find.text('20 km'), findsOneWidget); // ni sube de 20
    await t.tap(find.text('A pie'));
    await t.pump();
    await t.tap(find.text('Calcular'));
    await t.pump();
    expect(pedidos.single.radioKm, 20);
  });

  testWidgets('un modo sin tarifa no se puede elegir', (t) async {
    await abrir(t);
    expect(find.text('Sin tarifa disponible'), findsOneWidget);
    await t.tap(find.text('Auto particular'));
    await t.pump();
    expect(calcularActivo(t), isFalse);
  });

  testWidgets('mientras busca la ubicación lo dice y no deja calcular', (t) async {
    final gps = Completer<ResultadoUbicacion>();
    await abrir(t, ubicacion: () => gps.future);
    expect(find.text('Buscando tu ubicación…'), findsOneWidget);
    await t.tap(find.text('A pie'));
    await t.pump();
    expect(calcularActivo(t), isFalse);
    gps.complete(enLima);
    await t.pumpAndSettle();
    expect(calcularActivo(t), isTrue);
  });

  testWidgets('EX2: sin permiso lo explica y deja volver a intentar', (t) async {
    var intentos = 0;
    await abrir(
      t,
      ubicacion: () async {
        intentos++;
        return intentos == 1
            ? const ResultadoUbicacion.falla(FallaUbicacion.sinPermiso)
            : enLima;
      },
    );
    expect(find.text('No autorizaste el uso de tu ubicación'), findsOneWidget);
    expect(find.text('Ingresar una dirección'), findsOneWidget);
    await t.tap(find.text('A pie'));
    await t.pump();
    expect(calcularActivo(t), isFalse);
    await t.tap(find.text('Volver a intentar'));
    await t.pumpAndSettle();
    expect(find.text('Tu ubicación actual'), findsOneWidget);
    expect(calcularActivo(t), isTrue);
  });

  testWidgets('con el GPS apagado lo dice', (t) async {
    await abrir(
      t,
      ubicacion: () async => const ResultadoUbicacion.falla(FallaUbicacion.gpsApagado),
    );
    expect(find.text('La ubicación del teléfono está desactivada'), findsOneWidget);
  });
}
