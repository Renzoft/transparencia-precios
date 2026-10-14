// A3 · Menú de administración (CU01, paso 4).
//
// Las opciones de Predicciones y Desempeño del modelo aparecen como en el prototipo, pero
// sin acción: se construyen en la actividad de implementación del CU03.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import 'carga_precios.dart';
import 'inicio_sesion.dart';
import 'mercados.dart';

class PantallaMenu extends StatefulWidget {
  const PantallaMenu({super.key, required this.api});
  final ClienteApi api;

  @override
  State<PantallaMenu> createState() => _EstadoMenu();
}

class _EstadoMenu extends State<PantallaMenu> {
  String? _ultimaCarga;

  @override
  void initState() {
    super.initState();
    _leerUltimaCarga();
  }

  Future<void> _leerUltimaCarga() async {
    try {
      final cargas = await widget.api.listarCargas(limite: 20);
      final confirmada = cargas.where((c) => c.estado == 'confirmada').firstOrNull;
      if (!mounted) return;
      setState(() {
        // La API no expone la fecha en que se subió el archivo; lo que sí se sabe, y
        // es lo que le importa al administrador, es hasta qué fecha llegan los datos.
        _ultimaCarga = confirmada == null
            ? 'Todavía no hay cargas confirmadas'
            : 'Última carga: datos al ${confirmada.hasta == null ? '—' : fecha(confirmada.hasta!)}'
                ' · ${conMiles(confirmada.registrosValidos)} registros';
      });
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sesionVencida) {
        volverAlInicio(context, widget.api, avisoSesionVencida);
        return;
      }
      setState(() => _ultimaCarga = e.mensaje);
    }
  }

  Future<void> _abrirCarga() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PantallaCargaPrecios(api: widget.api)));
    // Al volver puede haber una carga nueva confirmada.
    if (mounted) _leerUltimaCarga();
  }

  @override
  Widget build(BuildContext context) {
    final nombre = (widget.api.usuario?.nombre ?? '').split(' ').first;
    return MarcoPantalla(
      barra: const BarraSuperior('Administración'),
      contenido: [
        Text('Hola, $nombre', style: Textos.tituloL()),
        const SizedBox(height: 4),
        Text(_ultimaCarga ?? 'Consultando la última carga…', style: Textos.cuerpoS()),
        const SizedBox(height: 18),
        _Opcion(
          icono: Icons.file_upload_outlined,
          titulo: 'Carga de precios',
          descripcion: 'Subir el archivo del SISAP y validarlo',
          alPresionar: _abrirCarga,
        ),
        _Opcion(
          icono: Icons.storefront_outlined,
          titulo: 'Mercados y tarifas',
          descripcion: 'Registrar mercados y actualizar tarifas',
          alPresionar: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => PantallaMercados(api: widget.api))),
        ),
        const _Opcion(
          icono: Icons.trending_up,
          titulo: 'Predicciones',
          descripcion: 'Ejecutar el modelo sobre los datos validados',
        ),
        const _Opcion(
          icono: Icons.bar_chart,
          titulo: 'Desempeño del modelo',
          descripcion: 'Revisar MAE, WAPE, MASE y exactitud direccional',
        ),
      ],
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion(
      {required this.icono, required this.titulo, required this.descripcion, this.alPresionar});

  final IconData icono;
  final String titulo;
  final String descripcion;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    final disponible = alPresionar != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: disponible ? 1 : 0.55,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: alPresionar,
            borderRadius: BorderRadius.circular(Radios.r16),
            child: Tarjeta(
              hijo: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: Colores.primarioSuave,
                      borderRadius: BorderRadius.circular(Radios.r12)),
                  child: Icon(icono, color: Colores.primario, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titulo, style: Textos.tituloM()),
                    const SizedBox(height: 2),
                    Text(disponible ? descripcion : '$descripcion · próximamente',
                        style: Textos.cuerpoS()),
                  ]),
                ),
                if (disponible) const Icon(Icons.chevron_right, color: Colores.textoSuave),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
