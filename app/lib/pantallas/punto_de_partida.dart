// C8 · Punto de partida y modo (CU05, pasos 6 a 8 y EX2).
//
// El punto de partida es la ubicación del GPS o una dirección que el consumidor escribe
// (EX2, o «Usar otra dirección»). Con el GPS se muestra «Tu ubicación actual» y sus
// coordenadas, y no una dirección como en el prototipo: convertir coordenadas en una
// dirección gastaría una consulta más de la cuota diaria de OpenRouteService en cada
// cálculo, solo para mostrarla.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import '../ubicacion.dart';
import 'direccion.dart';

/// Radio de búsqueda: por defecto 3 km (RN06); el contrato admite hasta 20.
const radioInicial = 3;
const radioMinimo = 1;
const radioMaximo = 20;

/// Lo que el consumidor eligió en esta pantalla: con esto se pide el cálculo.
class Partida {
  const Partida(this.origen, this.modo, this.radioKm);
  final Punto origen;
  final ModoDesplazamiento modo;
  final int radioKm;
}

class PantallaPuntoDePartida extends StatefulWidget {
  const PantallaPuntoDePartida({
    super.key,
    required this.api,
    required this.alCalcular,
    this.obtenerUbicacion = ubicacionDelGps,
  });

  final ClienteApi api;
  final ObtenerUbicacion obtenerUbicacion;

  /// «Calcular» (CU05, paso 9 en adelante).
  final void Function(BuildContext, Partida) alCalcular;

  @override
  State<PantallaPuntoDePartida> createState() => _EstadoPartida();
}

class _EstadoPartida extends State<PantallaPuntoDePartida> {
  ResultadoUbicacion? _ubicacion; // nula mientras se busca
  Direccion? _direccion; // la escrita por el consumidor; si hay una, manda sobre el GPS
  List<ModoDesplazamiento>? _modos;
  String? _errorModos;
  ModoDesplazamiento? _modo;
  int _radio = radioInicial;

  @override
  void initState() {
    super.initState();
    _ubicar();
    _cargarModos();
  }

  Future<void> _ubicar() async {
    setState(() => _ubicacion = null);
    final r = await widget.obtenerUbicacion();
    if (mounted) setState(() => _ubicacion = r);
  }

  Future<void> _cargarModos() async {
    setState(() => _errorModos = null);
    try {
      final modos = await widget.api.listarModos();
      if (mounted) setState(() => _modos = modos);
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _errorModos = e.mensaje);
    }
  }

  Future<void> _otraDireccion() async {
    final d = await Navigator.of(context).push<Direccion>(
      MaterialPageRoute(builder: (_) => PantallaDireccion(api: widget.api)),
    );
    if (d != null && mounted) setState(() => _direccion = d);
  }

  void _usarGps() {
    setState(() => _direccion = null);
    _ubicar();
  }

  @override
  Widget build(BuildContext context) {
    final d = _direccion;
    final origen = d != null ? Punto(d.latitud, d.longitud) : _ubicacion?.punto;
    final modo = _modo;
    return MarcoPantalla(
      barra: BarraSuperior(
        'Calcular costo total',
        alVolver: () => Navigator.of(context).pop(),
      ),
      contenido: [
        _tarjetaPartida(),
        const SizedBox(height: 14),
        Text('Modo de desplazamiento', style: Textos.etiquetaM()),
        const SizedBox(height: 14),
        ..._modosDeDesplazamiento(),
        const SizedBox(height: 14),
        _tarjetaRadio(),
      ],
      pie: SizedBox(
        width: double.infinity,
        child: BotonPrimario(
          'Calcular',
          alPresionar: origen == null || modo == null
              ? null
              : () => widget.alCalcular(context, Partida(origen, modo, _radio)),
        ),
      ),
    );
  }

  Widget _tarjetaPartida() {
    final u = _direccion != null ? null : _ubicacion;
    final buscando = _direccion == null && u == null;
    final sinUbicacion = u != null && u.punto == null;
    final Widget titulo;
    final List<Widget> resto;
    if (_direccion != null) {
      titulo = Text(_direccion!.etiqueta, style: Textos.tituloM());
      resto = [
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            _Enlace('Usar otra dirección', _otraDireccion),
            _Enlace('Usar mi ubicación', _usarGps),
          ],
        ),
      ];
    } else if (u == null) {
      titulo = Text('Buscando tu ubicación…', style: Textos.tituloM());
      resto = [];
    } else if (u.punto != null) {
      final p = u.punto!;
      titulo = Text('Tu ubicación actual', style: Textos.tituloM());
      resto = [
        Text(
          '${p.latitud.toStringAsFixed(5)}, ${p.longitud.toStringAsFixed(5)}',
          style: Textos.cuerpoS(),
        ),
        const SizedBox(height: 10),
        _Enlace('Usar otra dirección', _otraDireccion),
      ];
    } else {
      // EX2 y los demás casos en que no hay ubicación.
      final falla = u.falla!;
      titulo = Text(switch (falla) {
        FallaUbicacion.gpsApagado => 'La ubicación del teléfono está desactivada',
        FallaUbicacion.sinPermiso => 'No autorizaste el uso de tu ubicación',
        FallaUbicacion.sinPermisoSiempre => 'La aplicación no tiene permiso de ubicación',
        FallaUbicacion.sinRespuesta => 'No se pudo obtener tu ubicación',
      }, style: Textos.tituloM(Colores.textoError));
      final ajustes =
          !kIsWeb &&
          (falla == FallaUbicacion.gpsApagado ||
              falla == FallaUbicacion.sinPermisoSiempre);
      resto = [
        Text(
          'Puedes intentarlo de nuevo o ingresar la dirección desde donde saldrás.',
          style: Textos.cuerpoS(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            if (ajustes)
              _Enlace('Abrir ajustes', () => abrirAjustes(falla))
            else
              _Enlace('Volver a intentar', _ubicar),
            _Enlace('Ingresar una dirección', _otraDireccion),
          ],
        ),
      ];
    }
    return Tarjeta(
      relleno: const EdgeInsets.all(16),
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: buscando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colores.primario,
                        ),
                      )
                    : Icon(
                        Icons.location_on_outlined,
                        size: 22,
                        color: sinUbicacion ? Colores.textoError : Colores.primario,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Punto de partida', style: Textos.etiquetaS(Colores.textoSuave)),
                    const SizedBox(height: 2),
                    titulo,
                    ...resto,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tu ubicación solo se usa para este cálculo y no se guarda en el servidor.',
            style: Textos.etiquetaS(Colores.textoSuave),
          ),
        ],
      ),
    );
  }

  List<Widget> _modosDeDesplazamiento() {
    final modos = _modos;
    if (_errorModos != null) {
      return [
        Aviso(_errorModos!),
        const SizedBox(height: 10),
        BotonSecundario('Reintentar', alPresionar: _cargarModos),
      ];
    }
    if (modos == null) {
      return [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(color: Colores.primario)),
        ),
      ];
    }
    // De dos en dos, con el alto que pida el texto: así no se corta si el teléfono usa
    // letra grande.
    Widget tarjeta(ModoDesplazamiento m) => _TarjetaModo(
      m,
      elegido: _modo?.id == m.id,
      alElegir: m.conTarifa ? () => setState(() => _modo = m) : null,
    );
    return [
      for (var i = 0; i < modos.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tarjeta(modos[i])),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < modos.length ? tarjeta(modos[i + 1]) : const SizedBox(),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _tarjetaRadio() {
    return Tarjeta(
      relleno: const EdgeInsets.all(16),
      hijo: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Radio de búsqueda', style: Textos.tituloM()),
                const SizedBox(height: 2),
                Text('Mercados dentro de esta distancia', style: Textos.cuerpoS()),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colores.bordeFuerte),
              borderRadius: BorderRadius.circular(Radios.r8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BotonRadio(
                  Icons.remove,
                  'Reducir radio',
                  _radio > radioMinimo ? () => setState(() => _radio--) : null,
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    '$_radio km',
                    style: Textos.numeroM(),
                    textAlign: TextAlign.center,
                  ),
                ),
                _BotonRadio(
                  Icons.add,
                  'Ampliar radio',
                  _radio < radioMaximo ? () => setState(() => _radio++) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Sin costo», «S/ 2.50» o «S/ 1.14 por km», como en el prototipo.
String describirTarifa(ModoDesplazamiento m) {
  if (!m.conTarifa) return 'Sin tarifa disponible';
  final monto = 'S/ ${m.monto!.toStringAsFixed(2)}';
  if (m.tipoCobro == 'por_km') return '$monto por km';
  return m.monto == 0 ? 'Sin costo' : monto;
}

IconData iconoDeModo(String nombre) => switch (nombre) {
  'a pie' => Icons.directions_walk,
  'transporte público' => Icons.directions_bus_outlined,
  'taxi' => Icons.local_taxi_outlined,
  _ => Icons.directions_car_outlined,
};

class _TarjetaModo extends StatelessWidget {
  const _TarjetaModo(this.modo, {required this.elegido, required this.alElegir});

  final ModoDesplazamiento modo;
  final bool elegido;
  final VoidCallback? alElegir;

  @override
  Widget build(BuildContext context) {
    final color = elegido ? Colores.textoPrimario : Colores.textoFuerte;
    final radio = BorderRadius.circular(elegido ? Radios.r12 : Radios.r14);
    return Opacity(
      opacity: alElegir == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: alElegir,
          borderRadius: radio,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: elegido ? Colores.primarioSuave : Colores.superficie,
              borderRadius: radio,
              border: elegido ? Border.all(color: Colores.primario, width: 2) : null,
              boxShadow: elegido ? null : sombraTarjeta,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(iconoDeModo(modo.nombre), size: 24, color: color),
                const SizedBox(height: 8),
                Text(capitalizar(modo.nombre), style: Textos.etiquetaM(color)),
                const SizedBox(height: 4),
                Text(describirTarifa(modo), style: Textos.etiquetaS(Colores.textoSuave)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonRadio extends StatelessWidget {
  const _BotonRadio(this.icono, this.ayuda, this.alPresionar);

  final IconData icono;
  final String ayuda;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: ayuda,
    child: InkWell(
      onTap: alPresionar,
      child: SizedBox(
        width: 34,
        height: 36,
        child: Icon(
          icono,
          size: 16,
          color: alPresionar == null ? Colores.bordeFuerte : Colores.primario,
        ),
      ),
    ),
  );
}

class _Enlace extends StatelessWidget {
  const _Enlace(this.texto, this.alPresionar);

  final String texto;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: alPresionar,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(texto, style: Textos.etiquetaM(Colores.textoPrimario)),
    ),
  );
}
