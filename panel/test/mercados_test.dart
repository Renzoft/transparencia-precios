// Pruebas del panel del CU02 (A6, A7 y A8). La API se simula con respuestas que tienen el
// formato exacto del contrato, y se revisa además lo que el panel le envía.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:panel_admin/api.dart';
import 'package:panel_admin/componentes.dart';
import 'package:panel_admin/pantallas/menu.dart';
import 'package:panel_admin/pantallas/mercados.dart';
import 'package:panel_admin/tema.dart';

http.Response json(Object cuerpo, int estado) => http.Response.bytes(
  utf8.encode(jsonEncode(cuerpo)),
  estado,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> error(String codigo, String mensaje, [List<Map>? detalles]) => {
  'error': {'codigo': codigo, 'mensaje': mensaje, 'detalles': ?detalles},
};

Map<String, dynamic> mercado(
  int id,
  String nombre,
  String distrito, {
  bool activo = true,
}) => {
  'id_mercado': id,
  'nombre': nombre,
  'distrito': distrito,
  'direccion': 'Jr. Leoncio Prado 1200',
  'latitud': -12.0912,
  'longitud': -77.0712,
  'horario_atencion': '6:00 – 18:00',
  'activo': activo,
};

/// Una API falsa de /mercados que guarda las peticiones recibidas.
class ApiFalsa {
  final peticiones = <http.Request>[];

  /// Respuesta que dará el próximo POST /mercados; por defecto, 201.
  http.Response? respuestaRegistro;

  final mercados = [
    mercado(1, 'Mercado de Magdalena', 'Magdalena del Mar'),
    mercado(2, 'Mercado N.º 1 de Surquillo', 'Surquillo'),
    mercado(4, 'Mercado Santa Rosa', 'Lince', activo: false),
  ];

  Iterable<Map> cuerpos(String metodo) => peticiones
      .where((r) => r.method == metodo && r.url.path.startsWith('/api/v1/mercados'))
      .map((r) => jsonDecode(r.body) as Map);

  late final cliente = MockClient((r) async {
    peticiones.add(r);
    if (r.method == 'GET' && r.url.path == '/api/v1/cargas') return json([], 200);
    if (r.method == 'GET' && r.url.path == '/api/v1/mercados') return json(mercados, 200);
    if (r.method == 'POST' && r.url.path == '/api/v1/mercados') {
      return respuestaRegistro ??
          json({...mercado(9, 'nuevo', 'x'), ...jsonDecode(r.body) as Map}, 201);
    }
    if (r.method == 'PATCH' && r.url.path.startsWith('/api/v1/mercados/')) {
      final id = int.parse(r.url.pathSegments.last);
      final m = mercados.firstWhere((m) => m['id_mercado'] == id);
      m.addAll((jsonDecode(r.body) as Map).cast<String, Object?>());
      return json(m, 200);
    }
    return json(error('RECURSO_NO_ENCONTRADO', 'No existe'), 404);
  });

  ClienteApi get api => ClienteApi(cliente: cliente);
}

Future<void> abrir(WidgetTester t, ApiFalsa f) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: temaPanel(),
      home: PantallaMercados(api: f.api),
    ),
  );
  await t.pumpAndSettle();
}

/// Escribe en el campo que está debajo del rótulo indicado.
Future<void> llenar(WidgetTester t, String rotulo, String texto) async {
  final campo = find.descendant(
    of: find.ancestor(of: find.text(rotulo), matching: find.byType(Column)).first,
    matching: find.byType(TextField),
  );
  await t.enterText(campo, texto);
}

Future<void> llenarTodo(WidgetTester t, {String latitud = '-12.0757'}) async {
  await llenar(t, 'Nombre del mercado', 'Mercado de Jesús María');
  await llenar(t, 'Distrito', 'Jesús María');
  await llenar(t, 'Dirección', 'Av. Brasil 1200');
  await llenar(t, 'Latitud', latitud);
  await llenar(t, 'Longitud', '-77.0476');
}

void main() {
  setUp(() => usarInter = false);

  test('buscar sin tildes ni mayúsculas', () {
    expect(sinTildes('Jesús María '), 'jesus maria');
    expect(sinTildes('PEÑA'), 'pena');
  });

  group('A6 · mercados registrados', () {
    testWidgets('lista todos, con su distrito y su estado', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      expect(f.peticiones.single.url.queryParameters['incluir_inactivos'], 'true');
      expect(find.text('Mercado de Magdalena'), findsOneWidget);
      expect(find.text('Lince'), findsOneWidget);
      expect(find.text('Activo'), findsNWidgets(2));
      expect(find.text('Inactivo'), findsOneWidget);
    });

    testWidgets('la búsqueda filtra por nombre o distrito, sin tildes', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.enterText(find.byType(TextField), 'surquíllo');
      await t.pump();
      expect(find.text('Mercado N.º 1 de Surquillo'), findsOneWidget);
      expect(find.text('Mercado de Magdalena'), findsNothing);
    });

    testWidgets('el menú abre la pantalla de mercados', (t) async {
      final f = ApiFalsa();
      await t.pumpWidget(
        MaterialApp(
          theme: temaPanel(),
          home: PantallaMenu(api: f.api),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Mercados y tarifas'));
      await t.pumpAndSettle();
      expect(find.text('Nuevo mercado'), findsOneWidget);
    });
  });

  group('A7 · nuevo mercado', () {
    testWidgets('campos vacíos: EX1 nombra los que faltan y no llama a la API', (
      t,
    ) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Nuevo mercado'));
      await t.pumpAndSettle();
      await llenar(t, 'Nombre del mercado', 'Mercado de Jesús María');
      await t.tap(find.text('Guardar'));
      await t.pump();
      expect(find.text('Complete los campos obligatorios'), findsOneWidget);
      expect(find.text('• Distrito'), findsOneWidget);
      expect(find.text('• Longitud'), findsOneWidget);
      expect(find.text('• Horario de atención'), findsNothing); // es opcional
      expect(f.cuerpos('POST'), isEmpty);
    });

    testWidgets('una coordenada que no es número no llega a la API (EX2)', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Nuevo mercado'));
      await t.pumpAndSettle();
      await llenarTodo(t, latitud: '-12.07.57');
      await t.tap(find.text('Guardar'));
      await t.pump();
      expect(
        find.textContaining('Las coordenadas no corresponden a Lima Metropolitana'),
        findsOneWidget,
      );
      expect(f.cuerpos('POST'), isEmpty);
    });

    testWidgets(
      'coordenadas fuera de Lima: el mensaje de la EX2 y lo que encontró la API',
      (t) async {
        final f = ApiFalsa()
          ..respuestaRegistro = json(
            error(
              'COORDENADAS_FUERA_DE_LIMA',
              'Las coordenadas no corresponden a Lima Metropolitana',
              [
                {
                  'campo': 'latitud',
                  'problema': 'parece estar intercambiada con la longitud',
                },
              ],
            ),
            422,
          );
        await abrir(t, f);
        await t.tap(find.text('Nuevo mercado'));
        await t.pumpAndSettle();
        await llenarTodo(t);
        await t.tap(find.text('Guardar'));
        await t.pumpAndSettle();
        expect(
          find.text(
            'Las coordenadas no corresponden a Lima Metropolitana. La latitud '
            'parece estar intercambiada con la longitud',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('mercado repetido: el mensaje de la EX3', (t) async {
      final f = ApiFalsa()
        ..respuestaRegistro = json(
          error('MERCADO_YA_REGISTRADO', 'El mercado ya se encuentra registrado', [
            {
              'campo': 'nombre',
              'problema':
                  'ya existe «Mercado de Magdalena» en Magdalena del Mar '
                  '(mercado 1, activo)',
            },
          ]),
          409,
        );
      await abrir(t, f);
      await t.tap(find.text('Nuevo mercado'));
      await t.pumpAndSettle();
      await llenarTodo(t);
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.text('El mercado ya se encuentra registrado'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget); // sigue en A7
    });

    testWidgets('registrar: envía los datos, vuelve a la lista y lo confirma', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Nuevo mercado'));
      await t.pumpAndSettle();
      await llenarTodo(t, latitud: '-12,0757'); // coma decimal
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(f.cuerpos('POST').single, {
        'nombre': 'Mercado de Jesús María',
        'distrito': 'Jesús María',
        'direccion': 'Av. Brasil 1200',
        'latitud': -12.0757,
        'longitud': -77.0476,
      });
      expect(find.text('Mercado registrado'), findsOneWidget);
      expect(f.peticiones.where((r) => r.method == 'GET'), hasLength(2)); // recargó
    });

    testWidgets('cancelar no guarda nada', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Nuevo mercado'));
      await t.pumpAndSettle();
      await llenarTodo(t);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(f.cuerpos('POST'), isEmpty);
      expect(find.text('Mercado de Magdalena'), findsOneWidget);
    });
  });

  group('FA1 · editar y FA2 · desactivar (A8)', () {
    testWidgets('editar envía solo lo que cambió', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Mercado de Magdalena'));
      await t.pumpAndSettle();
      await t.tap(find.text('Editar'));
      await t.pumpAndSettle();
      expect(find.text('Editar mercado'), findsOneWidget);
      final valores = t
          .widgetList<TextField>(find.byType(TextField))
          .map((c) => c.controller!.text);
      expect(
        valores,
        containsAll(['Mercado de Magdalena', '-12.091200', '6:00 – 18:00']),
      );
      await llenar(t, 'Dirección', 'Av. Brasil 2500');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(f.cuerpos('PATCH').single, {'direccion': 'Av. Brasil 2500'});
      expect(find.text('Mercado actualizado'), findsOneWidget);
    });

    testWidgets('borrar el horario lo envía como nulo', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Mercado de Magdalena'));
      await t.pumpAndSettle();
      await t.tap(find.text('Editar'));
      await t.pumpAndSettle();
      await llenar(t, 'Horario de atención', '  ');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(f.cuerpos('PATCH').single, {'horario_atencion': null});
    });

    testWidgets('desactivar pide confirmación; cancelar no cambia nada', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Mercado de Magdalena'));
      await t.pumpAndSettle();
      await t.tap(find.text('Desactivar'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'El Mercado de Magdalena dejará de mostrarse al consumidor. Sus '
          'precios históricos se conservan.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(f.cuerpos('PATCH'), isEmpty);

      await t.tap(find.text('Mercado de Magdalena'));
      await t.pumpAndSettle();
      await t.tap(find.text('Desactivar'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Desactivar'));
      await t.pumpAndSettle();
      expect(f.cuerpos('PATCH').single, {'activo': false});
      expect(find.text('Mercado desactivado'), findsOneWidget);
      expect(find.text('Inactivo'), findsNWidgets(2));
    });

    testWidgets('un mercado inactivo no ofrece desactivar', (t) async {
      final f = ApiFalsa();
      await abrir(t, f);
      await t.tap(find.text('Mercado Santa Rosa'));
      await t.pumpAndSettle();
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Desactivar'), findsNothing);
    });
  });
}
