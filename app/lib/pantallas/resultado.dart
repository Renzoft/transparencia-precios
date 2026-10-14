// C9 · Calculando el costo y C10 · Resultado por mercado (CU05, pasos 9 a 13; EX3, EX4).
//
// Diferencias con el prototipo, y por qué:
//  - C9 no muestra la lista de pasos («Mercados cercanos encontrados: 4», …). El cálculo
//    es una sola consulta a la API y no informa su avance; mostrar esos pasos sería
//    inventarlo.
//  - «Más barato» solo se marca si ese mercado tiene precio para toda la lista: uno al que
//    le faltan precios no es el más barato, solo le falta sumar productos. Por lo mismo,
//    la diferencia «+ S/ …» solo se muestra entre mercados con la lista completa.
//  - El aviso de distancia aproximada dice solo eso, sin «el servicio de rutas no
//    respondió»: la API no dice por qué fue en línea recta (puede no tener clave
//    configurada, o el servicio no tener ruta hasta algún mercado).
//  - «Ver comparación y recomendación» lleva al CU06, que aún no se construye; el botón
//    no aparece.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../lista.dart';
import '../tema.dart';
import 'punto_de_partida.dart';

const mensajeSinMercados = 'No se encontraron mercados cercanos'; // EX3

class PantallaResultado extends StatefulWidget {
  const PantallaResultado({
    super.key,
    required this.api,
    required this.items,
    required this.partida,
  });

  final ClienteApi api;
  final List<ItemLista> items;
  final Partida partida;

  @override
  State<PantallaResultado> createState() => _EstadoResultado();
}

class _EstadoResultado extends State<PantallaResultado> {
  Comparacion? _resultado;
  String? _error;

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  Future<void> _calcular() async {
    setState(() {
      _resultado = null;
      _error = null;
    });
    final p = widget.partida;
    try {
      final r = await widget.api.comparar(
        latitud: p.origen.latitud,
        longitud: p.origen.longitud,
        idModo: p.modo.id,
        radioKm: p.radioKm,
        items: [
          for (final i in widget.items)
            (idVariedad: i.idVariedad, cantidadKg: i.cantidadKg),
        ],
      );
      if (mounted) setState(() => _resultado = r);
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  void _volver() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    if (_error != null) return _conError();
    if (r == null) return _calculando();
    if (r.mercados.isEmpty) return _sinMercados();
    return _resultadoPorMercado(r);
  }

  /// C9.
  Widget _calculando() => MarcoPantalla(
    barra: BarraSuperior('Calcular costo total', alVolver: _volver),
    contenido: [
      const SizedBox(height: 160),
      const Center(
        child: SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 4, color: Colores.primario),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Calculando tu costo total',
        style: Textos.tituloL(),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Text(
        'Estamos consultando la distancia hasta cada mercado cercano.',
        style: Textos.cuerpoM(Colores.textoSuave),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _conError() => MarcoPantalla(
    barra: BarraSuperior('Calcular costo total', alVolver: _volver),
    contenido: [Aviso(_error!)],
    pie: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: BotonPrimario('Volver a intentar', alPresionar: _calcular),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: BotonSecundario('Volver', alPresionar: _volver),
        ),
      ],
    ),
  );

  /// EX3: sin mercados en el radio; se sugiere ampliarlo.
  Widget _sinMercados() => MarcoPantalla(
    barra: BarraSuperior('Costo total de tu compra', alVolver: _volver),
    contenido: [
      const SizedBox(height: 140),
      const Icon(Icons.storefront_outlined, size: 40, color: Colores.textoSuave),
      const SizedBox(height: 12),
      Text(mensajeSinMercados, style: Textos.tituloL(), textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text(
        'No hay mercados registrados a menos de ${widget.partida.radioKm} km de tu '
        'punto de partida. Amplía el radio de búsqueda.',
        style: Textos.cuerpoM(Colores.textoSuave),
        textAlign: TextAlign.center,
      ),
    ],
    pie: SizedBox(
      width: double.infinity,
      child: BotonPrimario('Ampliar el radio', alPresionar: _volver),
    ),
  );

  /// C10.
  Widget _resultadoPorMercado(Comparacion r) {
    final mercados = r.mercados;
    final nombres = {for (final i in widget.items) i.idVariedad: i.nombre};
    final mayor = mercados.map((m) => m.costoTotal).reduce((a, b) => a > b ? a : b);
    final primero = mercados.first;
    final hayMasBarato = primero.listaCompleta;
    final n = widget.items.length;
    return MarcoPantalla(
      barra: BarraSuperior('Costo total de tu compra', alVolver: _volver),
      contenido: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${n == 1 ? '1 producto' : '$n productos'} · '
                '${mercados.length == 1 ? '1 mercado' : '${mercados.length} mercados'} '
                'en ${widget.partida.radioKm} km',
                style: Textos.etiquetaM(),
              ),
            ),
            Text(
              capitalizar(widget.partida.modo.nombre),
              style: Textos.etiquetaS(Colores.textoSuave),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (r.distanciaAproximada) ...[
          const _AvisoAlerta('Las distancias son aproximadas, en línea recta.'),
          const SizedBox(height: 12),
        ],
        for (final (i, m) in mercados.indexed) ...[
          _TarjetaMercado(
            m,
            masBarato: i == 0 && hayMasBarato,
            diferencia: i > 0 && hayMasBarato && m.listaCompleta
                ? m.costoTotal - primero.costoTotal
                : null,
            mayorTotal: mayor,
            sinPrecio: [for (final id in m.sinPrecio) nombres[id] ?? 'producto $id'],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

String soles(double x) => 'S/ ${x.toStringAsFixed(2)}';

class _AvisoAlerta extends StatelessWidget {
  const _AvisoAlerta(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colores.alertaSuave,
      borderRadius: BorderRadius.circular(Radios.r12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 20, color: Colores.alerta),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: Textos.cuerpoS(Colores.textoAlerta))),
      ],
    ),
  );
}

class _TarjetaMercado extends StatelessWidget {
  const _TarjetaMercado(
    this.m, {
    required this.masBarato,
    required this.diferencia,
    required this.mayorTotal,
    required this.sinPrecio,
  });

  final MercadoComparado m;
  final bool masBarato;
  final double? diferencia;
  final double mayorTotal;
  final List<String> sinPrecio;

  @override
  Widget build(BuildContext context) {
    final detalle = [
      m.distrito,
      '${m.distanciaKm.toStringAsFixed(1)} km',
      if (m.duracionMin != null) '${m.duracionMin} min',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: masBarato ? Colores.primarioSuave : Colores.superficie,
        borderRadius: BorderRadius.circular(Radios.r14),
        border: masBarato ? Border.all(color: Colores.primario, width: 1.5) : null,
        boxShadow: masBarato ? null : sombraTarjeta,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (masBarato) ...[
            Container(
              color: Colores.primario,
              padding: const EdgeInsets.fromLTRB(9, 4, 10, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check, size: 13, color: Colores.textoInverso),
                  const SizedBox(width: 5),
                  Text('Más barato', style: Textos.etiquetaS(Colores.textoInverso)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nombre, style: Textos.tituloM()),
                    const SizedBox(height: 3),
                    Text(detalle, style: Textos.etiquetaS(Colores.textoSuave)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    soles(m.costoTotal),
                    style: Textos.numeroXL(
                      masBarato ? Colores.textoPrimario : Colores.textoFuerte,
                    ),
                  ),
                  if (masBarato)
                    Text('el más barato', style: Textos.etiquetaS(Colores.textoPrimario))
                  else if (diferencia != null)
                    Text(
                      '+ ${soles(diferencia!)}',
                      style: Textos.etiquetaS(Colores.textoSuave),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BarraComposicion(m, mayorTotal),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Leyenda(Colores.primario, 'Productos  ${soles(m.costoProductos)}'),
              _Leyenda(Colores.alerta, 'Desplazamiento  ${soles(m.costoDesplazamiento)}'),
            ],
          ),
          if (sinPrecio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Sin precio en este mercado: ${sinPrecio.join(', ')}',
              style: Textos.etiquetaS(Colores.textoAlerta),
            ),
          ],
        ],
      ),
    );
  }
}

/// La barra del prototipo: productos en verde y desplazamiento en ámbar. Su largo es
/// proporcional al costo total, para comparar los mercados de un vistazo.
class _BarraComposicion extends StatelessWidget {
  const _BarraComposicion(this.m, this.mayorTotal);

  final MercadoComparado m;
  final double mayorTotal;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final escala = mayorTotal <= 0 ? 0.0 : c.maxWidth / mayorTotal;
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 10,
          color: Colores.barraComparacion,
          child: Row(
            children: [
              Container(width: m.costoProductos * escala, color: Colores.primario),
              Container(width: m.costoDesplazamiento * escala, color: Colores.alerta),
            ],
          ),
        ),
      );
    },
  );
}

class _Leyenda extends StatelessWidget {
  const _Leyenda(this.color, this.texto);

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(texto, style: Textos.etiquetaS(Colores.textoMedio)),
    ],
  );
}
