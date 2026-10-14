// Cliente de la API REST (openapi.yaml), en lo que usa el consumidor. El consumidor no
// inicia sesión: estas operaciones son públicas.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Dirección de la API. Se cambia al compilar: --dart-define=API_URL=https://...
///
/// Sin indicarla, se usa la API local. Desde el emulador de Android la computadora no es
/// «localhost» (ese es el propio emulador) sino 10.0.2.2.
const _urlDefinida = String.fromEnvironment('API_URL');
String get urlApi => _urlDefinida.isNotEmpty
    ? _urlDefinida
    : kIsWeb
        ? 'http://localhost:8000'
        : 'http://10.0.2.2:8000';

class ErrorApi implements Exception {
  ErrorApi(this.estado, this.codigo, this.mensaje);

  final int estado;
  final String codigo;
  final String mensaje;

  factory ErrorApi.desdeRespuesta(http.Response r) {
    try {
      final e = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['error'] as Map;
      return ErrorApi(r.statusCode, e['codigo'] as String, e['mensaje'] as String);
    } catch (_) {
      return ErrorApi(r.statusCode, 'RESPUESTA_INESPERADA',
          'El servidor respondió algo inesperado (código ${r.statusCode}).');
    }
  }

  @override
  String toString() => 'ErrorApi($estado, $codigo, $mensaje)';
}

class Producto {
  Producto(this.id, this.nombre);
  final int id;
  final String nombre;
}

class Variedad {
  Variedad(
      {required this.id,
      required this.idProducto,
      required this.nombre,
      required this.unidad,
      required this.factorAKg});

  final int id;
  final int idProducto;
  final String nombre;
  final String unidad;      // unidad_origen: en ella indica el consumidor la cantidad
  final double factorAKg;   // RN10

  factory Variedad.desdeJson(Map<String, dynamic> j) => Variedad(
        id: j['id_variedad'] as int,
        idProducto: j['id_producto'] as int,
        nombre: j['nombre'] as String,
        unidad: j['unidad_origen'] as String,
        factorAKg: (j['factor_a_kg'] as num).toDouble(),
      );
}

/// Un modo de desplazamiento con la tarifa que rige hoy (nula si aún no tiene).
class ModoDesplazamiento {
  ModoDesplazamiento(this.id, this.nombre, {this.tipoCobro, this.monto});

  final int id;
  final String nombre;
  final String? tipoCobro;   // «fijo» o «por_km»
  final double? monto;

  bool get conTarifa => tipoCobro != null;

  factory ModoDesplazamiento.desdeJson(Map<String, dynamic> j) {
    final t = j['tarifa'] as Map?;
    return ModoDesplazamiento(j['id_modo_desplazamiento'] as int, j['nombre'] as String,
        tipoCobro: t?['tipo_cobro'] as String?, monto: (t?['monto'] as num?)?.toDouble());
  }
}

class ClienteApi {
  ClienteApi({String? base, http.Client? cliente})
      : _base = (base ?? urlApi).replaceAll(RegExp(r'/+$'), ''),
        _http = cliente ?? http.Client();

  final String _base;
  final http.Client _http;

  Uri _url(String ruta, [Map<String, String>? consulta]) =>
      Uri.parse('$_base/api/v1$ruta').replace(queryParameters: consulta);

  Future<dynamic> _get(Uri url) async {
    final http.Response r;
    try {
      r = await _http.get(url).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ErrorApi(0, 'SIN_CONEXION',
          'No se pudo conectar con el servidor. Revisa tu conexión e inténtalo de nuevo.');
    }
    if (r.statusCode >= 400) throw ErrorApi.desdeRespuesta(r);
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// GET /productos (CU05, paso 3: el consumidor busca cada producto).
  Future<List<Producto>> listarProductos({String? buscar}) async {
    final consulta = buscar == null || buscar.trim().isEmpty ? null : {'buscar': buscar.trim()};
    final j = await _get(_url('/productos', consulta)) as List;
    return [
      for (final p in j) Producto((p as Map)['id_producto'] as int, p['nombre'] as String)
    ];
  }

  /// GET /productos/{id}/variedades (CU05, paso 3: selecciona la variedad).
  Future<List<Variedad>> listarVariedades(int idProducto) async {
    final j = await _get(_url('/productos/$idProducto/variedades')) as List;
    return [for (final v in j) Variedad.desdeJson(v as Map<String, dynamic>)];
  }

  /// GET /modos-desplazamiento (CU05, paso 7).
  Future<List<ModoDesplazamiento>> listarModos() async {
    final j = await _get(_url('/modos-desplazamiento')) as List;
    return [for (final m in j) ModoDesplazamiento.desdeJson(m as Map<String, dynamic>)];
  }
}
