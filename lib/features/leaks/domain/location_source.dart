/// Fuente de la ubicación de un reporte.
enum LocationSource { gps, manual }

LocationSource locationSourceFromString(String value) {
  switch (value) {
    case 'GPS':
      return LocationSource.gps;
    case 'MANUAL':
      return LocationSource.manual;
    default:
      throw ArgumentError.value(value, 'value', 'location_source inválido');
  }
}

extension LocationSourceLabel on LocationSource {
  String get wireName => this == LocationSource.gps ? 'GPS' : 'MANUAL';

  /// Etiqueta visible para el usuario (UX_SPEC §4: siempre saber si la
  /// ubicación es GPS o manual).
  String get label => this == LocationSource.gps
      ? 'Ubicación por GPS'
      : 'Ubicación manual';
}
