import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leaks/data/geolocator_location_service.dart';
import '../../leaks/data/leak_community_repository.dart';
import '../../leaks/data/location_service.dart';
import '../../leaks/domain/leak_community.dart';
import '../../leaks/domain/leak_errors.dart';
import '../domain/map_filter.dart';

/// Coordenadas por defecto (centro de Isla de Margarita / Nueva Esparta).
const kDefaultMapCenterLat = 10.99;
const kDefaultMapCenterLng = -63.87;

/// Notifier para gestionar el estado de los filtros del mapa (§10).
class MapFilterNotifier extends Notifier<MapFilterState> {
  @override
  MapFilterState build() => const MapFilterState();

  void setFilter(MapFilterType filter) {
    state = state.copyWith(filterType: filter);
  }

  void setViewMode(MapViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  void setSectorId(String? sectorId) {
    state = state.copyWith(
      selectedSectorId: sectorId,
      filterType: MapFilterType.mySector,
      sectorCenterLat: null,
      sectorCenterLng: null,
    );
  }

  void setUserLocation(double lat, double lng) {
    state = state.copyWith(userLatitude: lat, userLongitude: lng);
  }

  void clearSector() {
    state = state.clearSector();
  }

  static const double _boundsTolerance = 1e-5;

  void setBounds(double minLat, double minLng, double maxLat, double maxLng) {
    final hasExistingBounds =
        state.minLat != null ||
        state.minLng != null ||
        state.maxLat != null ||
        state.maxLng != null;
    if (hasExistingBounds) {
      final dMinLat = (state.minLat ?? minLat) - minLat;
      final dMinLng = (state.minLng ?? minLng) - minLng;
      final dMaxLat = (state.maxLat ?? maxLat) - maxLat;
      final dMaxLng = (state.maxLng ?? maxLng) - maxLng;
      if (dMinLat.abs() < _boundsTolerance &&
          dMinLng.abs() < _boundsTolerance &&
          dMaxLat.abs() < _boundsTolerance &&
          dMaxLng.abs() < _boundsTolerance) {
        return;
      }
    }

    state = state.copyWith(
      minLat: minLat,
      minLng: minLng,
      maxLat: maxLat,
      maxLng: maxLng,
    );
  }

  void setSectorCenter(double lat, double lng) {
    if (state.sectorCenterLat == lat && state.sectorCenterLng == lng) return;
    state = state.copyWith(sectorCenterLat: lat, sectorCenterLng: lng);
  }
}

final mapFilterProvider = NotifierProvider<MapFilterNotifier, MapFilterState>(
  MapFilterNotifier.new,
);

/// Notifier para el marker seleccionado en el mapa (§11).
class SelectedMarkerNotifier extends Notifier<LeakSummary?> {
  @override
  LeakSummary? build() => null;

  void select(LeakSummary leak) => state = leak;
  void clear() => state = null;
}

final selectedMarkerProvider =
    NotifierProvider<SelectedMarkerNotifier, LeakSummary?>(
      SelectedMarkerNotifier.new,
    );

/// Traduce [MapFilterState.filterType] a los parámetros de consulta compartidos
/// por [mapReportsProvider] y [listReportsProvider].
({String? status, String? sectorId, String orderBy}) _buildFilterParams(
  MapFilterState filterState,
) {
  String? status;
  String? sectorId;
  String orderBy = 'recent';

  switch (filterState.filterType) {
    case MapFilterType.all:
      status = 'ACTIVE';
      orderBy = 'recent';
    case MapFilterType.active:
      status = 'ACTIVE';
      orderBy = 'recent';
    case MapFilterType.resolved:
      status = 'RESOLVED';
      orderBy = 'recent';
    case MapFilterType.recent:
      status = 'ACTIVE';
      orderBy = 'recent';
    case MapFilterType.mostValidated:
      status = 'ACTIVE';
      orderBy = 'validated';
    case MapFilterType.mySector:
      status = 'ACTIVE';
      sectorId = filterState.selectedSectorId;
  }

  return (status: status, sectorId: sectorId, orderBy: orderBy);
}

/// Provider de reportes para el mapa (§9): incluye filtros + bbox del viewport.
///
/// La vista de mapa consume este provider para mostrar solo fugas dentro
/// del área visible (optimización PostGIS).
final mapReportsProvider = FutureProvider<List<LeakSummary>>((ref) async {
  final filterState = ref.watch(mapFilterProvider);
  final repository = ref.watch(leakCommunityRepositoryProvider);

  final params = _buildFilterParams(filterState);
  // "Mi sector" requiere selección explícita del sector vía setSectorId().
  // No se infiere el sector desde GPS porque no existe un modelo de
  // "sector del usuario" en Sprint 05; esa cadena (usuario → sector de
  // interés → notificación) pertenece a Sprint 06. Documentado en
  // MIGRATION_NOTES.md §Sprint-05-decisiones.
  if (filterState.filterType == MapFilterType.mySector &&
      params.sectorId == null) {
    return const <LeakSummary>[];
  }

  return repository.mapReports(
    status: params.status,
    sectorId: params.sectorId,
    minLat: filterState.minLat,
    minLng: filterState.minLng,
    maxLat: filterState.maxLat,
    maxLng: filterState.maxLng,
    orderBy: params.orderBy,
    limit: 100,
  );
});

/// Provider de reportes para la lista (§12): incluye filtros pero SIN bbox.
///
/// La vista de lista consume este provider para mostrar todas las fugas que
/// coincidan con los filtros activos, sin restricción del viewport visible
/// (decisión UX: la lista es más exhaustiva que el mapa).
final listReportsProvider = FutureProvider<List<LeakSummary>>((ref) async {
  final filterState = ref.watch(mapFilterProvider);
  final repository = ref.watch(leakCommunityRepositoryProvider);

  final params = _buildFilterParams(filterState);
  if (filterState.filterType == MapFilterType.mySector &&
      params.sectorId == null) {
    return const <LeakSummary>[];
  }

  return repository.mapReports(
    status: params.status,
    sectorId: params.sectorId,
    // No se aplican límites de bbox a la vista de lista
    minLat: null,
    minLng: null,
    maxLat: null,
    maxLng: null,
    orderBy: params.orderBy,
    limit: 100,
  );
});

/// Servicio de ubicación bajo demanda para el mapa (§13).
///
/// NO implementa tracking continuo. Solo obtiene la posición actual
/// si el usuario lo solicita explícitamente o permite centrar el mapa.
final mapLocationActionProvider = Provider<MapLocationAction>((ref) {
  return MapLocationAction(ref);
});

class MapLocationAction {
  MapLocationAction(this._ref);

  final Ref _ref;
  String? lastError;

  LocationService get _locationService => _ref.read(locationServiceProvider);

  /// Intenta obtener la posición una sola vez para centrar el mapa (§13).
  Future<({double latitude, double longitude})?> locateUser() async {
    lastError = null;
    try {
      final pos = await _locationService.getCurrentPosition();
      _ref
          .read(mapFilterProvider.notifier)
          .setUserLocation(pos.latitude, pos.longitude);
      return (latitude: pos.latitude, longitude: pos.longitude);
    } on LeakFlowException catch (error) {
      lastError = error.userMessage;
      return null;
    } on Exception {
      lastError = 'No pudimos obtener tu ubicación. Intenta de nuevo.';
      return null;
    }
  }
}
