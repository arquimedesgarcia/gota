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
    this.minLat,
    this.minLng,
    this.maxLat,
    this.maxLng,
    this.sectorCenterLat,
    this.sectorCenterLng,
  });

  final MapFilterType filterType;
  final MapViewMode viewMode;

  /// Sector específico si se activó el filtro "Mi sector".
  final String? selectedSectorId;

  /// Coordenadas del usuario si concedió permiso GPS (§13).
  final double? userLatitude;
  final double? userLongitude;

  /// Bounding box del viewport visible en el mapa (Sprint 05: optimización
  /// PostGIS). Capturado desde MapLibre al idle/move y pasado a la RPC.
  final double? minLat;
  final double? minLng;
  final double? maxLat;
  final double? maxLng;

  /// Centro del sector calculado una vez por selección (§B2).
  /// Se calcula desde el bounding box de leaks y se mantiene estable
  /// mientras el sector no cambie.
  final double? sectorCenterLat;
  final double? sectorCenterLng;

  bool get hasUserLocation => userLatitude != null && userLongitude != null;
  bool get hasBounds =>
      minLat != null && minLng != null && maxLat != null && maxLng != null;

  MapFilterState copyWith({
    MapFilterType? filterType,
    MapViewMode? viewMode,
    String? selectedSectorId,
    double? userLatitude,
    double? userLongitude,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    double? sectorCenterLat,
    double? sectorCenterLng,
  }) {
    return MapFilterState(
      filterType: filterType ?? this.filterType,
      viewMode: viewMode ?? this.viewMode,
      selectedSectorId: selectedSectorId ?? this.selectedSectorId,
      userLatitude: userLatitude ?? this.userLatitude,
      userLongitude: userLongitude ?? this.userLongitude,
      minLat: minLat ?? this.minLat,
      minLng: minLng ?? this.minLng,
      maxLat: maxLat ?? this.maxLat,
      maxLng: maxLng ?? this.maxLng,
      sectorCenterLat: sectorCenterLat ?? this.sectorCenterLat,
      sectorCenterLng: sectorCenterLng ?? this.sectorCenterLng,
    );
  }

  MapFilterState clearSector() => MapFilterState(
    filterType: MapFilterType.all,
    viewMode: viewMode,
    userLatitude: userLatitude,
    userLongitude: userLongitude,
    minLat: minLat,
    minLng: minLng,
    maxLat: maxLat,
    maxLng: maxLng,
  );
}
