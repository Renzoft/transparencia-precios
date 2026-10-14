// A7 · Nuevo mercado (CU02, pasos 3 a 9, EX1, EX2 y EX3) y su variante de edición (FA1).
//
// Lo que se puede revisar sin preguntar a la API se revisa aquí: campos vacíos (EX1) y
// coordenadas que no son números (EX2, «formato incorrecto»). Si la latitud y la
// longitud están en Lima, y si el mercado ya existe (EX3), lo decide la API.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import 'inicio_sesion.dart';

const mensajeCamposIncompletos = 'Complete los campos obligatorios'; // EX1
const mensajeFueraDeLima = 'Las coordenadas no corresponden a Lima Metropolitana'; // EX2

/// Rótulo de cada campo de la API, para decir cuál falta con el nombre que ve el usuario.
const rotulos = {
  'nombre': 'Nombre del mercado',
  'distrito': 'Distrito',
  'direccion': 'Dirección',
  'latitud': 'Latitud',
  'longitud': 'Longitud',
  'horario_atencion': 'Horario de atención',
};

class PantallaFormularioMercado extends StatefulWidget {
  const PantallaFormularioMercado({super.key, required this.api, this.mercado});

  final ClienteApi api;

  /// El mercado que se edita (FA1). Nulo para registrar uno nuevo.
  final Mercado? mercado;

  @override
  State<PantallaFormularioMercado> createState() => _EstadoFormulario();
}

class _EstadoFormulario extends State<PantallaFormularioMercado> {
  late final _c = {
    for (final campo in rotulos.keys) campo: TextEditingController(text: _inicial(campo)),
  };
  bool _guardando = false;
  String? _error;
  List<String> _detalles = const [];
  String? _errorCoordenadas;

  bool get _editando => widget.mercado != null;

  String _inicial(String campo) {
    final m = widget.mercado;
    if (m == null) return '';
    return switch (campo) {
      'nombre' => m.nombre,
      'distrito' => m.distrito,
      'direccion' => m.direccion,
      // Seis decimales, como los guarda la base.
      'latitud' => m.latitud.toStringAsFixed(6),
      'longitud' => m.longitud.toStringAsFixed(6),
      _ => m.horario ?? '',
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _texto(String campo) => _c[campo]!.text.trim();

  /// Acepta coma o punto decimal: «-12,0912» también es un número.
  double? _numero(String campo) => double.tryParse(_texto(campo).replaceAll(',', '.'));

  Future<void> _guardar() async {
    setState(() {
      _error = null;
      _detalles = const [];
      _errorCoordenadas = null;
    });

    // EX1: se señalan todos los que faltan, no solo el primero.
    final faltan = [
      for (final campo in ['nombre', 'distrito', 'direccion', 'latitud', 'longitud'])
        if (_texto(campo).isEmpty) rotulos[campo]!,
    ];
    if (faltan.isNotEmpty) {
      setState(() {
        _error = mensajeCamposIncompletos;
        _detalles = faltan;
      });
      return;
    }
    // EX2, formato: un texto que no es número no llega a la API.
    final latitud = _numero('latitud'), longitud = _numero('longitud');
    if (latitud == null || longitud == null) {
      setState(
        () => _errorCoordenadas =
            '$mensajeFueraDeLima. ${latitud == null ? 'La latitud' : 'La longitud'} no es '
            'un número.',
      );
      return;
    }

    final datos = <String, Object?>{
      'nombre': _texto('nombre'),
      'distrito': _texto('distrito'),
      'direccion': _texto('direccion'),
      'latitud': latitud,
      'longitud': longitud,
      'horario_atencion': _texto('horario_atencion').isEmpty
          ? null
          : _texto('horario_atencion'),
    };

    final m = widget.mercado;
    if (m != null) {
      // FA1: solo lo que cambió. Si nada cambió, no hay nada que guardar.
      final antes = <String, Object?>{
        'nombre': m.nombre,
        'distrito': m.distrito,
        'direccion': m.direccion,
        'latitud': m.latitud,
        'longitud': m.longitud,
        'horario_atencion': m.horario,
      };
      datos.removeWhere((campo, valor) => valor == antes[campo]);
      if (datos.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
    } else if (datos['horario_atencion'] == null) {
      datos.remove('horario_atencion');
    }

    setState(() => _guardando = true);
    try {
      if (m == null) {
        await widget.api.crearMercado(datos);
      } else {
        await widget.api.actualizarMercado(m.id, datos);
      }
      if (!mounted) return;
      Navigator.of(context).pop(m == null ? 'Mercado registrado' : 'Mercado actualizado');
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sesionVencida) {
        volverAlInicio(context, widget.api, avisoSesionVencida);
        return;
      }
      setState(() {
        _guardando = false;
        if (e.codigo == 'COORDENADAS_FUERA_DE_LIMA') {
          // EX2: el mensaje del CU, y debajo lo que la API encontró.
          final p = e.problemas;
          _errorCoordenadas = [
            e.mensaje,
            for (final campo in p.keys)
              p[campo]!.startsWith('parece')
                  ? 'La ${rotulos[campo]!.toLowerCase()} ${p[campo]}'
                  : '${rotulos[campo] ?? campo}: ${p[campo]}',
          ].join('. ');
        } else if (e.codigo == 'DATOS_NO_VALIDOS') {
          final obligatorios = [
            for (final d in e.problemas.entries)
              if (d.value == 'es obligatorio') rotulos[d.key] ?? d.key,
          ];
          _error = obligatorios.length == e.problemas.length && obligatorios.isNotEmpty
              ? mensajeCamposIncompletos
              : e.mensaje;
          _detalles = obligatorios.length == e.problemas.length
              ? obligatorios
              : [
                  for (final d in e.problemas.entries)
                    '${rotulos[d.key] ?? d.key}: ${d.value}',
                ];
        } else {
          // EX3 y cualquier otro: el mensaje de la API, con su detalle.
          _error = e.mensaje;
          _detalles = e.detalles;
        }
      });
    }
  }

  Widget _campo(String campo, {String? sugerencia, TextInputType? teclado}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Rotulo(rotulos[campo]!),
      Campo(controlador: _c[campo]!, sugerencia: sugerencia, teclado: teclado),
    ],
  );

  @override
  Widget build(BuildContext context) {
    const decimal = TextInputType.numberWithOptions(decimal: true, signed: true);
    return MarcoPantalla(
      barra: BarraSuperior(
        _editando ? 'Editar mercado' : 'Nuevo mercado',
        alVolver: () => Navigator.of(context).pop(),
      ),
      contenido: [
        _campo('nombre', sugerencia: 'Mercado de Magdalena'),
        const SizedBox(height: 14),
        _campo('distrito', sugerencia: 'Magdalena del Mar'),
        const SizedBox(height: 14),
        _campo('direccion', sugerencia: 'Jr. Leoncio Prado 1200'),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _campo('latitud', sugerencia: '-12.091200', teclado: decimal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _campo('longitud', sugerencia: '-77.071200', teclado: decimal),
            ),
          ],
        ),
        if (_errorCoordenadas != null) ...[
          const SizedBox(height: 10),
          _ErrorEnLinea(_errorCoordenadas!),
        ],
        const SizedBox(height: 14),
        _campo('horario_atencion', sugerencia: '6:00 – 18:00 (opcional)'),
        if (_error != null) ...[
          const SizedBox(height: 18),
          Aviso(_error!, detalles: _detalles),
        ],
      ],
      pie: Row(
        children: [
          Expanded(
            child: BotonSecundario(
              'Cancelar',
              alPresionar: _guardando ? null : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BotonPrimario('Guardar', alPresionar: _guardar, cargando: _guardando),
          ),
        ],
      ),
    );
  }
}

/// El error rojo debajo de las coordenadas, como en el prototipo.
class _ErrorEnLinea extends StatelessWidget {
  const _ErrorEnLinea(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.warning_amber_rounded, size: 16, color: Colores.textoError),
      const SizedBox(width: 8),
      Expanded(child: Text(texto, style: Textos.cuerpoS(Colores.textoError))),
    ],
  );
}
