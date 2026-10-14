// Cliente de la API REST (openapi.yaml). Solo cubre lo que usa el CU01: iniciar sesión
// y las cuatro operaciones de /cargas.
//
// El token se guarda solo en memoria, nunca en el almacenamiento del navegador: si se
// recarga la página hay que volver a entrar, pero un token no queda guardado donde otro
// script de la página podría leerlo.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Dirección de la API. Se cambia al compilar: --dart-define=API_URL=https://...
const urlApi = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

/// Un error de la API, con el formato del contrato: {"error": {codigo, mensaje, detalles}}.
class ErrorApi implements Exception {
  ErrorApi(this.estado, this.codigo, this.mensaje, [this.detalles = const []]);

  final int estado;
  final String codigo;
  final String mensaje;
  final List<String> detalles;      // «campo: problema», ya listo para mostrar

  bool get sesionVencida => estado == 401;

  factory ErrorApi.desdeRespuesta(http.Response r) {
    try {
      final e = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['error'] as Map;
      final detalles = [
        for (final d in (e['detalles'] as List? ?? const []))
          (d as Map)['campo'] == 'archivo'
              ? '${d['problema']}'
              : '${d['campo']}: ${d['problema']}'
      ];
      return ErrorApi(r.statusCode, e['codigo'] as String, e['mensaje'] as String, detalles);
    } catch (_) {
      return ErrorApi(r.statusCode, 'RESPUESTA_INESPERADA',
          'El servidor respondió algo inesperado (código ${r.statusCode}).');
    }
  }

  @override
  String toString() => 'ErrorApi($estado, $codigo, $mensaje)';
}

class Usuario {
  Usuario(this.nombre, this.rol);
  final String nombre;
  final String rol;
}

class Rechazo {
  Rechazo(this.motivo, this.cantidad);
  final String motivo;
  final int cantidad;
}

class CargaResumen {
  CargaResumen({
    required this.id,
    required this.estado,
    required this.nombreArchivo,
    required this.registrosValidos,
    required this.registrosRechazados,
    this.fuente,
    this.desde,
    this.hasta,
    this.rechazos = const [],
    this.productosNuevos = const [],
    this.variedadesNuevas = const [],
  });

  final int id;
  final String estado;
  final String nombreArchivo;
  final String? fuente;
  final DateTime? desde;
  final DateTime? hasta;
  final int registrosValidos;
  final int registrosRechazados;
  final List<Rechazo> rechazos;
  final List<String> productosNuevos;
  final List<String> variedadesNuevas;

  factory CargaResumen.desdeJson(Map<String, dynamic> j) {
    final periodo = j['periodo'] as Map?;
    final catalogo = j['catalogo_nuevo'] as Map?;
    return CargaResumen(
      id: j['id_carga_archivo'] as int,
      estado: j['estado'] as String,
      nombreArchivo: j['nombre_archivo'] as String,
      fuente: j['fuente'] as String?,
      desde: periodo == null ? null : DateTime.parse(periodo['desde'] as String),
      hasta: periodo == null ? null : DateTime.parse(periodo['hasta'] as String),
      registrosValidos: j['registros_validos'] as int,
      registrosRechazados: j['registros_rechazados'] as int,
      rechazos: [
        for (final r in (j['rechazos'] as List? ?? const []))
          Rechazo((r as Map)['motivo'] as String, r['cantidad'] as int)
      ],
      productosNuevos: [...((catalogo?['productos'] as List?) ?? const []).cast<String>()],
      variedadesNuevas: [...((catalogo?['variedades'] as List?) ?? const []).cast<String>()],
    );
  }
}

class CargaResuelta {
  CargaResuelta(this.estado, this.preciosGuardados);
  final String estado;
  final int preciosGuardados;
}

class ClienteApi {
  ClienteApi({String base = urlApi, http.Client? cliente})
      : _base = base.replaceAll(RegExp(r'/+$'), ''),
        _http = cliente ?? http.Client();

  final String _base;
  final http.Client _http;
  String? _token;
  Usuario? usuario;

  bool get conSesion => _token != null;

  Uri _url(String ruta, [Map<String, String>? consulta]) =>
      Uri.parse('$_base/api/v1$ruta').replace(queryParameters: consulta);

  Map<String, String> get _cabeceras => {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<http.Response> _enviar(Future<http.Response> Function() peticion) async {
    final http.Response r;
    try {
      r = await peticion();
    } catch (_) {
      throw ErrorApi(0, 'SIN_CONEXION',
          'No se pudo conectar con el servidor. Revisa que la API esté encendida.');
    }
    if (r.statusCode >= 400) {
      final e = ErrorApi.desdeRespuesta(r);
      if (e.sesionVencida && _token != null) cerrarSesion();
      throw e;
    }
    return r;
  }

  dynamic _json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  /// POST /sesiones (R1).
  Future<Usuario> iniciarSesion(String correo, String contrasena) async {
    final r = await _enviar(() => _http.post(_url('/sesiones'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'correo': correo.trim(), 'contrasena': contrasena})));
    final j = _json(r) as Map<String, dynamic>;
    _token = j['token'] as String;
    final u = j['usuario'] as Map;
    return usuario = Usuario(u['nombre'] as String, u['rol'] as String);
  }

  void cerrarSesion() {
    _token = null;
    usuario = null;
  }

  /// GET /cargas.
  Future<List<CargaResumen>> listarCargas({int limite = 50}) async {
    final r = await _enviar(() =>
        _http.get(_url('/cargas', {'limite': '$limite'}), headers: _cabeceras));
    return [
      for (final c in _json(r) as List) CargaResumen.desdeJson(c as Map<String, dynamic>)
    ];
  }

  /// POST /cargas: sube el archivo y devuelve el resumen; todavía no guarda precios.
  Future<CargaResumen> subirCarga(Uint8List contenido, String nombre, String fuente) async {
    final r = await _enviar(() async {
      final peticion = http.MultipartRequest('POST', _url('/cargas'))
        ..headers.addAll(_cabeceras)
        ..fields['fuente'] = fuente
        ..files.add(http.MultipartFile.fromBytes('archivo', contenido, filename: nombre));
      return http.Response.fromStream(await _http.send(peticion));
    });
    return CargaResumen.desdeJson(_json(r) as Map<String, dynamic>);
  }

  /// PATCH /cargas/{id}: «confirmada» guarda los precios; «descartada», nada.
  Future<CargaResuelta> resolverCarga(int id, String estado) async {
    final r = await _enviar(() => _http.patch(_url('/cargas/$id'),
        headers: {..._cabeceras, 'Content-Type': 'application/json'},
        body: jsonEncode({'estado': estado})));
    final j = _json(r) as Map<String, dynamic>;
    return CargaResuelta(j['estado'] as String, j['precios_guardados'] as int);
  }
}
