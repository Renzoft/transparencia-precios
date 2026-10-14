// Componentes compartidos. Corresponden a los componentes de Figma (cmp/Barra superior,
// cmp/Boton primario, cmp/Boton secundario, cmp/Campo) y a los bloques que se repiten
// entre pantallas: tarjeta, avisos y el marco de cada pantalla.
//
// cmp/Barra de estado no se reproduce: es la del teléfono, y el panel es una aplicación
// web (Documento de Arquitectura, AD04).

import 'package:flutter/material.dart';

import 'tema.dart';

/// Ancho de la columna del panel. Los prototipos se dibujaron a 390 px; en el
/// navegador la misma columna se centra y crece un poco para leerse cómoda.
const anchoColumna = 440.0;

/// Una pantalla del panel: barra superior, contenido desplazable y pie fijo.
class MarcoPantalla extends StatelessWidget {
  const MarcoPantalla({super.key, this.barra, required this.contenido, this.pie});

  final Widget? barra;
  final List<Widget> contenido;
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.fondo,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: anchoColumna),
            child: Column(children: [
              ?barra,
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch, children: contenido),
                ),
              ),
              if (pie != null)
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: pie),
            ]),
          ),
        ),
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
      padding: EdgeInsets.only(left: alVolver == null ? 16 : 4, right: 16),
      child: Row(children: [
        if (alVolver != null)
          IconButton(
            tooltip: 'Volver',
            onPressed: alVolver,
            icon: const Icon(Icons.chevron_left, color: Colores.textoFuerte, size: 28),
          ),
        Expanded(child: Text(titulo, style: Textos.tituloM(), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// cmp/Boton primario.
class BotonPrimario extends StatelessWidget {
  const BotonPrimario(this.texto, {super.key, required this.alPresionar, this.cargando = false});

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
          disabledBackgroundColor: Colores.primario.withValues(alpha: cargando ? 0.85 : 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radios.r12)),
        ),
        child: cargando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colores.textoInverso))
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

/// Rótulo encima de un campo («Correo electrónico», «Fuente de los datos»).
class Rotulo extends StatelessWidget {
  const Rotulo(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto, style: Textos.etiquetaM()),
      );
}

/// Bordes de cmp/Campo, también usados por la lista desplegable de la fuente.
InputDecoration decoracionCampo({String? sugerencia}) {
  OutlineInputBorder borde(Color c, [double ancho = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radios.r12),
      borderSide: BorderSide(color: c, width: ancho));
  return InputDecoration(
    hintText: sugerencia,
    hintStyle: Textos.cuerpoM(Colores.textoSuave),
    filled: true,
    fillColor: Colores.superficie,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    enabledBorder: borde(Colores.bordeFuerte),
    focusedBorder: borde(Colores.primario, 1.5),
    border: borde(Colores.bordeFuerte),
  );
}

/// cmp/Campo.
class Campo extends StatelessWidget {
  const Campo({
    super.key,
    required this.controlador,
    this.sugerencia,
    this.oculto = false,
    this.teclado,
    this.alEnviar,
    this.autocompletar,
  });

  final TextEditingController controlador;
  final String? sugerencia;
  final bool oculto;
  final TextInputType? teclado;
  final ValueChanged<String>? alEnviar;
  final Iterable<String>? autocompletar;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controlador,
        obscureText: oculto,
        keyboardType: teclado,
        onSubmitted: alEnviar,
        autofillHints: autocompletar,
        style: Textos.cuerpoM(),
        decoration: decoracionCampo(sugerencia: sugerencia),
      );
}

/// Tarjeta blanca con la sombra del sistema.
class Tarjeta extends StatelessWidget {
  const Tarjeta({super.key, required this.hijo, this.relleno = const EdgeInsets.all(16)});

  final Widget hijo;
  final EdgeInsets relleno;

  @override
  Widget build(BuildContext context) => Container(
        padding: relleno,
        decoration: BoxDecoration(
          color: Colores.superficie,
          borderRadius: BorderRadius.circular(Radios.r16),
          boxShadow: sombraTarjeta,
        ),
        child: hijo,
      );
}

enum TipoAviso { error, informacion, exito }

/// Recuadro de aviso: el de «Usuario o contraseña incorrectos» (A2) y el informativo
/// de la carga (A4).
class Aviso extends StatelessWidget {
  const Aviso(this.texto, {super.key, this.tipo = TipoAviso.error, this.detalles = const []});

  final String texto;
  final TipoAviso tipo;
  final List<String> detalles;

  @override
  Widget build(BuildContext context) {
    final (fondo, color, icono) = switch (tipo) {
      TipoAviso.error => (Colores.errorSuave, Colores.textoError, Icons.warning_amber_rounded),
      TipoAviso.informacion => (Colores.infoSuave, Colores.textoMedio, Icons.info_outline),
      TipoAviso.exito => (Colores.primarioSuave, Colores.textoPrimario, Icons.check_circle_outline),
    };
    final colorIcono = tipo == TipoAviso.informacion ? Colores.info : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration:
          BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(Radios.r12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 20, color: colorIcono),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(texto, style: Textos.cuerpoS(color)),
            for (final d in detalles)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $d', style: Textos.cuerpoS(color)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// «1842» -> «1 842», como en los prototipos. Espacio duro para que no se parta.
String conMiles(int n) {
  final s = n.abs().toString();
  final grupos = <String>[];
  for (var fin = s.length; fin > 0; fin -= 3) {
    grupos.insert(0, s.substring(fin - 3 < 0 ? 0 : fin - 3, fin));
  }
  return (n < 0 ? '-' : '') + grupos.join(' ');
}

String fecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Primera letra en mayúscula: «duplicado» -> «Duplicado».
String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
