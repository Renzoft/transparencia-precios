// Ingresar una dirección de partida (CU05, EX2; R12). Se abre desde C8 cuando el
// consumidor no autoriza el GPS, o cuando prefiere salir desde otro lugar.
//
// El prototipo no tiene esta pantalla (C8 solo muestra el enlace «Usar otra
// dirección»); se armó con el campo de búsqueda y las tarjetas de las demás pantallas.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';

class PantallaDireccion extends StatefulWidget {
  const PantallaDireccion({super.key, required this.api});
  final ClienteApi api;

  @override
  State<PantallaDireccion> createState() => _EstadoDireccion();
}

class _EstadoDireccion extends State<PantallaDireccion> {
  final _texto = TextEditingController();
  bool _buscando = false;
  List<Direccion>? _encontradas;
  String? _error;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final texto = _texto.text.trim();
    if (texto.length < 3) {
      setState(() => _error = 'Escribe la dirección con al menos 3 caracteres.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _buscando = true;
      _error = null;
      _encontradas = null;
    });
    try {
      final r = await widget.api.buscarDirecciones(texto);
      if (mounted) setState(() => _encontradas = r);
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final encontradas = _encontradas;
    return MarcoPantalla(
      barra: BarraSuperior(
        'Punto de partida',
        alVolver: () => Navigator.of(context).pop(),
      ),
      contenido: [
        Text('¿Desde dónde saldrás?', style: Textos.etiquetaM()),
        const SizedBox(height: 10),
        TextField(
          controller: _texto,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _buscar(),
          style: Textos.cuerpoM(),
          decoration: InputDecoration(
            hintText: 'Calle y número, distrito',
            hintStyle: Textos.cuerpoM(Colores.textoSuave),
            prefixIcon: const Icon(
              Icons.location_on_outlined,
              color: Colores.textoSuave,
              size: 20,
            ),
            filled: true,
            fillColor: Colores.superficie,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radios.r12),
              borderSide: const BorderSide(color: Colores.bordeFuerte),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radios.r12),
              borderSide: const BorderSide(color: Colores.primario, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tu dirección solo se usa para este cálculo y no se guarda en el servidor.',
          style: Textos.etiquetaS(Colores.textoSuave),
        ),
        const SizedBox(height: 18),
        if (_error != null) Aviso(_error!),
        if (encontradas != null && encontradas.isEmpty)
          const Aviso(
            'No encontramos esa dirección en Lima Metropolitana. Prueba agregando el '
            'distrito.',
            tipo: TipoAviso.informacion,
          ),
        if (encontradas != null && encontradas.isNotEmpty) ...[
          Text('Elige tu punto de partida', style: Textos.etiquetaM()),
          const SizedBox(height: 10),
          for (final d in encontradas) ...[
            Tarjeta(
              alPresionar: () => Navigator.of(context).pop(d),
              hijo: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Colores.primario,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(d.etiqueta, style: Textos.cuerpoM())),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
      pie: SizedBox(
        width: double.infinity,
        child: BotonPrimario('Buscar', alPresionar: _buscar, cargando: _buscando),
      ),
    );
  }
}
