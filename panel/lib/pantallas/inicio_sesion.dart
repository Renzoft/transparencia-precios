// A1 · Iniciar sesión y A2 · Credenciales no válidas (CU01, pasos 1 a 4 y EX1).
// Son la misma pantalla: A2 es A1 con el aviso de error.

import 'package:flutter/material.dart';

import '../api.dart';
import '../componentes.dart';
import '../tema.dart';
import 'menu.dart';

class PantallaInicioSesion extends StatefulWidget {
  const PantallaInicioSesion({super.key, required this.api, this.aviso});

  final ClienteApi api;

  /// Mensaje con que se abre la pantalla, por ejemplo cuando la sesión venció.
  final String? aviso;

  @override
  State<PantallaInicioSesion> createState() => _EstadoInicioSesion();
}

class _EstadoInicioSesion extends State<PantallaInicioSesion> {
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  bool _entrando = false;
  String? _error;
  List<String> _detalles = const [];

  @override
  void initState() {
    super.initState();
    _error = widget.aviso;
  }

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (_correo.text.trim().isEmpty || _contrasena.text.isEmpty) {
      setState(() {
        _error = 'Ingresa tu correo y tu contraseña.';
        _detalles = const [];
      });
      return;
    }
    setState(() {
      _entrando = true;
      _error = null;
      _detalles = const [];
    });
    try {
      await widget.api.iniciarSesion(_correo.text, _contrasena.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PantallaMenu(api: widget.api)));
    } on ErrorApi catch (e) {
      if (!mounted) return;
      setState(() {
        _entrando = false;
        // El 401 trae el mensaje literal de la EX1 del CU01; el 422, qué campo falló.
        _error = e.mensaje;
        _detalles = e.detalles;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MarcoPantalla(
      contenido: [
        const SizedBox(height: 48),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: Colores.primarioSuave, borderRadius: BorderRadius.circular(Radios.r16)),
            child: const Icon(Icons.storefront_outlined, color: Colores.primario, size: 30),
          ),
        ),
        const SizedBox(height: 20),
        Text('Transparencia de precios', style: Textos.tituloL(), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Panel de administración',
            style: Textos.cuerpoM(Colores.textoSuave), textAlign: TextAlign.center),
        const SizedBox(height: 36),
        const Rotulo('Correo electrónico'),
        AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Campo(
              controlador: _correo,
              sugerencia: 'Ingrese su correo',
              teclado: TextInputType.emailAddress,
              autocompletar: const [AutofillHints.email],
            ),
            const SizedBox(height: 16),
            const Rotulo('Contraseña'),
            Campo(
              controlador: _contrasena,
              oculto: true,
              alEnviar: (_) => _ingresar(),
              autocompletar: const [AutofillHints.password],
            ),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 18),
          Aviso(_error!, detalles: _detalles),
        ],
        const SizedBox(height: 18),
        BotonPrimario('Ingresar', alPresionar: _ingresar, cargando: _entrando),
        const SizedBox(height: 22),
        Text(
          'Solo el administrador necesita cuenta. El consumidor usa la aplicación sin '
          'registrarse.',
          style: Textos.cuerpoS(),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Vuelve al inicio de sesión cerrando todo lo abierto. Se usa cuando la API responde
/// 401 en medio del trabajo: el token venció a las ocho horas (RNF001).
void volverAlInicio(BuildContext context, ClienteApi api, String aviso) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => PantallaInicioSesion(api: api, aviso: aviso)),
    (_) => false,
  );
}

const avisoSesionVencida = 'Tu sesión venció. Vuelve a iniciar sesión.';
