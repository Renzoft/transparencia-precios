// Componentes compartidos. Corresponden a los componentes de Figma (cmp/Barra superior,
// cmp/Boton primario, cmp/Boton secundario, cmp/Nav inferior) y a los bloques que se
// repiten entre pantallas. cmp/Barra de estado no se reproduce: la dibuja el teléfono.

import 'package:flutter/material.dart';

import 'tema.dart';

/// Una pantalla: barra superior, contenido desplazable y pie fijo.
class MarcoPantalla extends StatelessWidget {
  const MarcoPantalla({
    super.key,
    this.barra,
    required this.contenido,
    this.pie,
    this.navegacion,
  });

  final Widget? barra;
  final List<Widget> contenido;
  final Widget? pie;
  final Widget? navegacion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondo,
      bottomNavigationBar: navegacion,
      body: SafeArea(
        bottom: navegacion == null,
        child: Column(children: [
          ?barra,
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: contenido),
            ),
          ),
          if (pie != null)
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: pie),
        ]),
      ),
    );
  }
}

/// cmp/Barra superior: título y, si corresponde, flecha para volver.
class BarraSuperior extends StatelessWidget {
  const BarraSuperior(this.titulo, {super.key, this.alVolver});

  final String titulo;
  final VoidCallback? alVolver;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Colores.superficie,
        border: Border(bottom: BorderSide(color: Colores.borde)),
      ),
      padding: EdgeInsets.only(left: alVolver == null ? 20 : 4, right: 16),
      child: Row(children: [
        if (alVolver != null)
          IconButton(
            tooltip: 'Volver',
            onPressed: alVolver,
            icon: const Icon(Icons.chevron_left, color: Colores.textoFuerte, size: 28),
          ),
        Expanded(
            child: Text(titulo, style: Textos.tituloM(), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// cmp/Boton primario.
class BotonPrimario extends StatelessWidget {
  const BotonPrimario(this.texto,
      {super.key, required this.alPresionar, this.cargando = false});

  final String texto;
  final VoidCallback? alPresionar;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final activo = alPresionar != null && !cargando;
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: activo ? alPresionar : null,
        style: FilledButton.styleFrom(
          backgroundColor: Colores.primario,
          disabledBackgroundColor:
              Colores.primario.withValues(alpha: cargando ? 0.85 : 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.r12)),
        ),
        child: cargando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colores.textoInverso))
            : Text(texto, style: Textos.botonM()),
      ),
    );
  }
}

/// cmp/Boton secundario.
class BotonSecundario extends StatelessWidget {
  const BotonSecundario(this.texto, {super.key, required this.alPresionar});

  final String texto;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: alPresionar,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colores.superficie,
          side: const BorderSide(color: Colores.bordeFuerte),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.r12)),
        ),
        child: Text(texto, style: Textos.botonM(Colores.textoFuerte)),
      ),
    );
  }
}

/// Tarjeta blanca con la sombra del sistema (radio de 14, como las de las listas).
class Tarjeta extends StatelessWidget {
  const Tarjeta(
      {super.key,
      required this.hijo,
      this.relleno = const EdgeInsets.all(14),
      this.alPresionar});

  final Widget hijo;
  final EdgeInsets relleno;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    final caja = Container(
      padding: relleno,
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(Radios.r14),
        boxShadow: sombraTarjeta,
      ),
      child: hijo,
    );
    if (alPresionar == null) return caja;
    return Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(Radios.r14),
          child: caja),
    );
  }
}

enum TipoAviso { error, informacion }

class Aviso extends StatelessWidget {
  const Aviso(this.texto, {super.key, this.tipo = TipoAviso.error});

  final String texto;
  final TipoAviso tipo;

  @override
  Widget build(BuildContext context) {
    final error = tipo == TipoAviso.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: error ? Colores.errorSuave : Colores.infoSuave,
          borderRadius: BorderRadius.circular(Radios.r12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 20, color: error ? Colores.textoError : Colores.info),
        const SizedBox(width: 10),
        Expanded(
            child: Text(texto,
                style: Textos.cuerpoS(error ? Colores.textoError : Colores.textoMedio))),
      ]),
    );
  }
}

/// Campo de búsqueda con lupa, como el de los prototipos.
class CampoBusqueda extends StatelessWidget {
  const CampoBusqueda(
      {super.key, required this.controlador, required this.sugerencia, this.alCambiar});

  final TextEditingController controlador;
  final String sugerencia;
  final ValueChanged<String>? alCambiar;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder borde(Color c, [double ancho = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.r12),
        borderSide: BorderSide(color: c, width: ancho));
    return TextField(
      controller: controlador,
      onChanged: alCambiar,
      style: Textos.cuerpoM(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: sugerencia,
        hintStyle: Textos.cuerpoM(Colores.textoSuave),
        prefixIcon: const Icon(Icons.search, color: Colores.textoSuave, size: 20),
        filled: true,
        fillColor: Colores.superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: borde(Colores.bordeFuerte),
        focusedBorder: borde(Colores.primario, 1.5),
        border: borde(Colores.bordeFuerte),
      ),
    );
  }
}

/// Botones «−» y «+» unidos, como en C7.
class Contador extends StatelessWidget {
  const Contador({super.key, required this.alRestar, required this.alSumar});

  final VoidCallback alRestar;
  final VoidCallback alSumar;

  @override
  Widget build(BuildContext context) {
    Widget boton(IconData icono, String ayuda, VoidCallback accion, {bool linea = false}) =>
        Container(
          decoration: linea
              ? const BoxDecoration(
                  border: Border(right: BorderSide(color: Colores.bordeFuerte)))
              : null,
          child: Tooltip(
            message: ayuda,
            child: InkWell(
              onTap: accion,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(icono, size: 16, color: Colores.primario),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: Colores.superficie,
        border: Border.all(color: Colores.bordeFuerte),
        borderRadius: BorderRadius.circular(Radios.r8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          boton(Icons.remove, 'Restar', alRestar, linea: true),
          boton(Icons.add, 'Sumar', alSumar),
        ]),
      ),
    );
  }
}

/// Para buscar sin que importen tildes ni mayúsculas: «Limón» -> «limon».
String sinTildes(String s) {
  const con = 'áéíóúüñ', sin = 'aeiouun';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = con.indexOf(c);
    b.write(i < 0 ? c : sin[i]);
  }
  return b.toString().trim();
}

/// Abreviatura de la unidad: «kilogramo» -> «kg», «litro» -> «L».
String abreviar(String unidad) => switch (unidad) {
      'kilogramo' => 'kg',
      'litro' => 'L',
      'unidad' => 'u',
      _ => unidad,
    };

/// «2.0 kg», con un decimal como en el prototipo.
String cantidadConUnidad(double cantidad, String unidad) =>
    '${cantidad.toStringAsFixed(1)} ${abreviar(unidad)}';

/// Primera letra en mayúscula: «transporte público» -> «Transporte público».
String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
