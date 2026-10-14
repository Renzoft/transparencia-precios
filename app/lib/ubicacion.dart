// Ubicación del consumidor por GPS, previo consentimiento (CU05, paso 6; EX2).
//
// La ubicación se usa solo para el cálculo y no se guarda en el servidor (RNF003). La
// aplicación tampoco la guarda: se pide cada vez.

import 'package:geolocator/geolocator.dart';

/// Coordenadas del punto de partida.
class Punto {
  const Punto(this.latitud, this.longitud);
  final double latitud;
  final double longitud;
}

/// Por qué no se obtuvo la ubicación. Cada caso se le explica distinto al consumidor.
enum FallaUbicacion {
  gpsApagado,          // el servicio de ubicación del teléfono está desactivado
  sinPermiso,          // el consumidor no autorizó (EX2)
  sinPermisoSiempre,   // eligió «no volver a preguntar»: hay que ir a Ajustes
  sinRespuesta,        // el GPS no respondió a tiempo
}

class ResultadoUbicacion {
  const ResultadoUbicacion.ok(Punto this.punto) : falla = null;
  const ResultadoUbicacion.falla(FallaUbicacion this.falla) : punto = null;

  final Punto? punto;
  final FallaUbicacion? falla;
}

/// Se inyecta en la pantalla para poder probarla sin un GPS de verdad.
typedef ObtenerUbicacion = Future<ResultadoUbicacion> Function();

Future<ResultadoUbicacion> ubicacionDelGps() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return const ResultadoUbicacion.falla(FallaUbicacion.gpsApagado);
  }
  var permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied) {
    // Aquí el teléfono le pregunta al consumidor si autoriza (consentimiento).
    permiso = await Geolocator.requestPermission();
  }
  if (permiso == LocationPermission.deniedForever) {
    return const ResultadoUbicacion.falla(FallaUbicacion.sinPermisoSiempre);
  }
  if (permiso == LocationPermission.denied || permiso == LocationPermission.unableToDetermine) {
    return const ResultadoUbicacion.falla(FallaUbicacion.sinPermiso);
  }
  try {
    final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    return ResultadoUbicacion.ok(Punto(p.latitude, p.longitude));
  } catch (_) {
    return const ResultadoUbicacion.falla(FallaUbicacion.sinRespuesta);
  }
}

/// Abre los ajustes del teléfono para activar el GPS o dar el permiso.
Future<void> abrirAjustes(FallaUbicacion falla) => falla == FallaUbicacion.gpsApagado
    ? Geolocator.openLocationSettings()
    : Geolocator.openAppSettings();
