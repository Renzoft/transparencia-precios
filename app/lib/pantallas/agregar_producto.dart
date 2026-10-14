// Agregar un producto a la lista (CU05, pasos 3 y 4): buscar el producto, elegir la
// variedad e indicar la cantidad en su unidad de medida.
//
// El prototipo del CU05 no tiene pantalla para esto (C7 solo muestra «Agregar otro
// producto»). Se armó con las piezas de las pantallas de consulta del CU04: la búsqueda
// y las tarjetas de productos de C1, y la lista de variedades de C2, sin los precios, que
// llegan con el CU04.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../lista.dart';
import '../tema.dart';

class PantallaAgregarProducto extends StatefulWidget {
  const PantallaAgregarProducto({super.key, required this.api, required this.lista});

  final ClienteApi api;
  final ListaCompras lista;

  @override
  State<PantallaAgregarProducto> createState() => _EstadoAgregar();
}

class _EstadoAgregar extends State<PantallaAgregarProducto> {
  final _busqueda = TextEditingController();
  List<Producto>? _productos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final productos = await widget.api.listarProductos();
      if (mounted) setState(() => _productos = productos);
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buscado = sinTildes(_busqueda.text);
    final productos = [
      for (final p in _productos ?? const <Producto>[])
        if (sinTildes(p.nombre).contains(buscado)) p
    ];
    return MarcoPantalla(
      barra: BarraSuperior('Agregar producto', alVolver: () => Navigator.of(context).pop()),
      contenido: [
        CampoBusqueda(
          controlador: _busqueda,
          sugerencia: 'Buscar un producto',
          alCambiar: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          Aviso(_error!),
          const SizedBox(height: 12),
          BotonSecundario('Reintentar', alPresionar: _cargar),
        ] else if (_productos == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: Colores.primario)),
          )
        else if (productos.isEmpty)
          Text('Ningún producto coincide con «${_busqueda.text.trim()}».',
              style: Textos.cuerpoS())
        else ...[
          Text('Productos de la canasta básica', style: Textos.etiquetaM()),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: 3.1,
            children: [
              for (final p in productos)
                Tarjeta(
                  relleno: const EdgeInsets.symmetric(horizontal: 12),
                  alPresionar: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PantallaVariedades(
                          api: widget.api, lista: widget.lista, producto: p))),
                  hijo: Row(children: [
                    Expanded(
                        child: Text(p.nombre,
                            style: Textos.tituloM(), overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.chevron_right, color: Colores.textoSuave, size: 20),
                  ]),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Las variedades de un producto. Al tocar una se indica la cantidad.
class PantallaVariedades extends StatefulWidget {
  const PantallaVariedades(
      {super.key, required this.api, required this.lista, required this.producto});

  final ClienteApi api;
  final ListaCompras lista;
  final Producto producto;

  @override
  State<PantallaVariedades> createState() => _EstadoVariedades();
}

class _EstadoVariedades extends State<PantallaVariedades> {
  List<Variedad>? _variedades;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final v = await widget.api.listarVariedades(widget.producto.id);
      if (mounted) setState(() => _variedades = v);
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _elegir(Variedad v) async {
    final agregado = await pedirCantidad(context, v, widget.lista.buscar(v.id)?.cantidad);
    if (agregado == null || !mounted) return;
    await widget.lista.poner(ItemLista(
        idVariedad: v.id,
        nombre: v.nombre,
        unidad: v.unidad,
        factorAKg: v.factorAKg,
        cantidad: agregado));
    // De vuelta a la lista, que muestra el total de productos (CU05, paso 4).
    if (mounted) Navigator.of(context).popUntil((ruta) => ruta.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final variedades = _variedades;
    return MarcoPantalla(
      barra: BarraSuperior(widget.producto.nombre,
          alVolver: () => Navigator.of(context).pop()),
      contenido: [
        if (_error != null) ...[
          Aviso(_error!),
          const SizedBox(height: 12),
          BotonSecundario('Reintentar', alPresionar: _cargar),
        ] else if (variedades == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: Colores.primario)),
          )
        else ...[
          Text(
              variedades.length == 1
                  ? '1 variedad disponible'
                  : '${variedades.length} variedades disponibles',
              style: Textos.etiquetaM()),
          const SizedBox(height: 12),
          for (final v in variedades) ...[
            ListenableBuilder(
              listenable: widget.lista,
              builder: (context, _) {
                final enLista = widget.lista.buscar(v.id);
                return Tarjeta(
                  alPresionar: () => _elegir(v),
                  hijo: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(v.nombre, style: Textos.tituloM()),
                        const SizedBox(height: 2),
                        Text(
                            enLista == null
                                ? 'Por ${v.unidad}'
                                : 'En tu lista: ${cantidadConUnidad(enLista.cantidad, v.unidad)}',
                            style: Textos.cuerpoS(enLista == null
                                ? Colores.textoSuave
                                : Colores.textoPrimario)),
                      ]),
                    ),
                    const Icon(Icons.add_circle_outline, color: Colores.primario),
                  ]),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

/// Hoja inferior para indicar la cantidad. Devuelve la cantidad elegida, o nada si se
/// cierra sin agregar.
Future<double?> pedirCantidad(BuildContext context, Variedad v, double? actual) {
  var cantidad = actual ?? 1.0;
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: Colores.superficie,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radios.r16))),
    builder: (contexto) => StatefulBuilder(
      builder: (contexto, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(v.nombre, style: Textos.tituloL()),
              const SizedBox(height: 4),
              Text('¿Cuánto vas a comprar?', style: Textos.cuerpoS()),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _BotonRedondo(Icons.remove, 'Restar',
                    cantidad > paso ? () => setState(() => cantidad -= paso) : null),
                SizedBox(
                  width: 120,
                  child: Text(cantidadConUnidad(cantidad, v.unidad),
                      style: Textos.numeroXL(), textAlign: TextAlign.center),
                ),
                _BotonRedondo(Icons.add, 'Sumar', () => setState(() => cantidad += paso)),
              ]),
              const SizedBox(height: 22),
              BotonPrimario(actual == null ? 'Agregar a la lista' : 'Actualizar cantidad',
                  alPresionar: () => Navigator.of(contexto).pop(cantidad)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo(this.icono, this.ayuda, this.alPresionar);

  final IconData icono;
  final String ayuda;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        onPressed: alPresionar,
        tooltip: ayuda,
        icon: Icon(icono, color: alPresionar == null ? Colores.bordeFuerte : Colores.primario),
        style: IconButton.styleFrom(
            side: const BorderSide(color: Colores.bordeFuerte),
            minimumSize: const Size(44, 44)),
      );
}
