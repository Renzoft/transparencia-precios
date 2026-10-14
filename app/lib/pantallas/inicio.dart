// Las tres secciones de la aplicación, con cmp/Nav inferior: Precios, Mi lista y
// Mercados. Por ahora solo «Mi lista» (CU05) está construida; «Precios» es el CU04 y
// «Mercados» llega con él.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../lista.dart';
import '../tema.dart';
import 'mi_lista.dart';
import 'punto_de_partida.dart';
import 'resultado.dart';

class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key, required this.api, required this.lista});

  final ClienteApi api;
  final ListaCompras lista;

  @override
  State<PantallaInicio> createState() => _EstadoInicio();
}

class _EstadoInicio extends State<PantallaInicio> {
  int _seccion = 1;

  /// «Calcular costo total» (CU05, paso 5): lleva al punto de partida y el modo (C8).
  void _calcular() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PantallaPuntoDePartida(
          api: widget.api,
          alCalcular: (contexto, partida) => Navigator.of(contexto).push(
            MaterialPageRoute(
              builder: (_) => PantallaResultado(
                api: widget.api,
                items: widget.lista.items,
                partida: partida,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = NavInferior(
      seleccionada: _seccion,
      alElegir: (i) => setState(() => _seccion = i),
    );
    return switch (_seccion) {
      1 => VistaMiLista(
        api: widget.api,
        lista: widget.lista,
        navegacion: nav,
        alCalcular: _calcular,
      ),
      0 => _Proximamente(titulo: 'Consultar precios', navegacion: nav),
      _ => _Proximamente(titulo: 'Mercados', navegacion: nav),
    };
  }
}

class _Proximamente extends StatelessWidget {
  const _Proximamente({required this.titulo, required this.navegacion});

  final String titulo;
  final Widget navegacion;

  @override
  Widget build(BuildContext context) => MarcoPantalla(
    barra: BarraSuperior(titulo),
    navegacion: navegacion,
    contenido: const [
      Aviso('Esta sección estará disponible próximamente.', tipo: TipoAviso.informacion),
    ],
  );
}

/// cmp/Nav inferior.
class NavInferior extends StatelessWidget {
  const NavInferior({super.key, required this.seleccionada, required this.alElegir});

  final int seleccionada;
  final ValueChanged<int> alElegir;

  static const _opciones = [
    (Icons.search, 'Precios'),
    (Icons.format_list_bulleted, 'Mi lista'),
    (Icons.storefront_outlined, 'Mercados'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colores.superficie,
        border: Border(top: BorderSide(color: Colores.borde)),
        boxShadow: [
          BoxShadow(color: Color(0x140F1729), offset: Offset(0, -2), blurRadius: 5),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final (i, (icono, texto)) in _opciones.indexed)
                Expanded(
                  child: InkWell(
                    onTap: () => alElegir(i),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          Icon(
                            icono,
                            size: 24,
                            color: i == seleccionada
                                ? Colores.primario
                                : Colores.textoSuave,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            texto,
                            style: Textos.etiquetaS(
                              i == seleccionada
                                  ? Colores.textoPrimario
                                  : Colores.textoSuave,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
