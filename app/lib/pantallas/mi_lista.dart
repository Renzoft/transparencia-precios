// C6 · Mi lista de compras — vacía y C7 · Mi lista de compras (CU05, pasos 1 a 5).
//
// «−» en la cantidad mínima quita el producto de la lista, con la opción de deshacer.
// El prototipo no dibuja cómo se quita un producto; esta es la forma más directa con
// los mismos botones.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../lista.dart';
import '../tema.dart';
import 'agregar_producto.dart';

class VistaMiLista extends StatelessWidget {
  const VistaMiLista(
      {super.key, required this.api, required this.lista, this.navegacion, this.alCalcular});

  final ClienteApi api;
  final ListaCompras lista;
  final Widget? navegacion;

  /// «Calcular costo total» (CU05, paso 5).
  final VoidCallback? alCalcular;

  Future<void> _agregar(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaAgregarProducto(api: api, lista: lista)));

  void _restar(BuildContext context, ItemLista item) {
    final posicion = lista.posicion(item);
    final sale = item.cantidad - paso <= 0;
    lista.restar(item);
    if (!sale) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Se quitó ${item.nombre} de la lista'),
        action: SnackBarAction(
            label: 'Deshacer', onPressed: () => lista.reinsertar(posicion, item)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lista,
      builder: (context, _) =>
          lista.vacia ? _vacia(context) : _conProductos(context),
    );
  }

  /// C6.
  Widget _vacia(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondo,
      bottomNavigationBar: navegacion,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const BarraSuperior('Mi lista de compras'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Spacer(),
                Container(
                  width: 72,
                  height: 72,
                  color: Colores.borde,
                  child: const Icon(Icons.format_list_bulleted,
                      size: 32, color: Colores.textoSuave),
                ),
                const SizedBox(height: 12),
                Text('Tu lista está vacía', style: Textos.tituloL()),
                const SizedBox(height: 12),
                Text(
                  'Agrega los productos que quieres comprar y te diremos en qué mercado te '
                  'sale más barato, incluyendo el pasaje.',
                  style: Textos.cuerpoM(Colores.textoSuave),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: BotonPrimario('Agregar productos',
                      alPresionar: () => _agregar(context)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// C7.
  Widget _conProductos(BuildContext context) {
    final items = lista.items;
    return MarcoPantalla(
      barra: const BarraSuperior('Mi lista de compras'),
      navegacion: navegacion,
      contenido: [
        Row(children: [
          Expanded(
            child: Text(items.length == 1 ? '1 producto' : '${items.length} productos',
                style: Textos.etiquetaM()),
          ),
          Text('Guardada en este dispositivo', style: Textos.etiquetaS(Colores.textoSuave)),
        ]),
        const SizedBox(height: 12),
        for (final item in items) ...[
          Tarjeta(
            hijo: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.nombre, style: Textos.tituloM()),
                  const SizedBox(height: 2),
                  Text(cantidadConUnidad(item.cantidad, item.unidad),
                      style: Textos.cuerpoS()),
                ]),
              ),
              const SizedBox(width: 12),
              Contador(
                alRestar: () => _restar(context, item),
                alSumar: () => lista.sumar(item),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        BotonSecundario('Agregar otro producto', alPresionar: () => _agregar(context)),
      ],
      pie: SizedBox(
        width: double.infinity,
        child: BotonPrimario('Calcular costo total', alPresionar: alCalcular),
      ),
    );
  }
}
