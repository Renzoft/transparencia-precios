// Pruebas de «Mi lista de compras» (CU05, pasos 1 a 4). La API se simula con respuestas
// en el formato del contrato, y el almacenamiento del teléfono, con el de prueba de
// shared_preferences.

import 'dart:convert';

import 'package:app_consumidor/api.dart';
import 'package:app_consumidor/componentes.dart';
import 'package:app_consumidor/lista.dart';
import 'package:app_consumidor/main.dart';
import 'package:app_consumidor/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response json(Object cuerpo, int estado) => http.Response.bytes(
    utf8.encode(jsonEncode(cuerpo)), estado,
    headers: {'content-type': 'application/json; charset=utf-8'});

class ApiFalsa {
  final peticiones = <http.Request>[];
  bool caida = false;

  late final cliente = MockClient((r) async {
    peticiones.add(r);
    if (caida) throw const SocketExceptionFalsa();
    switch (r.url.path) {
      case '/api/v1/productos':
        return json([
          {'id_producto': 1, 'nombre': 'Papa'},
          {'id_producto': 5, 'nombre': 'Limón'},
          {'id_producto': 8, 'nombre': 'Aceite'},
        ], 200);
      case '/api/v1/productos/1/variedades':
        return json([
          for (final (id, nombre) in [(1, 'Papa amarilla'), (2, 'Papa canchan')])
            {
              'id_variedad': id,
              'id_producto': 1,
              'nombre': nombre,
              'unidad_origen': 'kilogramo',
              'factor_a_kg': 1.0
            }
        ], 200);
      case '/api/v1/productos/8/variedades':
        return json([
          {
            'id_variedad': 9,
            'id_producto': 8,
            'nombre': 'Aceite clásico botella 900 ml',
            'unidad_origen': 'litro',
            'factor_a_kg': 0.92
          }
        ], 200);
    }
    return json({
      'error': {'codigo': 'RECURSO_NO_ENCONTRADO', 'mensaje': 'No existe'}
    }, 404);
  });
}

class SocketExceptionFalsa implements Exception {
  const SocketExceptionFalsa();
}

Future<ListaCompras> abrir(WidgetTester t, ApiFalsa f) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final lista = ListaCompras();
  await lista.cargar();
  await t.pumpWidget(AppConsumidor(api: ClienteApi(cliente: f.cliente), lista: lista));
  await t.pumpAndSettle();
  return lista;
}

/// Desde la lista: agregar, elegir producto y variedad, ajustar la cantidad y aceptar.
Future<void> agregar(WidgetTester t, String producto, String variedad,
    {int sumas = 0, String boton = 'Agregar a la lista'}) async {
  await t.tap(find.text(find.text('Agregar productos').evaluate().isEmpty
      ? 'Agregar otro producto'
      : 'Agregar productos'));
  await t.pumpAndSettle();
  await t.tap(find.text(producto));
  await t.pumpAndSettle();
  await t.tap(find.text(variedad));
  await t.pumpAndSettle();
  for (var i = 0; i < sumas; i++) {
    await t.tap(find.byTooltip('Sumar'));
    await t.pump();
  }
  await t.tap(find.text(boton));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    usarInter = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('la lista y su copia en el teléfono', () {
    ItemLista papa([double cantidad = 1]) => ItemLista(
        idVariedad: 1,
        nombre: 'Papa amarilla',
        unidad: 'kilogramo',
        factorAKg: 1,
        cantidad: cantidad);

    test('una variedad aparece una sola vez: volver a ponerla cambia la cantidad', () async {
      final l = ListaCompras();
      await l.poner(papa());
      await l.poner(papa(2.5));
      expect(l.items.single.cantidad, 2.5);
    });

    test('se guarda y se recupera al volver a abrir la aplicación', () async {
      final l = ListaCompras();
      await l.poner(papa(2));
      final otra = ListaCompras();
      await otra.cargar();
      expect(otra.items.single.nombre, 'Papa amarilla');
      expect(otra.items.single.cantidad, 2);
    });

    test('restar medio kilo; en la mínima, el producto sale', () async {
      final l = ListaCompras();
      await l.poner(papa(1));
      await l.restar(l.items.single);
      expect(l.items.single.cantidad, 0.5);
      await l.restar(l.items.single);
      expect(l.vacia, isTrue);
    });

    test('la cantidad en kg usa el factor de la variedad (RN10)', () {
      final aceite = ItemLista(
          idVariedad: 9, nombre: 'Aceite', unidad: 'litro', factorAKg: 0.92, cantidad: 2);
      expect(aceite.cantidadKg, closeTo(1.84, 1e-9));
    });

    test('si lo guardado está dañado, empieza vacía en vez de fallar', () async {
      SharedPreferences.setMockInitialValues({'lista_de_compras': '{no es json'});
      final l = ListaCompras();
      await l.cargar();
      expect(l.vacia, isTrue);
    });
  });

  testWidgets('C6: la lista vacía invita a agregar productos', (t) async {
    await abrir(t, ApiFalsa());
    expect(find.text('Tu lista está vacía'), findsOneWidget);
    expect(find.text('Agregar productos'), findsOneWidget);
    expect(find.text('Calcular costo total'), findsNothing);   // EX1 no puede ocurrir
  });

  testWidgets('agregar un producto: buscar, elegir variedad y cantidad (C7)', (t) async {
    final f = ApiFalsa();
    final lista = await abrir(t, f);
    await t.tap(find.text('Agregar productos'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'limon');           // sin tilde
    await t.pump();
    expect(find.text('Limón'), findsOneWidget);
    expect(find.text('Papa'), findsNothing);
    await t.enterText(find.byType(TextField), '');
    await t.pump();
    await t.tap(find.text('Papa'));
    await t.pumpAndSettle();
    expect(find.text('2 variedades disponibles'), findsOneWidget);
    await t.tap(find.text('Papa amarilla'));
    await t.pumpAndSettle();
    expect(find.text('1.0 kg'), findsOneWidget);                  // empieza en 1
    await t.tap(find.byTooltip('Sumar'));
    await t.pump();
    await t.tap(find.text('Agregar a la lista'));
    await t.pumpAndSettle();

    expect(find.text('Mi lista de compras'), findsOneWidget);     // volvió a la lista
    expect(find.text('1 producto'), findsOneWidget);
    expect(find.text('Guardada en este dispositivo'), findsOneWidget);
    expect(find.text('1.5 kg'), findsOneWidget);
    expect(lista.items.single.idVariedad, 1);
  });

  testWidgets('la unidad es la de la variedad: el aceite se pide en litros', (t) async {
    final lista = await abrir(t, ApiFalsa());
    await agregar(t, 'Aceite', 'Aceite clásico botella 900 ml');
    expect(find.text('1.0 L'), findsOneWidget);
    expect(lista.items.single.cantidadKg, closeTo(0.92, 1e-9));
  });

  testWidgets('elegir una variedad que ya está en la lista actualiza su cantidad', (t) async {
    final lista = await abrir(t, ApiFalsa());
    await agregar(t, 'Papa', 'Papa amarilla');
    await t.tap(find.text('Agregar otro producto'));
    await t.pumpAndSettle();
    await t.tap(find.text('Papa'));
    await t.pumpAndSettle();
    expect(find.text('En tu lista: 1.0 kg'), findsOneWidget);
    await t.tap(find.text('Papa amarilla'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Sumar'));
    await t.pump();
    await t.tap(find.text('Actualizar cantidad'));
    await t.pumpAndSettle();
    expect(lista.items, hasLength(1));
    expect(find.text('1.5 kg'), findsOneWidget);
  });

  testWidgets('− y + cambian la cantidad; en la mínima, quita y se puede deshacer',
      (t) async {
    final lista = await abrir(t, ApiFalsa());
    await agregar(t, 'Papa', 'Papa amarilla');
    await t.tap(find.byTooltip('Sumar'));
    await t.pump();
    expect(find.text('1.5 kg'), findsOneWidget);
    await t.tap(find.byTooltip('Restar'));
    await t.pump();
    await t.tap(find.byTooltip('Restar'));
    await t.pump();
    expect(find.text('0.5 kg'), findsOneWidget);
    await t.tap(find.byTooltip('Restar'));
    await t.pumpAndSettle();
    expect(find.text('Tu lista está vacía'), findsOneWidget);
    expect(find.text('Se quitó Papa amarilla de la lista'), findsOneWidget);
    await t.tap(find.text('Deshacer'));
    await t.pumpAndSettle();
    expect(lista.items.single.cantidad, 0.5);
  });

  testWidgets('sin conexión: lo dice y permite reintentar', (t) async {
    final f = ApiFalsa()..caida = true;
    await abrir(t, f);
    await t.tap(find.text('Agregar productos'));
    await t.pumpAndSettle();
    expect(find.textContaining('No se pudo conectar con el servidor'), findsOneWidget);
    f.caida = false;
    await t.tap(find.text('Reintentar'));
    await t.pumpAndSettle();
    expect(find.text('Papa'), findsOneWidget);
  });

  test('desde el emulador la API local es 10.0.2.2', () {
    expect(urlApi, 'http://10.0.2.2:8000');
    expect(abreviar('kilogramo'), 'kg');
  });
}
