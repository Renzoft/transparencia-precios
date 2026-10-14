// Pruebas del panel del CU01. La API se simula con respuestas que tienen el formato
// exacto del contrato (openapi.yaml), y se revisa además lo que el panel le envía.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:panel_admin/api.dart';
import 'package:panel_admin/componentes.dart';
import 'package:panel_admin/pantallas/carga_precios.dart';
import 'package:panel_admin/pantallas/inicio_sesion.dart';
import 'package:panel_admin/tema.dart';

http.Response json(Object cuerpo, int estado) => http.Response.bytes(
    utf8.encode(jsonEncode(cuerpo)), estado,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> error(String codigo, String mensaje, [List<Map>? detalles]) => {
      'error': {'codigo': codigo, 'mensaje': mensaje, 'detalles': ?detalles}
    };

/// Una API falsa que responde como la real y guarda las peticiones recibidas.
class ApiFalsa {
  final peticiones = <http.Request>[];
  bool listarResponde401 = false;
  int estadoSubida = 201;

  late final cliente = MockClient((r) async {
    peticiones.add(r);
    final ruta = '${r.method} ${r.url.path}';
    switch (ruta) {
      case 'POST /api/v1/sesiones':
        final datos = jsonDecode(r.body) as Map;
        if (datos['contrasena'] != 'clave-correcta') {
          return json(error('CREDENCIALES_INVALIDAS', 'Usuario o contraseña incorrectos'), 401);
        }
        return json({
          'token': 'token-de-prueba',
          'tipo': 'Bearer',
          'expira_en': '2026-10-14T20:00:00Z',
          'usuario': {'nombre': 'Renzo Munayco', 'rol': 'administrador'},
        }, 201);
      case 'GET /api/v1/cargas':
        if (listarResponde401) {
          return json(error('NO_AUTENTICADO', 'La sesión no es válida o expiró.'), 401);
        }
        return json([
          {
            'id_carga_archivo': 3,
            'estado': 'confirmada',
            'nombre_archivo': 'historico.csv',
            'fuente': 'SISAP minorista',
            'periodo': {'desde': '2019-01-01', 'hasta': '2026-09-30'},
            'registros_validos': 1842,
            'registros_rechazados': 0,
            'rechazos': [],
          }
        ], 200);
      case 'POST /api/v1/cargas':
        if (estadoSubida == 400) {
          return json(
              error('FORMATO_NO_VALIDO', 'El archivo no corresponde al formato esperado', [
                {'campo': 'archivo', 'problema': 'el archivo es de la región «Arequipa»'}
              ]),
              400);
        }
        return json({
          'id_carga_archivo': 7,
          'estado': 'pendiente',
          'nombre_archivo': 'reporte.xls',
          'fuente': 'SISAP minorista',
          'periodo': {'desde': '2026-09-01', 'hasta': '2026-10-13'},
          'registros_validos': 18,
          'registros_rechazados': 43,
          'rechazos': [
            {'motivo': 'duplicado', 'cantidad': 43}
          ],
          'catalogo_nuevo': {'productos': [], 'variedades': ['Tomate marzano']},
        }, 201);
      case 'PATCH /api/v1/cargas/7':
        final estado = (jsonDecode(r.body) as Map)['estado'];
        return json({
          'id_carga_archivo': 7,
          'estado': estado,
          'precios_guardados': estado == 'confirmada' ? 18 : 0,
          'confirmada_en': '2026-10-14T12:00:00Z',
        }, 200);
    }
    return json(error('RECURSO_NO_ENCONTRADO', 'No existe'), 404);
  });
}

Widget app(Widget pantalla) => MaterialApp(theme: temaPanel(), home: pantalla);

Future<void> escribir(WidgetTester t, int indice, String texto) =>
    t.enterText(find.byType(TextField).at(indice), texto);

void main() {
  setUp(() => usarInter = false);

  group('formatos', () {
    test('miles con espacio, como en los prototipos', () {
      expect(conMiles(5), '5');
      expect(conMiles(1842), '1 842');
      expect(conMiles(1234567), '1 234 567');
    });
    test('fecha dd/mm/aaaa', () => expect(fecha(DateTime(2026, 9, 1)), '01/09/2026'));
  });

  group('A1 · A2 iniciar sesión', () {
    testWidgets('credenciales incorrectas muestran el mensaje de la EX1', (t) async {
      final f = ApiFalsa();
      await t.pumpWidget(app(PantallaInicioSesion(api: ClienteApi(cliente: f.cliente))));
      await escribir(t, 0, 'admin@unmsm.edu.pe');
      await escribir(t, 1, 'otra-clave');
      await t.tap(find.text('Ingresar'));
      await t.pumpAndSettle();
      expect(find.text('Usuario o contraseña incorrectos'), findsOneWidget);
    });

    testWidgets('campos vacíos no llegan a la API', (t) async {
      final f = ApiFalsa();
      await t.pumpWidget(app(PantallaInicioSesion(api: ClienteApi(cliente: f.cliente))));
      await t.tap(find.text('Ingresar'));
      await t.pump();
      expect(find.text('Ingresa tu correo y tu contraseña.'), findsOneWidget);
      expect(f.peticiones, isEmpty);
    });

    testWidgets('credenciales correctas llevan al menú (A3)', (t) async {
      final f = ApiFalsa();
      await t.pumpWidget(app(PantallaInicioSesion(api: ClienteApi(cliente: f.cliente))));
      await escribir(t, 0, 'admin@unmsm.edu.pe');
      await escribir(t, 1, 'clave-correcta');
      await t.tap(find.text('Ingresar'));
      await t.pumpAndSettle();
      expect(find.text('Hola, Renzo'), findsOneWidget);
      expect(find.text('Última carga: datos al 30/09/2026 · 1 842 registros'),
          findsOneWidget);
      // El menú consulta las cargas con el token recibido.
      expect(f.peticiones.last.headers['Authorization'], 'Bearer token-de-prueba');
    });

    testWidgets('si la sesión vence, vuelve al inicio de sesión con aviso', (t) async {
      final f = ApiFalsa()..listarResponde401 = true;
      await t.pumpWidget(app(PantallaInicioSesion(api: ClienteApi(cliente: f.cliente))));
      await escribir(t, 0, 'admin@unmsm.edu.pe');
      await escribir(t, 1, 'clave-correcta');
      await t.tap(find.text('Ingresar'));
      await t.pumpAndSettle();
      expect(find.text(avisoSesionVencida), findsOneWidget);
      expect(find.text('Ingresar'), findsOneWidget);
    });
  });

  group('A4 · A5 carga de precios', () {
    Future<(ApiFalsa, ClienteApi)> conSesion() async {
      final f = ApiFalsa();
      final api = ClienteApi(cliente: f.cliente);
      await api.iniciarSesion('admin@unmsm.edu.pe', 'clave-correcta');
      return (f, api);
    }

    Future<ArchivoElegido?> archivoFalso() async =>
        ArchivoElegido('reporte.xls', Uint8List.fromList(List.filled(23350, 60)));

    Future<void> abrirCarga(WidgetTester t, ClienteApi api) async {
      // Se abre desde una pantalla previa para que «volver» tenga a dónde ir.
      await t.pumpWidget(app(Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute(
                  builder: (_) => PantallaCargaPrecios(api: api, elegirArchivo: archivoFalso))),
              child: const Text('abrir'),
            ),
          ),
        ),
      )));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    testWidgets('sin archivo no se puede cargar', (t) async {
      final (_, api) = await conSesion();
      await abrirCarga(t, api);
      final boton = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Cargar y validar'));
      expect(boton.onPressed, isNull);
    });

    testWidgets('flujo completo: elegir, validar, revisar y confirmar', (t) async {
      final (f, api) = await conSesion();
      await abrirCarga(t, api);

      await t.tap(find.text('Seleccionar archivo'));
      await t.pumpAndSettle();
      expect(find.text('reporte.xls'), findsOneWidget);
      expect(find.text('23 KB · seleccionado'), findsOneWidget);

      await t.tap(find.text('Cargar y validar'));
      await t.pumpAndSettle();

      // Lo que recibió la API: multipart con la fuente, el archivo y el token.
      final subida = f.peticiones.lastWhere((p) => p.method == 'POST');
      expect(subida.headers['Authorization'], 'Bearer token-de-prueba');
      expect(subida.headers['content-type'], startsWith('multipart/form-data'));
      final cuerpo = latin1.decode(subida.bodyBytes);
      expect(cuerpo, contains('name="fuente"'));
      expect(cuerpo, contains('SISAP minorista'));
      expect(cuerpo, contains('filename="reporte.xls"'));

      // A5: el resumen.
      expect(find.text('Resumen de la carga'), findsOneWidget);
      expect(find.text('01/09/2026 – 13/10/2026'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('43'), findsNWidgets(2));            // rechazados y su motivo
      expect(find.text('Duplicado'), findsOneWidget);
      expect(find.text('Tomate marzano'), findsOneWidget);

      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      expect(find.text('La carga se completó: se guardaron 18 precios.'), findsOneWidget);

      await t.tap(find.text('Volver al menú'));
      await t.pumpAndSettle();
      expect(find.text('abrir'), findsOneWidget);           // volvió hasta el inicio
    });

    testWidgets('un archivo con formato no válido muestra el motivo (EX2)', (t) async {
      final (f, api) = await conSesion();
      f.estadoSubida = 400;
      await abrirCarga(t, api);
      await t.tap(find.text('Seleccionar archivo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cargar y validar'));
      await t.pumpAndSettle();
      expect(find.text('El archivo no corresponde al formato esperado'), findsOneWidget);
      expect(find.text('• el archivo es de la región «Arequipa»'), findsOneWidget);
    });

    testWidgets('salir del resumen sin decidir pregunta, y descartar libera el archivo',
        (t) async {
      final (f, api) = await conSesion();
      await abrirCarga(t, api);
      await t.tap(find.text('Seleccionar archivo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cargar y validar'));
      await t.pumpAndSettle();

      await t.tap(find.byTooltip('Volver'));
      await t.pumpAndSettle();
      expect(find.text('¿Salir sin confirmar?'), findsOneWidget);

      await t.tap(find.text('Seguir revisando'));
      await t.pumpAndSettle();
      expect(find.text('Resumen de la carga'), findsOneWidget);
      expect(f.peticiones.where((p) => p.method == 'PATCH'), isEmpty);

      await t.tap(find.byTooltip('Volver'));
      await t.pumpAndSettle();
      await t.tap(find.text('Descartar y salir'));
      await t.pumpAndSettle();
      final patch = f.peticiones.lastWhere((p) => p.method == 'PATCH');
      expect(jsonDecode(patch.body), {'estado': 'descartada'});
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
