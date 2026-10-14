// A4 · Carga de precios (CU01, pasos 5 a 9, EX2 y EX3).
//
// El aviso informativo no es el del prototipo. El prototipo decía que el archivo trae
// «fecha, producto, variedad, mercado, precio y unidad» y mostraba un .xlsx; con los
// archivos reales del SISAP se comprobó que el de ciudades no trae producto ni mercado y
// que la extensión es .xls. Se reemplazó por lo que el administrador necesita saber.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import 'inicio_sesion.dart';
import 'resumen_carga.dart';

class ArchivoElegido {
  ArchivoElegido(this.nombre, this.contenido);
  final String nombre;
  final Uint8List contenido;
}

/// Abre el selector de archivos del navegador. Se inyecta para poder probar la
/// pantalla sin un navegador de verdad.
typedef ElegirArchivo = Future<ArchivoElegido?> Function();

Future<ArchivoElegido?> elegirArchivoDelSistema() async {
  // file_picker 13: un solo archivo con pickFile; el contenido se lee aparte.
  final f = await FilePicker.pickFile(
      type: FileType.custom, allowedExtensions: const ['xls']);
  if (f == null) return null;
  return ArchivoElegido(f.name, await f.readAsBytes());
}

/// Las fuentes con un formato de archivo definido. «Precios por mercado» no aparece:
/// todavía no hay un archivo real de esa fuente con el que definir su formato.
const fuentes = ['SISAP minorista', 'SISAP mayorista'];

class PantallaCargaPrecios extends StatefulWidget {
  const PantallaCargaPrecios(
      {super.key, required this.api, this.elegirArchivo = elegirArchivoDelSistema});

  final ClienteApi api;
  final ElegirArchivo elegirArchivo;

  @override
  State<PantallaCargaPrecios> createState() => _EstadoCargaPrecios();
}

class _EstadoCargaPrecios extends State<PantallaCargaPrecios> {
  String _fuente = fuentes.first;
  ArchivoElegido? _archivo;
  bool _subiendo = false;
  ErrorApi? _error;

  Future<void> _elegir() async {
    final a = await widget.elegirArchivo();
    if (a != null && mounted) {
      setState(() {
        _archivo = a;
        _error = null;
      });
    }
  }

  Future<void> _cargar() async {
    final archivo = _archivo;
    if (archivo == null) return;
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      final resumen = await widget.api.subirCarga(archivo.contenido, archivo.nombre, _fuente);
      if (!mounted) return;
      setState(() => _subiendo = false);
      final resuelta = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => PantallaResumenCarga(api: widget.api, resumen: resumen)));
      // Si la carga se resolvió, esta pantalla ya cumplió: se vuelve al menú.
      if (resuelta == true && mounted) Navigator.of(context).pop();
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sesionVencida) {
        volverAlInicio(context, widget.api, avisoSesionVencida);
        return;
      }
      setState(() {
        _subiendo = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final archivo = _archivo;
    return MarcoPantalla(
      barra: BarraSuperior('Carga de precios', alVolver: () => Navigator.of(context).pop()),
      contenido: [
        const Rotulo('Fuente de los datos'),
        DropdownButtonFormField<String>(
          initialValue: _fuente,
          items: [
            for (final f in fuentes)
              DropdownMenuItem(value: f, child: Text(f, style: Textos.cuerpoM()))
          ],
          onChanged: _subiendo ? null : (f) => setState(() => _fuente = f ?? _fuente),
          decoration: decoracionCampo(),
          borderRadius: BorderRadius.circular(Radios.r12),
        ),
        const SizedBox(height: 16),
        _ZonaArchivo(archivo: archivo, alPresionar: _subiendo ? null : _elegir),
        const SizedBox(height: 16),
        const Aviso(
          'Exporta el archivo desde el portal del SISAP con «Herramientas → Exportar a '
          'Excel», con una sola variedad, y súbelo sin abrirlo ni guardarlo en Excel. '
          'No marques «Transformar unidad de medida a kilogramo». Si vas a subir los dos '
          'archivos de las mismas fechas, sube primero el del módulo mayorista, que trae '
          'el volumen.',
          tipo: TipoAviso.informacion,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Aviso(_error!.mensaje, detalles: _error!.detalles),
        ],
      ],
      pie: BotonPrimario('Cargar y validar',
          alPresionar: archivo == null ? null : _cargar, cargando: _subiendo),
    );
  }
}

/// El recuadro punteado donde se elige el archivo.
class _ZonaArchivo extends StatelessWidget {
  const _ZonaArchivo({required this.archivo, required this.alPresionar});

  final ArchivoElegido? archivo;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    final a = archivo;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: alPresionar,
        borderRadius: BorderRadius.circular(Radios.r12),
        child: CustomPaint(
          painter: _BordePunteado(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: a == null ? Colores.superficie : Colores.primarioSuave,
              borderRadius: BorderRadius.circular(Radios.r12),
            ),
            child: Column(children: [
              const Icon(Icons.file_upload_outlined, color: Colores.primario, size: 28),
              const SizedBox(height: 10),
              Text(a?.nombre ?? 'Seleccionar archivo',
                  style: Textos.tituloM(), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                a == null
                    ? 'Archivo .xls exportado del SISAP'
                    : '${conMiles((a.contenido.length / 1024).ceil())} KB · seleccionado',
                style: Textos.cuerpoS(),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BordePunteado extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = Colores.primario
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final contorno = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(Radios.r12)));
    for (final metrica in contorno.computeMetrics()) {
      for (var d = 0.0; d < metrica.length; d += 9) {
        canvas.drawPath(metrica.extractPath(d, d + 5), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
