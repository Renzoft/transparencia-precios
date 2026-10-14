// Cliente de la API REST (openapi.yaml). Cubre lo que usa el panel: iniciar sesión, las
// operaciones de /cargas (CU01) y las de /mercados y /tarifas (CU02).
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
  ErrorApi(this.estado, this.codigo, this.mensaje,
      [this.detalles = const [], this.problemas = const {}]);

  final int estado;
  final String codigo;
  final String mensaje;
  final List<String> detalles;           // «campo: problema», ya listo para mostrar
  final Map<String, String> problemas;   // campo -> problema, para señalar cada campo

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
      final problemas = {
        for (final d in (e['detalles'] as List? ?? const []))
          '${(d as Map)['campo']}': '${d['problema']}'
      };
      return ErrorApi(r.statusCode, e['codigo'] as String, e['mensaje'] as String,
          detalles, problemas);
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

class Mercado {
  Mercado({
    required this.id,
    required this.nombre,
    required this.distrito,
    required this.direccion,
    required this.latitud,
    required this.longitud,
    required this.activo,
    this.horario,
  });

  final int id;
  final String nombre;
  final String distrito;
  final String direccion;
  final double latitud;
  final double longitud;
  final String? horario;
  final bool activo;

  factory Mercado.desdeJson(Map<String, dynamic> j) => Mercado(
        id: j['id_mercado'] as int,
        nombre: j['nombre'] as String,
        distrito: j['distrito'] as String,
        direccion: j['direccion'] as String,
        latitud: (j['latitud'] as num).toDouble(),
        longitud: (j['longitud'] as num).toDouble(),
        horario: j['horario_atencion'] as String?,
        activo: j['activo'] as bool,
      );
}

class ModoDesplazamiento {
  ModoDesplazamiento(this.id, this.nombre);
  final int id;
  final String nombre;
}

class Tarifa {
  Tarifa({
    required this.id,
    required this.idModo,
    required this.tipoCobro,
    required this.monto,
    required this.desde,
    this.hasta,
  });

  final int id;
  final int idModo;
  final String tipoCobro;
  final double monto;
  final DateTime desde;
  final DateTime? hasta;

  factory Tarifa.desdeJson(Map<String, dynamic> j) => Tarifa(
        id: j['id_tarifa'] as int,
        idModo: j['id_modo_desplazamiento'] as int,
        tipoCobro: j['tipo_cobro'] as String,
        monto: (j['monto'] as num).toDouble(),
        desde: DateTime.parse(j['vigente_desde'] as String),
        hasta: j['vigente_hasta'] == null ? null : DateTime.parse(j['vigente_hasta'] as String),
      );
}

/// Fecha AAAA-MM-DD, como la pide el contrato.
String fechaIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

  /// GET /mercados con los desactivados: el administrador ve todos (CU02, paso 2).
  Future<List<Mercado>> listarMercados() async {
    final r = await _enviar(() => _http.get(
        _url('/mercados', {'incluir_inactivos': 'true'}), headers: _cabeceras));
    return [for (final m in _json(r) as List) Mercado.desdeJson(m as Map<String, dynamic>)];
  }

  /// POST /mercados (CU02, pasos 5 a 9).
  Future<Mercado> crearMercado(Map<String, Object?> datos) async {
    final r = await _enviar(() => _http.post(_url('/mercados'),
        headers: {..._cabeceras, 'Content-Type': 'application/json'},
        body: jsonEncode(datos)));
    return Mercado.desdeJson(_json(r) as Map<String, dynamic>);
  }

  /// PATCH /mercados/{id}: solo los campos que cambian; {"activo": false} desactiva.
  Future<Mercado> actualizarMercado(int id, Map<String, Object?> cambios) async {
    final r = await _enviar(() => _http.patch(_url('/mercados/$id'),
        headers: {..._cabeceras, 'Content-Type': 'application/json'},
        body: jsonEncode(cambios)));
    return Mercado.desdeJson(_json(r) as Map<String, dynamic>);
  }

  /// GET /modos-desplazamiento.
  Future<List<ModoDesplazamiento>> listarModos() async {
    final r = await _enviar(() => _http.get(_url('/modos-desplazamiento')));
    return [
      for (final m in _json(r) as List)
        ModoDesplazamiento((m as Map)['id_modo_desplazamiento'] as int, m['nombre'] as String)
    ];
  }

  /// GET /tarifas: todo el historial, para saber también desde cuándo rige cada una.
  Future<List<Tarifa>> listarTarifas() async {
    final r = await _enviar(() => _http.get(_url('/tarifas'), headers: _cabeceras));
    return [for (final t in _json(r) as List) Tarifa.desdeJson(t as Map<String, dynamic>)];
  }

  /// POST /tarifas: nueva vigencia; la API cierra la anterior (AD13).
  Future<Tarifa> crearTarifa(int idModo, String tipoCobro, double monto, DateTime desde) async {
    final r = await _enviar(() => _http.post(_url('/tarifas'),
        headers: {..._cabeceras, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_modo_desplazamiento': idModo,
          'tipo_cobro': tipoCobro,
          'monto': monto,
          'vigente_desde': fechaIso(desde),
        })));
    return Tarifa.desdeJson(_json(r) as Map<String, dynamic>);
  }
}
