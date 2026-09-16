import '../domain/leak_errors.dart';

/// Contrato de obtención de ubicación.
///
/// Desacopla el dominio del paquete `geolocator` para poder simular el
/// GPS en tests y sustituir/sumar MapLibre en sprints posteriores.
abstract class LocationService {
  /// Intenta obtener la posición actual.
  ///
  /// Lanza [LocationPermissionDeniedException], [LocationServiceOffException]
  /// o [LocationUnavailableException] según el motivo del fallo.
  Future<({double latitude, double longitude, double? accuracyMeters})>
  getCurrentPosition();
}
