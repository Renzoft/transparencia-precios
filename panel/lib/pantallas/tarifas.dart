// A9 · Tarifas de desplazamiento (CU02, pasos 10 a 13 y EX4). Es la pestaña «Tarifas» de
// la pantalla de mercados; el botón «Guardar tarifas» vive en el pie de esa pantalla y
// llama a guardar() de esta vista.
//
// La API registra una tarifa por petición. Para cumplir la EX4 («sin guardar ningún
// cambio») todo lo que se puede revisar se revisa aquí antes de enviar la primera:
// montos válidos y que ninguna tarifa cambiada se haya cambiado ya hoy (una vigencia
// nueva debe empezar después de la abierta, y la nueva empieza hoy).

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import 'inicio_sesion.dart';

const mensajeMontosNoValidos = 'Ingrese montos válidos'; // EX4

/// El tipo de cobro de cada modo (R5). A pie no tiene: cuesta cero (RN07).
const tipoPorModo = {
  'transporte público': 'fijo',
  'taxi': 'por_km',
  'auto particular': 'por_km',
};

/// Hoy en Lima, que es la fecha con que la API compara (el Perú no cambia de hora).
DateTime hoyEnLima() {
  final t = DateTime.now().toUtc().subtract(const Duration(hours: 5));
  return DateTime(t.year, t.month, t.day);
}

/// Un monto en soles con hasta dos decimales; acepta coma o punto. Nulo si no lo es.
double? leerMonto(String texto) {
  final t = texto.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
  return double.parse(t);
}

class VistaTarifas extends StatefulWidget {
  const VistaTarifas({
    super.key,
    required this.api,
    required this.guardando,
    this.hoy = hoyEnLima,
  });

  final ClienteApi api;

  /// Lo escucha el botón del pie para mostrar que se está guardando.
  final ValueNotifier<bool> guardando;
  final DateTime Function() hoy;

  @override
  State<VistaTarifas> createState() => EstadoVistaTarifas();
}

class _Fila {
  _Fila(this.modo, this.vigente, this.abierta)
    : monto = TextEditingController(text: vigente?.monto.toStringAsFixed(2) ?? '');

  final ModoDesplazamiento modo;
  final Tarifa? vigente; // la que rige hoy
  final Tarifa? abierta; // la que no tiene fecha de cierre (puede empezar en el futuro)
  final TextEditingController monto;
  bool conError = false;

  String get nombre => capitalizar(modo.nombre);
  String? get tipo => tipoPorModo[modo.nombre];
}

class EstadoVistaTarifas extends State<VistaTarifas> {
  List<_Fila>? _filas;
  String? _error;
  List<String> _detalles = const [];
  String? _aviso;
  TipoAviso _tipoAviso = TipoAviso.exito;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final f in _filas ?? const <_Fila>[]) {
      f.monto.dispose();
    }
    super.dispose();
  }

  bool _sesionVencida(ErrorApi e) {
    if (!e.sesionVencida) return false;
    volverAlInicio(context, widget.api, avisoSesionVencida);
    return true;
  }

  Future<void> _cargar() async {
    try {
      final modos = await widget.api.listarModos();
      final tarifas = await widget.api.listarTarifas();
      final hoy = widget.hoy();
      if (!mounted) return;
      setState(() {
        _filas = [
          for (final m in modos)
            _Fila(
              m,
              tarifas
                  .where(
                    (t) =>
                        t.idModo == m.id &&
                        !t.desde.isAfter(hoy) &&
                        (t.hasta == null || t.hasta!.isAfter(hoy)),
                  )
                  .firstOrNull,
              tarifas.where((t) => t.idModo == m.id && t.hasta == null).firstOrNull,
            ),
        ];
      });
    } on ErrorApi catch (e) {
      if (!mounted || _sesionVencida(e)) return;
      setState(() => _error = e.mensaje);
    }
  }

  void _mostrar({
    String? error,
    List<String> detalles = const [],
    String? aviso,
    TipoAviso tipo = TipoAviso.exito,
  }) {
    setState(() {
      _error = error;
      _detalles = detalles;
      _aviso = aviso;
      _tipoAviso = tipo;
    });
  }

  /// «Guardar tarifas» (CU02, pasos 12 y 13).
  Future<void> guardar() async {
    final filas = _filas;
    if (filas == null || widget.guardando.value) return;
    final editables = filas.where((f) => f.tipo != null).toList();

    // EX4: montos no numéricos, negativos o con más de dos decimales. Un campo vacío
    // solo vale si ese modo todavía no tiene tarifa.
    for (final f in editables) {
      final texto = f.monto.text.trim();
      f.conError = texto.isEmpty ? f.vigente != null : leerMonto(texto) == null;
    }
    final conError = [
      for (final f in editables)
        if (f.conError) f.nombre,
    ];
    if (conError.isNotEmpty) {
      _mostrar(error: mensajeMontosNoValidos, detalles: conError);
      return;
    }

    final cambios = [
      for (final f in editables)
        if (f.monto.text.trim().isNotEmpty && leerMonto(f.monto.text) != f.vigente?.monto)
          f,
    ];
    if (cambios.isEmpty) {
      _mostrar(aviso: 'No cambiaste ninguna tarifa.', tipo: TipoAviso.informacion);
      return;
    }

    // Cada tarifa nueva rige desde hoy y debe empezar después de la abierta del modo.
    final hoy = widget.hoy();
    final bloqueadas = [
      for (final f in cambios)
        if (f.abierta != null && !f.abierta!.desde.isBefore(hoy))
          f.abierta!.desde.isAfter(hoy)
              ? '${f.nombre}: ya tiene una tarifa programada desde '
                    '${fecha(f.abierta!.desde)}'
              : '${f.nombre}: su tarifa ya se cambió hoy; podrás cambiarla de nuevo mañana',
    ];
    if (bloqueadas.isNotEmpty) {
      _mostrar(error: 'No se guardó ningún cambio.', detalles: bloqueadas);
      return;
    }

    widget.guardando.value = true;
    _mostrar();
    final guardadas = <String>[];
    try {
      for (final f in cambios) {
        await widget.api.crearTarifa(f.modo.id, f.tipo!, leerMonto(f.monto.text)!, hoy);
        guardadas.add(f.nombre);
      }
      if (!mounted) return;
      _mostrar(aviso: 'Tarifas actualizadas');
    } on ErrorApi catch (e) {
      if (!mounted || _sesionVencida(e)) return;
      _mostrar(
        error: e.mensaje,
        detalles: [
          ...e.detalles,
          if (guardadas.isNotEmpty) 'Sí se guardaron: ${guardadas.join(', ')}',
        ],
      );
    } finally {
      widget.guardando.value = false;
    }
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Las tarifas se aplican de ida y vuelta al calcular el costo de desplazamiento.',
          style: Textos.cuerpoS(),
        ),
        const SizedBox(height: 14),
        if (filas == null && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: Colores.primario)),
          ),
        for (final f in filas ?? const <_Fila>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _TarjetaTarifa(
              f,
              alCambiar: () {
                if (f.conError) setState(() => f.conError = false);
              },
            ),
          ),
        if (_aviso != null) Aviso(_aviso!, tipo: _tipoAviso),
        if (_error != null) Aviso(_error!, detalles: _detalles),
      ],
    );
  }
}

class _TarjetaTarifa extends StatelessWidget {
  const _TarjetaTarifa(this.fila, {required this.alCambiar});

  final _Fila fila;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final f = fila;
    final descripcion = switch (f.tipo) {
      null => 'Sin costo',
      'fijo' => 'Pasaje fijo',
      _ => 'Por kilómetro',
    };
    final desde = f.tipo != null && f.vigente != null
        ? ' · desde ${fecha(f.vigente!.desde)}'
        : '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(Radios.r14),
        boxShadow: sombraTarjeta,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.nombre, style: Textos.tituloM()),
                const SizedBox(height: 3),
                Text('$descripcion$desde', style: Textos.cuerpoS()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (f.tipo == null)
            // A pie: cero siempre, no se edita (RN07).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colores.fondo,
                borderRadius: BorderRadius.circular(Radios.r8),
              ),
              child: Text('S/ 0.00', style: Textos.numeroM(Colores.textoSuave)),
            )
          else
            SizedBox(width: 108, child: _CampoMonto(f, alCambiar: alCambiar)),
        ],
      ),
    );
  }
}

class _CampoMonto extends StatelessWidget {
  const _CampoMonto(this.fila, {required this.alCambiar});

  final _Fila fila;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder borde(Color c, [double ancho = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radios.r8),
      borderSide: BorderSide(color: c, width: ancho),
    );
    final error = fila.conError;
    return TextField(
      controller: fila.monto,
      onChanged: (_) => alCambiar(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Textos.numeroM(),
      decoration: InputDecoration(
        isDense: true,
        prefixText: 'S/ ',
        prefixStyle: Textos.numeroM(),
        hintText: '0.00',
        hintStyle: Textos.numeroM(Colores.textoSuave),
        filled: true,
        fillColor: error ? Colores.errorSuave : Colores.superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: borde(error ? Colores.textoError : Colores.bordeFuerte),
        focusedBorder: borde(error ? Colores.textoError : Colores.primario, 1.5),
        border: borde(Colores.bordeFuerte),
      ),
    );
  }
}
