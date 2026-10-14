// La lista de compras del consumidor. Se guarda en el teléfono y no en el servidor: el
// consumidor no tiene cuenta (CU05, poscondición 1: «queda guardada en el dispositivo»).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo que se suma o resta con «−» y «+»: medio kilo (o medio litro).
const paso = 0.5;

class ItemLista {
  ItemLista({
    required this.idVariedad,
    required this.nombre,
    required this.unidad,
    required this.factorAKg,
    required this.cantidad,
  });

  final int idVariedad;
  final String nombre;
  final String unidad;
  final double factorAKg;

  /// En la unidad de la variedad, que es la que entiende el consumidor.
  double cantidad;

  /// Lo que pide la API (ItemLista.cantidad_kg), convertido con el factor (RN10).
  double get cantidadKg => cantidad * factorAKg;

  Map<String, Object> aJson() => {
        'id_variedad': idVariedad,
        'nombre': nombre,
        'unidad': unidad,
        'factor_a_kg': factorAKg,
        'cantidad': cantidad,
      };

  factory ItemLista.desdeJson(Map<String, dynamic> j) => ItemLista(
        idVariedad: j['id_variedad'] as int,
        nombre: j['nombre'] as String,
        unidad: j['unidad'] as String,
        factorAKg: (j['factor_a_kg'] as num).toDouble(),
        cantidad: (j['cantidad'] as num).toDouble(),
      );
}

/// La lista y su copia en el teléfono. Avisa a las pantallas cada vez que cambia.
class ListaCompras extends ChangeNotifier {
  static const _clave = 'lista_de_compras';

  final List<ItemLista> _items = [];
  List<ItemLista> get items => List.unmodifiable(_items);
  bool get vacia => _items.isEmpty;

  ItemLista? buscar(int idVariedad) =>
      _items.where((i) => i.idVariedad == idVariedad).firstOrNull;

  /// Lee la lista guardada (CU05, paso 2). Si lo guardado no se entiende, empieza vacía.
  Future<void> cargar() async {
    final guardada = (await SharedPreferences.getInstance()).getString(_clave);
    _items.clear();
    if (guardada != null) {
      try {
        _items.addAll([
          for (final j in jsonDecode(guardada) as List)
            ItemLista.desdeJson(j as Map<String, dynamic>)
        ]);
      } catch (_) {
        _items.clear();
      }
    }
    notifyListeners();
  }

  Future<void> _guardar() async {
    notifyListeners();
    await (await SharedPreferences.getInstance())
        .setString(_clave, jsonEncode([for (final i in _items) i.aJson()]));
  }

  /// Agrega la variedad o, si ya estaba, le pone la cantidad nueva: una variedad aparece
  /// una sola vez en la lista.
  Future<void> poner(ItemLista item) {
    final existente = buscar(item.idVariedad);
    if (existente == null) {
      _items.add(item);
    } else {
      existente.cantidad = item.cantidad;
    }
    return _guardar();
  }

  Future<void> sumar(ItemLista item) {
    item.cantidad += paso;
    return _guardar();
  }

  /// Resta medio kilo. Si la cantidad llega a cero, el producto sale de la lista.
  Future<void> restar(ItemLista item) {
    if (item.cantidad - paso <= 0) {
      _items.remove(item);
    } else {
      item.cantidad -= paso;
    }
    return _guardar();
  }

  Future<void> reinsertar(int posicion, ItemLista item) {
    _items.insert(posicion.clamp(0, _items.length), item);
    return _guardar();
  }

  int posicion(ItemLista item) => _items.indexOf(item);
}
