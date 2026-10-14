// A5 · Resumen de la carga (CU01, pasos 10 a 13).
//
// Salir sin confirmar ni descartar dejaría la carga pendiente para siempre, y con ella
// bloqueado su archivo. Por eso volver atrás pregunta qué hacer, y la única salida sin
// decidir es seguir revisando.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import 'inicio_sesion.dart';

class PantallaResumenCarga extends StatefulWidget {
  const PantallaResumenCarga({super.key, required this.api, required this.resumen});

  final ClienteApi api;
  final CargaResumen resumen;

  @override
  State<PantallaResumenCarga> createState() => _EstadoResumenCarga();
}

class _EstadoResumenCarga extends State<PantallaResumenCarga> {
  String? _accion;                  // «confirmada» o «descartada» mientras se envía
  CargaResuelta? _resultado;
  ErrorApi? _error;

  bool get _resuelta => _resultado != null;

  Future<void> _resolver(String estado) async {
    setState(() {
      _accion = estado;
      _error = null;
    });
    try {
      final r = await widget.api.resolverCarga(widget.resumen.id, estado);
      if (mounted) setState(() => _resultado = r);
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sesionVencida) {
        volverAlInicio(context, widget.api, avisoSesionVencida);
        return;
      }
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _accion = null);
    }
  }

  Future<void> _salir() async {
    if (_resuelta) {
      Navigator.of(context).pop(true);
      return;
    }
    final descartar = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text('¿Salir sin confirmar?', style: Textos.tituloM()),
        content: Text(
            'Si sales ahora, la carga se descarta y no se guarda ningún precio. Podrás '
            'volver a subir el mismo archivo.',
            style: Textos.cuerpoM(Colores.textoMedio)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(contexto).pop(false),
              child: const Text('Seguir revisando')),
          TextButton(
              onPressed: () => Navigator.of(contexto).pop(true),
              child: const Text('Descartar y salir',
                  style: TextStyle(color: Colores.textoError))),
        ],
      ),
    );
    if (descartar != true || !mounted) return;
    await _resolver('descartada');
    if (_resuelta && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.resumen;
    final ocupado = _accion != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho && !ocupado) _salir();
      },
      child: MarcoPantalla(
        barra: BarraSuperior('Resumen de la carga', alVolver: ocupado ? null : _salir),
        contenido: [
          Tarjeta(
            hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.nombreArchivo, style: Textos.tituloM()),
              const SizedBox(height: 10),
              _Dato('Periodo',
                  c.desde == null ? '—' : '${fecha(c.desde!)} – ${fecha(c.hasta!)}'),
              const SizedBox(height: 6),
              _Dato('Fuente', c.fuente ?? '—'),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _Cifra(c.registrosValidos, 'Registros aceptados', Colores.textoPrimario)),
            const SizedBox(width: 12),
            Expanded(child: _Cifra(c.registrosRechazados, 'Rechazados', Colores.textoError)),
          ]),
          if (c.rechazos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Tarjeta(
              hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Motivo del rechazo', style: Textos.etiquetaM()),
                for (final r in c.rechazos)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(children: [
                      Expanded(child: Text(capitalizar(r.motivo), style: Textos.cuerpoS())),
                      Text(conMiles(r.cantidad), style: Textos.numeroM()),
                    ]),
                  ),
              ]),
            ),
          ],
          if (c.productosNuevos.isNotEmpty || c.variedadesNuevas.isNotEmpty) ...[
            const SizedBox(height: 12),
            Tarjeta(
              hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Se incorporará al catálogo', style: Textos.etiquetaM()),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in c.productosNuevos) _Chip('Producto: $p'),
                  for (final v in c.variedadesNuevas) _Chip(v),
                ]),
              ]),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Aviso(_error!.mensaje, detalles: _error!.detalles),
          ],
          if (_resultado != null) ...[
            const SizedBox(height: 12),
            Aviso(
              _resultado!.estado == 'confirmada'
                  // CU01, paso 13: el sistema informa que la carga se completó.
                  ? 'La carga se completó: se guardaron '
                      '${conMiles(_resultado!.preciosGuardados)} precios.'
                  : 'La carga se descartó. No se guardó ningún precio.',
              tipo: _resultado!.estado == 'confirmada' ? TipoAviso.exito : TipoAviso.informacion,
            ),
          ],
        ],
        pie: _resuelta
            ? BotonPrimario('Volver al menú',
                alPresionar: () => Navigator.of(context).pop(true))
            : Row(children: [
                Expanded(
                  child: BotonSecundario('Descartar',
                      alPresionar: ocupado ? null : () => _resolver('descartada')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BotonPrimario('Confirmar',
                      alPresionar: () => _resolver('confirmada'),
                      cargando: _accion == 'confirmada'),
                ),
              ]),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.rotulo, this.valor);
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(rotulo, style: Textos.cuerpoS())),
        Text(valor, style: Textos.cuerpoS(Colores.textoFuerte)),
      ]);
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.valor, this.rotulo, this.color);
  final int valor;
  final String rotulo;
  final Color color;

  @override
  Widget build(BuildContext context) => Tarjeta(
        hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(conMiles(valor), style: Textos.numeroXL(color)),
          const SizedBox(height: 2),
          Text(rotulo, style: Textos.cuerpoS()),
        ]),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: Colores.primarioSuave, borderRadius: BorderRadius.circular(6)),
        child: Text(texto, style: Textos.cuerpoS(Colores.textoPrimario)),
      );
}
