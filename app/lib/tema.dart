// Sistema visual de la aplicación, tomado de las variables y estilos de los prototipos
// en Figma (archivo «Prototipos UX-UI — Transparencia de precios»). Es el mismo del
// panel de administración (panel/lib/tema.dart): los dos salen de las mismas variables.
// Los nombres siguen los de Figma: color/texto-fuerte pasa a Colores.textoFuerte.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// En las pruebas se desactiva: la tipografía Inter se descarga de internet y una
/// prueba no debe depender de la red.
bool usarInter = true;

class Colores {
  static const textoFuerte = Color(0xFF111827);
  static const textoMedio = Color(0xFF4B5563);
  static const textoSuave = Color(0xFF6B7280);
  static const textoInverso = Color(0xFFFFFFFF);
  static const textoPrimario = Color(0xFF15803D);
  static const textoError = Color(0xFFB42318);
  static const primario = Color(0xFF15803D);
  static const primarioSuave = Color(0xFFECFDF3);
  static const errorSuave = Color(0xFFFEF3F2);
  static const infoSuave = Color(0xFFEFF6FF);
  // El ícono del aviso informativo no usa una variable en Figma; es el azul de su trazo.
  static const info = Color(0xFF2563EB);
  static const fondo = Color(0xFFF7F8FA);
  static const superficie = Color(0xFFFFFFFF);
  static const borde = Color(0xFFE5E7EB);
  static const bordeFuerte = Color(0xFFD1D5DB);
}

class Radios {
  static const r8 = 8.0;
  static const r12 = 12.0;
  static const r14 = 14.0;
  static const r16 = 16.0;
}

/// Sombra/Tarjeta de Figma: dos sombras suaves superpuestas.
const sombraTarjeta = [
  BoxShadow(color: Color(0x0A0F1729), offset: Offset(0, 1), blurRadius: 2),
  BoxShadow(
      color: Color(0x120F1729), offset: Offset(0, 4), blurRadius: 12, spreadRadius: -2),
];

TextStyle _inter(double tamano, FontWeight peso, double interlineado, Color color) {
  final altura = interlineado / tamano;
  if (!usarInter) {
    return TextStyle(fontSize: tamano, fontWeight: peso, height: altura, color: color);
  }
  return GoogleFonts.inter(fontSize: tamano, fontWeight: peso, height: altura, color: color);
}

/// Estilos de texto de Figma: tamaño, peso e interlineado exactos.
class Textos {
  static TextStyle tituloL([Color c = Colores.textoFuerte]) =>
      _inter(20, FontWeight.w600, 28, c);
  static TextStyle tituloM([Color c = Colores.textoFuerte]) =>
      _inter(17, FontWeight.w600, 24, c);
  static TextStyle cuerpoM([Color c = Colores.textoFuerte]) =>
      _inter(15, FontWeight.w400, 22, c);
  static TextStyle cuerpoS([Color c = Colores.textoSuave]) =>
      _inter(13, FontWeight.w400, 18, c);
  static TextStyle etiquetaM([Color c = Colores.textoMedio]) =>
      _inter(13, FontWeight.w500, 18, c);
  static TextStyle etiquetaS([Color c = Colores.textoMedio]) =>
      _inter(11, FontWeight.w500, 16, c);
  static TextStyle botonM([Color c = Colores.textoInverso]) =>
      _inter(15, FontWeight.w600, 20, c);
  static TextStyle numeroXL([Color c = Colores.textoFuerte]) =>
      _inter(28, FontWeight.w700, 34, c);
  static TextStyle numeroM([Color c = Colores.textoFuerte]) =>
      _inter(17, FontWeight.w600, 24, c);
}

ThemeData temaApp() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Colores.fondo,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colores.primario,
      primary: Colores.primario,
      error: Colores.textoError,
      surface: Colores.superficie,
    ),
  );
  return usarInter
      ? base.copyWith(textTheme: GoogleFonts.interTextTheme(base.textTheme))
      : base;
}
