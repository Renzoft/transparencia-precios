// A6 · Mercados registrados y A8 · Desactivar mercado (CU02, pasos 1 a 3, FA1 y FA2), con
// la pestaña de A9 · Tarifas de desplazamiento (tarifas.dart).
//
// El prototipo no dibuja los botones «Editar» y «Desactivar» que nombran FA1 y FA2. Aquí
// aparecen al tocar un mercado de la lista, en un menú con esas dos opciones. Un mercado
// desactivado solo ofrece «Editar»: reactivarlo no forma parte del CU02.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import 'formulario_mercado.dart';
import 'inicio_sesion.dart';
import 'tarifas.dart';

class PantallaMercados extends StatefulWidget {
  const PantallaMercados({super.key, required this.api});
  final ClienteApi api;

  @override
  State<PantallaMercados> createState() => _EstadoMercados();
}

class _EstadoMercados extends State<PantallaMercados> {
  final _busqueda = TextEditingController();
  final _tarifas = GlobalKey<EstadoVistaTarifas>();
  final _guardandoTarifas = ValueNotifier(false);
  int _pestana = 0;
  List<Mercado>? _mercados;
  String? _error;
  String? _exito;

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _guardandoTarifas.dispose();
    super.dispose();
  }

  /// Atiende un error de la API: si la sesión venció, vuelve al inicio.
  bool _sesionVencida(ErrorApi e) {
    if (!e.sesionVencida) return false;
    volverAlInicio(context, widget.api, avisoSesionVencida);
    return true;
  }

  Future<void> _cargar() async {
    try {
      final mercados = await widget.api.listarMercados();
      if (mounted) setState(() => _mercados = mercados);
    } on ErrorApi catch (e) {
      if (!mounted || _sesionVencida(e)) return;
      setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrirFormulario([Mercado? mercado]) async {
    final mensaje = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PantallaFormularioMercado(api: widget.api, mercado: mercado),
      ),
    );
    if (mensaje == null || !mounted) return;
    setState(() {
      _exito = mensaje;
      _error = null;
    });
    _cargar();
  }

  Future<void> _desactivar(Mercado m) async {
    final confirmado = await confirmarDesactivacion(context, m);
    if (confirmado != true || !mounted) return;
    try {
      await widget.api.actualizarMercado(m.id, {'activo': false});
      if (!mounted) return;
      setState(() {
        _exito = 'Mercado desactivado';
        _error = null;
      });
      _cargar();
    } on ErrorApi catch (e) {
      if (!mounted || _sesionVencida(e)) return;
      setState(() {
        _exito = null;
        _error = e.mensaje;
      });
    }
  }

  Future<void> _opciones(Mercado m) async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colores.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radios.r16)),
      ),
      builder: (contexto) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(m.nombre, style: Textos.tituloM(), textAlign: TextAlign.center),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colores.textoFuerte),
              title: Text('Editar', style: Textos.cuerpoM()),
              onTap: () => Navigator.of(contexto).pop('editar'),
            ),
            if (m.activo)
              ListTile(
                leading: const Icon(Icons.block, color: Colores.textoError),
                title: Text('Desactivar', style: Textos.cuerpoM(Colores.textoError)),
                onTap: () => Navigator.of(contexto).pop('desactivar'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (opcion == 'editar') await _abrirFormulario(m);
    if (opcion == 'desactivar') await _desactivar(m);
  }

  List<Mercado> get _filtrados {
    final buscado = sinTildes(_busqueda.text);
    return [
      for (final m in _mercados ?? const <Mercado>[])
        if (buscado.isEmpty ||
            sinTildes(m.nombre).contains(buscado) ||
            sinTildes(m.distrito).contains(buscado))
          m,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final enMercados = _pestana == 0;
    return MarcoPantalla(
      barra: BarraSuperior(
        'Mercados y tarifas',
        alVolver: () => Navigator.of(context).pop(),
      ),
      contenido: [
        _Pestanas(seleccionada: _pestana, alCambiar: (i) => setState(() => _pestana = i)),
        const SizedBox(height: 14),
        if (enMercados)
          ..._listaMercados()
        else
          VistaTarifas(key: _tarifas, api: widget.api, guardando: _guardandoTarifas),
      ],
      pie: enMercados
          ? BotonPrimario('Nuevo mercado', alPresionar: () => _abrirFormulario())
          : ValueListenableBuilder<bool>(
              valueListenable: _guardandoTarifas,
              builder: (_, guardando, _) => BotonPrimario(
                'Guardar tarifas',
                alPresionar: () => _tarifas.currentState?.guardar(),
                cargando: guardando,
              ),
            ),
    );
  }

  List<Widget> _listaMercados() {
    final mercados = _mercados;
    return [
      TextField(
        controller: _busqueda,
        style: Textos.cuerpoM(),
        decoration: decoracionCampo(sugerencia: 'Buscar mercado').copyWith(
          prefixIcon: const Icon(Icons.search, color: Colores.textoSuave, size: 20),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      const SizedBox(height: 14),
      if (_exito != null) ...[
        Aviso(_exito!, tipo: TipoAviso.exito),
        const SizedBox(height: 14),
      ],
      if (_error != null) ...[Aviso(_error!), const SizedBox(height: 14)],
      if (mercados == null && _error == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: Colores.primario)),
        )
      else if (mercados != null && mercados.isEmpty)
        Text('Todavía no hay mercados registrados.', style: Textos.cuerpoS())
      else if (mercados != null && _filtrados.isEmpty)
        Text(
          'Ningún mercado coincide con «${_busqueda.text.trim()}».',
          style: Textos.cuerpoS(),
        )
      else
        for (final m in _filtrados)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TarjetaMercado(m, alPresionar: () => _opciones(m)),
          ),
    ];
  }
}

/// A8: pide confirmación y avisa qué pasa al desactivar (FA2, paso 2).
Future<bool?> confirmarDesactivacion(BuildContext context, Mercado m) => showDialog<bool>(
  context: context,
  barrierColor: const Color(0x73121726),
  builder: (contexto) => Dialog(
    backgroundColor: Colores.superficie,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.r14)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: anchoColumna - 48),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Desactivar mercado', style: Textos.tituloL()),
            const SizedBox(height: 14),
            Text(
              'El ${m.nombre} dejará de mostrarse al consumidor. Sus precios '
              'históricos se conservan.',
              style: Textos.cuerpoM(Colores.textoMedio),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: BotonSecundario(
                    'Cancelar',
                    alPresionar: () => Navigator.of(contexto).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BotonPrimario(
                    'Desactivar',
                    alPresionar: () => Navigator.of(contexto).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Selector «Mercados | Tarifas» del prototipo.
class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.seleccionada, required this.alCambiar});

  final int seleccionada;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    Widget pestana(int i, String texto) {
      final activa = i == seleccionada;
      return Expanded(
        child: Material(
          color: activa ? Colores.superficie : Colors.transparent,
          borderRadius: BorderRadius.circular(Radios.r8),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radios.r8),
            onTap: () => alCambiar(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(
                texto,
                textAlign: TextAlign.center,
                style: Textos.etiquetaM(
                  activa ? Colores.textoFuerte : Colores.textoSuave,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colores.borde,
        borderRadius: BorderRadius.circular(Radios.r12),
      ),
      child: Row(
        children: [
          pestana(0, 'Mercados'),
          const SizedBox(width: 4),
          pestana(1, 'Tarifas'),
        ],
      ),
    );
  }
}

class _TarjetaMercado extends StatelessWidget {
  const _TarjetaMercado(this.mercado, {required this.alPresionar});

  final Mercado mercado;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final m = mercado;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: alPresionar,
        borderRadius: BorderRadius.circular(Radios.r14),
        child: Container(
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
                    Text(m.nombre, style: Textos.tituloM()),
                    const SizedBox(height: 3),
                    Text(m.distrito, style: Textos.cuerpoS()),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                color: m.activo ? Colores.primarioSuave : Colores.borde,
                child: Text(
                  m.activo ? 'Activo' : 'Inactivo',
                  style: Textos.etiquetaS(
                    m.activo ? Colores.textoPrimario : Colores.textoSuave,
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
