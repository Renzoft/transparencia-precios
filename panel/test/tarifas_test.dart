// Pruebas de A9 · Tarifas de desplazamiento (CU02, pasos 10 a 13 y EX4). La API se
// simula con respuestas en el formato del contrato y se revisa lo que el panel le envía.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:panel_admin/api.dart';
import 'package:panel_admin/pantallas/mercados.dart';
import 'package:panel_admin/pantallas/tarifas.dart';
import 'package:panel_admin/tema.dart';

http.Response json(Object cuerpo, int estado) => http.Response.bytes(
  utf8.encode(jsonEncode(cuerpo)),
  estado,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final hoy = DateTime(2026, 10, 14);

Map<String, dynamic> tarifa(
  int id,
  int modo,
  String tipo,
  num monto,
  String desde, [
  String? hasta,
]) => {
  'id_tarifa': id,
  'id_modo_desplazamiento': modo,
  'tipo_cobro': tipo,
  'monto': monto,
  'vigente_desde': desde,
  'vigente_hasta': hasta,
};

class ApiFalsa {
  ApiFalsa({String desdePasaje = '2026-10-01'}) {
    tarifas.addAll([
      tarifa(1, 1, 'fijo', 0, '2026-10-13'),
      tarifa(2, 2, 'fijo', 2.5, desdePasaje),
    ]);
  }

  final peticiones = <http.Request>[];
  final tarifas = <Map<String, dynamic>>[];

  /// Si se indica, el POST de ese modo responde 409.
  int? modoQueChoca;

  List<Map> get registradas => [
    for (final r in peticiones)
      if (r.method == 'POST') jsonDecode(r.body) as Map,
  ];

  late final cliente = MockClient((r) async {
    peticiones.add(r);
    final ruta = '${r.method} ${r.url.path}';
    switch (ruta) {
      case 'GET /api/v1/mercados':
        return json([], 200);
      case 'GET /api/v1/modos-desplazamiento':
        return json([
          for (final (id, nombre) in [
            (1, 'a pie'),
            (2, 'transporte público'),
            (3, 'taxi'),
            (4, 'auto particular'),
          ])
            {'id_modo_desplazamiento': id, 'nombre': nombre, 'activo': true},
        ], 200);
      case 'GET /api/v1/tarifas':
        return json(tarifas, 200);
      case 'POST /api/v1/tarifas':
        final d = jsonDecode(r.body) as Map;
        if (d['id_modo_desplazamiento'] == modoQueChoca) {
          return json({
            'error': {
              'codigo': 'TARIFA_SOLAPADA',
              'mensaje': 'Ya existe una tarifa vigente para ese modo en esa fecha.',
            },
          }, 409);
        }
        final nueva = tarifa(
          100 + tarifas.length,
          d['id_modo_desplazamiento'] as int,
          d['tipo_cobro'] as String,
          d['monto'] as num,
          d['vigente_desde'] as String,
        );
        tarifas.add(nueva);
        return json({...nueva, 'tarifa_cerrada': null}, 201);
    }
    return json({
      'error': {'codigo': 'RECURSO_NO_ENCONTRADO', 'mensaje': 'No existe'},
    }, 404);
  });
}

/// Abre «Mercados y tarifas» y pasa a la pestaña de tarifas.
Future<void> abrir(WidgetTester t, ApiFalsa f) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: temaPanel(),
      home: PantallaMercados(api: ClienteApi(cliente: f.cliente)),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('Tarifas'));
  await t.pumpAndSettle();
}

Finder campoDe(String modo) => find.descendant(
  of: find.ancestor(of: find.text(modo), matching: find.byType(Row)).first,
  matching: find.byType(TextField),
);

Future<void> guardar(WidgetTester t) async {
  await t.tap(find.text('Guardar tarifas'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => usarInter = false);

  test('montos válidos: hasta dos decimales, coma o punto, no negativos', () {
    expect(leerMonto('2.50'), 2.5);
    expect(leerMonto(' 3,8 '), 3.8);
    expect(leerMonto('0'), 0);
    for (final malo in ['-1', 'abc', '2.505', '', '1e3', '2.']) {
      expect(leerMonto(malo), isNull, reason: malo);
    }
  });

  test('hoy en Lima es UTC menos cinco horas', () {
    final t = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    expect(hoyEnLima(), DateTime(t.year, t.month, t.day));
  });

  testWidgets('muestra las tarifas vigentes; a pie no se edita', (t) async {
    final f = ApiFalsa();
    // La vista usa la fecha real; aquí basta con que las tarifas falsas sean pasadas.
    await abrir(t, f);
    expect(
      find.text(
        'Las tarifas se aplican de ida y vuelta al calcular el costo de '
        'desplazamiento.',
      ),
      findsOneWidget,
    );
    expect(find.text('S/ 0.00'), findsOneWidget); // a pie, fijo
    expect(find.text('Sin costo'), findsOneWidget);
    expect(find.text('Pasaje fijo · desde 01/10/2026'), findsOneWidget);
    expect(find.text('Por kilómetro'), findsNWidgets(2)); // sin tarifa aún
    expect(find.byType(TextField), findsNWidgets(3));
    expect(t.widget<TextField>(campoDe('Transporte público')).controller!.text, '2.50');
    expect(t.widget<TextField>(campoDe('Taxi')).controller!.text, '');
  });

  group('con la fecha fija del 14/10/2026', () {
    Future<void> abrirEnFecha(WidgetTester t, ApiFalsa f) async {
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final guardando = ValueNotifier(false);
      final clave = GlobalKey<EstadoVistaTarifas>();
      await t.pumpWidget(
        MaterialApp(
          theme: temaPanel(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  VistaTarifas(
                    key: clave,
                    api: ClienteApi(cliente: f.cliente),
                    guardando: guardando,
                    hoy: () => hoy,
                  ),
                  TextButton(
                    onPressed: () => clave.currentState!.guardar(),
                    child: const Text('Guardar tarifas'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('EX4: montos no válidos no guardan nada y se señalan', (t) async {
      final f = ApiFalsa();
      await abrirEnFecha(t, f);
      await t.enterText(campoDe('Taxi'), '3.80');
      await t.enterText(campoDe('Auto particular'), '-1');
      await t.enterText(campoDe('Transporte público'), 'dos soles');
      await guardar(t);
      expect(find.text('Ingrese montos válidos'), findsOneWidget);
      expect(find.text('• Transporte público'), findsOneWidget);
      expect(find.text('• Auto particular'), findsOneWidget);
      expect(find.text('• Taxi'), findsNothing);
      expect(f.registradas, isEmpty); // ni el taxi
    });

    testWidgets('EX4: vaciar una tarifa que ya existe tampoco vale', (t) async {
      final f = ApiFalsa();
      await abrirEnFecha(t, f);
      await t.enterText(campoDe('Transporte público'), '');
      await guardar(t);
      expect(find.text('Ingrese montos válidos'), findsOneWidget);
      expect(f.registradas, isEmpty);
    });

    testWidgets('guarda solo las que cambiaron, con su tipo de cobro y desde hoy', (
      t,
    ) async {
      final f = ApiFalsa();
      await abrirEnFecha(t, f);
      await t.enterText(campoDe('Taxi'), '3,80');
      await t.enterText(campoDe('Auto particular'), '1.2');
      await guardar(t);
      expect(f.registradas, [
        {
          'id_modo_desplazamiento': 3,
          'tipo_cobro': 'por_km',
          'monto': 3.8,
          'vigente_desde': '2026-10-14',
        },
        {
          'id_modo_desplazamiento': 4,
          'tipo_cobro': 'por_km',
          'monto': 1.2,
          'vigente_desde': '2026-10-14',
        },
      ]);
      expect(find.text('Tarifas actualizadas'), findsOneWidget);
      expect(find.text('Por kilómetro · desde 14/10/2026'), findsNWidgets(2)); // recargó
    });

    testWidgets('sin cambios no envía nada', (t) async {
      final f = ApiFalsa();
      await abrirEnFecha(t, f);
      await t.enterText(campoDe('Transporte público'), '2.5'); // mismo monto
      await guardar(t);
      expect(find.text('No cambiaste ninguna tarifa.'), findsOneWidget);
      expect(f.registradas, isEmpty);
    });

    testWidgets('una tarifa que ya se cambió hoy no se vuelve a cambiar, y no se guarda '
        'ninguna', (t) async {
      final f = ApiFalsa(desdePasaje: '2026-10-14');
      await abrirEnFecha(t, f);
      await t.enterText(campoDe('Taxi'), '3.80');
      await t.enterText(campoDe('Transporte público'), '3.00');
      await guardar(t);
      expect(find.text('No se guardó ningún cambio.'), findsOneWidget);
      expect(
        find.text(
          '• Transporte público: su tarifa ya se cambió hoy; podrás cambiarla '
          'de nuevo mañana',
        ),
        findsOneWidget,
      );
      expect(f.registradas, isEmpty);
    });

    testWidgets('si la API rechaza una a mitad de camino, dice cuáles sí se guardaron', (
      t,
    ) async {
      final f = ApiFalsa()..modoQueChoca = 4;
      await abrirEnFecha(t, f);
      await t.enterText(campoDe('Taxi'), '3.80');
      await t.enterText(campoDe('Auto particular'), '1.20');
      await guardar(t);
      expect(
        find.text('Ya existe una tarifa vigente para ese modo en esa fecha.'),
        findsOneWidget,
      );
      expect(find.text('• Sí se guardaron: Taxi'), findsOneWidget);
    });
  });
}
