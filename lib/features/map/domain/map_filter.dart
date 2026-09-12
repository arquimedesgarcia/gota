/// Filtros oficiales de Sprint 05 (Map) definidos en FUNCTIONAL_SPEC §7.
///
/// Modos:
/// - Mapa;
/// - Lista.
///
/// Filtros:
/// - Todas;
/// - Activas;
/// - Resueltas;
/// - Mi sector;
/// - Recientes;
/// - Más validadas.
library;

/// Modo de visualización: Mapa o Lista (§12).
enum MapViewMode {
  map('Mapa'),
  list('Lista');

  const MapViewMode(this.label);
  final String label;
}

/// Tipo de filtro aprobado para el mapa/lista (§10).
enum MapFilterType {
  all('Todas'),
  active('Activas'),
  resolved('Resueltas'),
  mySector('Mi sector'),
  recent('Recientes'),
  mostValidated('Más validadas');

  const MapFilterType(this.label);
  final String label;
}

/// Estado inmutable de los filtros y vista del mapa.
class MapFilterState {
  const MapFilterState({
    this.filterType = MapFilterType.all,
    this.viewMode = MapViewMode.map,
    this.selectedSectorId,
    this.userLatitude,
    this.userLongitude,
  });

  final MapFilterType filterType;
  final MapViewMode viewMode;

  /// Sector específico si se activó el filtro "Mi sector".
  final String? selectedSectorId;

  /// Coordenadas del usuario si concedió permiso GPS (§13).
  final double? userLatitude;
  final double? userLongitude;

  bool get hasUserLocation => userLatitude != null && userLongitude != null;

  MapFilterState copyWith({
    MapFilterType? filterType,
    MapViewMode? viewMode,
    String? selectedSectorId,
    double? userLatitude,
    double? userLongitude,
    bool clearSector = false,
  }) {
    return MapFilterState(
      filterType: filterType ?? this.filterType,
      viewMode: viewMode ?? this.viewMode,
      selectedSectorId: clearSector
          ? null
          : (selectedSectorId ?? this.selectedSectorId),
      userLatitude: userLatitude ?? this.userLatitude,
      userLongitude: userLongitude ?? this.userLongitude,
    );
  }
}
