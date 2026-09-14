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
    );
  }

  void setUserLocation(double lat, double lng) {
    state = state.copyWith(userLatitude: lat, userLongitude: lng);
  }

  void clearSector() {
    state = state.copyWith(clearSector: true);
  }

  /// Establece el bounding box del viewport visible en el mapa (Sprint 05).
  /// Se invoca desde GotaMapView cuando MapLibre dispara onCameraIdle.
  void setBounds(double minLat, double minLng, double maxLat, double maxLng) {
    state = state.copyWith(
      minLat: minLat,
      minLng: minLng,
      maxLat: maxLat,
      maxLng: maxLng,
    );
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

/// Provider de reportes para el mapa (§9): incluye filtros + bbox del viewport.
///
/// La vista de mapa consume este provider para mostrar solo fugas dentro
/// del área visible (optimización PostGIS).
final mapReportsProvider = FutureProvider<List<LeakSummary>>((ref) async {
  final filterState = ref.watch(mapFilterProvider);
  final repository = ref.watch(leakCommunityRepositoryProvider);

  String? status;
  String? sectorId;
  String orderBy = 'recent';

  switch (filterState.filterType) {
    case MapFilterType.all:
      status = null;
      orderBy = 'recent';
      break;
    case MapFilterType.active:
      status = 'ACTIVE';
      orderBy = 'recent';
      break;
    case MapFilterType.resolved:
      status = 'RESOLVED';
      orderBy = 'recent';
      break;
    case MapFilterType.recent:
      status = null;
      orderBy = 'recent';
      break;
    case MapFilterType.mostValidated:
      status = null;
      orderBy = 'validated';
      break;
    case MapFilterType.mySector:
      // "Mi sector" requiere selección explícita del sector vía setSectorId().
      // No se infiere el sector desde GPS porque no existe un modelo de
      // "sector del usuario" en Sprint 05; esa cadena (usuario → sector de
      // interés → notificación) pertenece a Sprint 06. Documentado en
      // MIGRATION_NOTES.md §Sprint-05-decisiones.
      sectorId = filterState.selectedSectorId;
      if (sectorId == null) {
        return const <LeakSummary>[];
      }
      break;
  }

  return repository.mapReports(
    status: status,
    sectorId: sectorId,
    minLat: filterState.minLat,
    minLng: filterState.minLng,
    maxLat: filterState.maxLat,
    maxLng: filterState.maxLng,
    orderBy: orderBy,
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

  String? status;
  String? sectorId;
  String orderBy = 'recent';

  switch (filterState.filterType) {
    case MapFilterType.all:
      status = null;
      orderBy = 'recent';
      break;
    case MapFilterType.active:
      status = 'ACTIVE';
      orderBy = 'recent';
      break;
    case MapFilterType.resolved:
      status = 'RESOLVED';
      orderBy = 'recent';
      break;
    case MapFilterType.recent:
      status = null;
      orderBy = 'recent';
      break;
    case MapFilterType.mostValidated:
      status = null;
      orderBy = 'validated';
      break;
    case MapFilterType.mySector:
      sectorId = filterState.selectedSectorId;
      if (sectorId == null) {
        return const <LeakSummary>[];
      }
      break;
  }

  return repository.mapReports(
    status: status,
    sectorId: sectorId,
    // No se aplican límites de bbox a la vista de lista
    minLat: null,
    minLng: null,
    maxLat: null,
    maxLng: null,
    orderBy: orderBy,
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
      return pos;
    } on LeakFlowException catch (error) {
      lastError = error.userMessage;
      return null;
    } on Exception {
      lastError = 'No pudimos obtener tu ubicación. Intenta de nuevo.';
      return null;
    }
  }
}
