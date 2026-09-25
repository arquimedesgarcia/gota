import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../features/leaks/domain/leak_age.dart';
import '../../../../features/leaks/domain/leak_community.dart';
import '../../../../features/leaks/presentation/leak_detail_screen.dart';
import '../../../../features/notifications/presentation/notification_providers.dart';
import '../../../../shared/widgets/gota_filter_chip.dart';
import '../../../../shared/widgets/gota_icon_tile.dart';
import '../../../../shared/widgets/gota_status_badge.dart';
import '../domain/map_filter.dart';
import '../domain/leak_map_status.dart';
import 'map_providers.dart'
    show
        mapFilterProvider,
        mapLocationActionProvider,
        mapReportsProvider,
        listReportsProvider,
        selectedMarkerProvider;
import 'widgets/gota_map_view.dart' show GotaMapView, LatLngBounds;

/// Claves estables para pruebas de UI (§17).
const mapScreenKey = Key('map-screen');

/// Clave para cards individuales en la vista de lista del mapa.
Key mapLeakCardKey(String reportId) => ValueKey('map-leak-card-$reportId');
const mapFilterMenuKey = Key('map-filter-menu');
const mapMoreFiltersChipKey = Key('map-more-filters-chip');
const mapViewToggleKey = Key('map-view-toggle');
const mapLocateButtonKey = Key('map-locate-button');
const mapListViewKey = Key('map-list-view');
const mapEmptyStateKey = Key('map-empty-state');
const mapErrorStateKey = Key('map-error-state');
const mapLoadingStateKey = Key('map-loading-state');
const mapLegendKey = Key('map-legend');

bool _isMySectorWithoutSelection(MapFilterState filterState) =>
    filterState.filterType == MapFilterType.mySector &&
    filterState.selectedSectorId == null;

/// Pantalla principal del Mapa (Sprint 05).
///
/// Muestra fugas geolocalizadas con filtros y vista Mapa/Lista.
/// Seleccionar un marker abre el detalle existente (Sprint 02/03).
/// Al abrirse, centra automáticamente en la ubicación del usuario.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  @override
  void initState() {
    super.initState();
    // Centra el mapa en la ubicación del usuario al abrir la pantalla,
    // igual que si el usuario presionara el botón "Mi ubicación".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mapLocationActionProvider).locateUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(mapFilterProvider);
    final reportsAsync = filterState.viewMode == MapViewMode.list
        ? ref.watch(listReportsProvider)
        : ref.watch(mapReportsProvider);
    final selectedLeak = ref.watch(selectedMarkerProvider);

    return Scaffold(
      key: mapScreenKey,
      appBar: AppBar(
        title: const Text('Mapa'),
        actions: [
          _FilterMenuButton(filterState: filterState),
          _ViewModeToggle(viewMode: filterState.viewMode),
        ],
      ),
      body: Column(
        children: [
          _FilterChipsBar(filterState: filterState),
          Expanded(
            child: filterState.viewMode == MapViewMode.map
                ? _buildMapWithOverlays(
                    context,
                    ref,
                    reportsAsync,
                    selectedLeak,
                    filterState,
                  )
                : reportsAsync.when(
                    skipLoadingOnReload: true,
                    loading: () => const _MapLoadingView(),
                    error: (error, _) => _MapErrorView(
                      message: _mapErrorMessage(error),
                      onRetry: () => ref.invalidate(
                        filterState.viewMode == MapViewMode.list
                            ? listReportsProvider
                            : mapReportsProvider,
                      ),
                    ),
                    data: (reports) {
                      if (_isMySectorWithoutSelection(filterState)) {
                        return _MapEmptyView(filterState: filterState);
                      }
                      return reports.isEmpty
                          ? _MapEmptyView(filterState: filterState)
                          : _MapListView(
                              leaks: reports,
                              onLeakTapped: (leak) => Navigator.of(context)
                                  .push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          LeakDetailScreen(reportId: leak.id),
                                    ),
                                  ),
                            );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _LocateButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

String _mapErrorMessage(Object error) {
  if (error is NetworkException) {
    return 'Sin conexión. Verifica tu red e intenta de nuevo.';
  }
  if (error is QueryException) {
    return 'No pudimos cargar el mapa. Intenta de nuevo.';
  }
  return 'Ocurrió un error inesperado. Intenta de nuevo.';
}

Widget _buildMapWithOverlays(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<List<LeakSummary>> reportsAsync,
  LeakSummary? selectedLeak,
  MapFilterState filterState,
) {
  if (_isMySectorWithoutSelection(filterState)) {
    return _MapEmptyView(filterState: filterState);
  }

  return Stack(
    children: [
      _MapViewContent(
        leaks: reportsAsync.value ?? const [],
        selectedLeak: selectedLeak,
        onMarkerTapped: (leak) {
          ref.read(selectedMarkerProvider.notifier).select(leak);
        },
        centerLat: filterState.userLatitude,
        centerLng: filterState.userLongitude,
        onBoundsChanged: (bounds) {
          if (bounds != null) {
            ref
                .read(mapFilterProvider.notifier)
                .setBounds(
                  bounds.minLat,
                  bounds.minLng,
                  bounds.maxLat,
                  bounds.maxLng,
                );
          }
        },
      ),
          // Leyenda de colores: bottom-left, siempre visible.
      const Positioned(
        left: AppSpacing.lg,
        bottom: AppSpacing.lg,
        child: _MapLegend(),
      ),
      // Tarjeta de fuga seleccionada: top-right, debajo de los botones +/-.
      // Los botones +/- ocupan top:12, 40px + 8px + 40px = 100px → card top:108.
      if (selectedLeak != null)
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: 108.0,
          child: _SelectedLeakCard(
            leak: selectedLeak,
            onViewDetail: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LeakDetailScreen(reportId: selectedLeak.id),
              ),
            ),
          ),
        ),
      if (reportsAsync.isLoading && !reportsAsync.hasValue)
        const _MapLoadingView(),
      if (reportsAsync.hasError)
        _MapErrorView(
          message: _mapErrorMessage(reportsAsync.error!),
          onRetry: () => ref.invalidate(mapReportsProvider),
        ),
    ],
  );
}

/// Barra de chips de filtro (patrón prototipo §mapa). Chips directos para
/// los filtros de alcance (Todas/Activas/Resueltas) y botón de menú para
/// los avances (Mi sector, Recientes, Más validadas) que mantiene el
/// PopupMenu funcional existente.
class _FilterChipsBar extends ConsumerWidget {
  const _FilterChipsBar({required this.filterState});

  final MapFilterState filterState;

  // H: Mi Sector | Recientes | Activas
  static const _directFilters = [
    MapFilterType.mySector,
    MapFilterType.recent,
    MapFilterType.active,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in _directFilters)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: GotaFilterChip(
                  label: filter.label,
                  selected: filterState.filterType == filter,
                  onSelected: () => _selectFilter(ref, filter),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _FilterMenuButton(filterState: filterState, asChip: true),
            ),
          ],
        ),
      ),
    );
  }

  // H: mySector necesita resolver el sectorId preferido igual que el menú.
  Future<void> _selectFilter(WidgetRef ref, MapFilterType filter) async {
    if (filter == MapFilterType.mySector) {
      final preferences = ref.read(
        notificationPreferencesControllerProvider,
      ).value;
      if (preferences?.preferredSectorId != null) {
        ref
            .read(mapFilterProvider.notifier)
            .setSectorId(preferences!.preferredSectorId);
        return;
      }
    }
    ref.read(mapFilterProvider.notifier).setFilter(filter);
  }
}

/// Botón de menú de filtros (§10). En AppBar usa icono; como chip de la
/// superficie usa texto "Más filtros" + insignia del filtro activo.
class _FilterMenuButton extends ConsumerWidget {
  const _FilterMenuButton({required this.filterState, this.asChip = false});

  final MapFilterState filterState;
  final bool asChip;

  Future<void> _handleFilterSelection(
    WidgetRef ref,
    MapFilterType filter,
  ) async {
    if (filter == MapFilterType.mySector) {
      final preferencesAsync = ref.read(
        notificationPreferencesControllerProvider,
      );
      final preferences = preferencesAsync.value;
      if (preferences?.preferredSectorId != null) {
        ref
            .read(mapFilterProvider.notifier)
            .setSectorId(preferences!.preferredSectorId);
      } else {
        ref.read(mapFilterProvider.notifier).setFilter(filter);
      }
    } else {
      ref.read(mapFilterProvider.notifier).setFilter(filter);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (asChip) {
      return PopupMenuButton<MapFilterType>(
        key: mapMoreFiltersChipKey,
        tooltip: 'Filtrar',
        onSelected: (filter) {
          _handleFilterSelection(ref, filter);
        },
        itemBuilder: _items,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_list, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Más filtros',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return PopupMenuButton<MapFilterType>(
      key: mapFilterMenuKey,
      tooltip: 'Filtrar',
      icon: const Icon(Icons.filter_list),
      onSelected: (filter) {
        _handleFilterSelection(ref, filter);
      },
      itemBuilder: _items,
    );
  }

  // H: excluir los filtros que ya son chips directos.
  static const _chipFilters = _FilterChipsBar._directFilters;

  List<PopupMenuEntry<MapFilterType>> _items(BuildContext context) =>
      MapFilterType.values
          .where((f) => !_chipFilters.contains(f))
          .map((filter) {
            final isSelected = filterState.filterType == filter;
            return PopupMenuItem<MapFilterType>(
              value: filter,
              child: Row(
                children: [
                  if (isSelected)
                    Icon(Icons.check, size: 18, color: AppColors.primary),
                  if (isSelected) const SizedBox(width: 8),
                  Text(filter.label),
                ],
              ),
            );
          })
          .toList();
}

/// Toggle Mapa ↔ Lista (§12).
class _ViewModeToggle extends ConsumerWidget {
  const _ViewModeToggle({required this.viewMode});

  final MapViewMode viewMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: mapViewToggleKey,
      tooltip: viewMode == MapViewMode.map ? 'Ver lista' : 'Ver mapa',
      icon: Icon(viewMode == MapViewMode.map ? Icons.list : Icons.map),
      onPressed: () => ref
          .read(mapFilterProvider.notifier)
          .setViewMode(
            viewMode == MapViewMode.map ? MapViewMode.list : MapViewMode.map,
          ),
    );
  }
}

/// Botón para centrar en la ubicación del usuario (§13).
class _LocateButton extends ConsumerWidget {
  const _LocateButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.small(
      key: mapLocateButtonKey,
      tooltip: 'Mi ubicación',
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.primary,
      onPressed: () async {
        final action = ref.read(mapLocationActionProvider);
        await action.locateUser();
      },
      child: const Icon(Icons.my_location),
    );
  }
}

/// Contenido del mapa con markers (§11).
class _MapViewContent extends ConsumerWidget {
  const _MapViewContent({
    required this.leaks,
    required this.selectedLeak,
    required this.onMarkerTapped,
    this.centerLat,
    this.centerLng,
    this.onBoundsChanged,
  });

  final List<LeakSummary> leaks;
  final LeakSummary? selectedLeak;
  final ValueChanged<LeakSummary> onMarkerTapped;
  final double? centerLat;
  final double? centerLng;
  final ValueChanged<LatLngBounds?>? onBoundsChanged;

  /// Calcula el centro del bounding box de los reportes (para "Mi sector").
  ({double lat, double lng})? _calculateSectorCenter() {
    final leaksWithCoordinates = leaks.where((l) => l.hasCoordinates).toList();
    if (leaksWithCoordinates.isEmpty) return null;

    double minLat = leaksWithCoordinates[0].latitude!;
    double maxLat = leaksWithCoordinates[0].latitude!;
    double minLng = leaksWithCoordinates[0].longitude!;
    double maxLng = leaksWithCoordinates[0].longitude!;

    for (final leak in leaksWithCoordinates) {
      minLat = leak.latitude! < minLat ? leak.latitude! : minLat;
      maxLat = leak.latitude! > maxLat ? leak.latitude! : maxLat;
      minLng = leak.longitude! < minLng ? leak.longitude! : minLng;
      maxLng = leak.longitude! > maxLng ? leak.longitude! : maxLng;
    }

    return (lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(mapFilterProvider);
    double? finalCenterLat;
    double? finalCenterLng;
    if (centerLat != null) {
      finalCenterLat = centerLat;
      finalCenterLng = centerLng;
    } else if (filterState.filterType == MapFilterType.mySector) {
      finalCenterLat = filterState.sectorCenterLat;
      finalCenterLng = filterState.sectorCenterLng;
      if (finalCenterLat == null) {
        final center = _calculateSectorCenter();
        if (center != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            ref
                .read(mapFilterProvider.notifier)
                .setSectorCenter(center.lat, center.lng);
          });
          finalCenterLat = center.lat;
          finalCenterLng = center.lng;
        }
      }
    }
    finalCenterLat ??= 10.99;
    finalCenterLng ??= -63.87;

    return GotaMapView(
      leaks: leaks,
      selectedLeak: selectedLeak,
      onMarkerTapped: onMarkerTapped,
      centerLat: finalCenterLat,
      centerLng: finalCenterLng,
      onBoundsChanged: onBoundsChanged,
    );
  }
}

class _SelectedLeakCard extends StatelessWidget {
  const _SelectedLeakCard({required this.leak, required this.onViewDetail});

  final LeakSummary leak;
  final VoidCallback onViewDetail;

  @override
  Widget build(BuildContext context) {
    final place = [
      if (leak.sectorName != null) leak.sectorName!,
      if (leak.municipalityName != null) leak.municipalityName!,
    ].join(' · ');

    return Card(
      key: const Key('map-selection-card'),
      margin: EdgeInsets.zero,
      elevation: 8,
      shadowColor: AppColors.text.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LeakPhotoThumbnail(leak: leak),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          leak.isResolved
                              ? StatusBadgePresets.resolved(context)
                              : StatusBadgePresets.active(context),
                          const Spacer(),
                          Text(
                            describeLeakAge(leak.createdAt),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        place.isEmpty ? 'Reporte de fuga' : place,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            leak.validationCount == 1
                                ? '1 validación'
                                : '${leak.validationCount} validaciones',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('map-view-detail-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onPressed: onViewDetail,
                child: const Text(
                  'Ver detalle',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapListView extends StatelessWidget {
  const _MapListView({required this.leaks, required this.onLeakTapped});

  final List<LeakSummary> leaks;
  final ValueChanged<LeakSummary> onLeakTapped;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: mapListViewKey,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: leaks.length,
      itemBuilder: (context, index) {
        final leak = leaks[index];
        final place = [
          if (leak.sectorName != null) leak.sectorName!,
          if (leak.municipalityName != null) leak.municipalityName!,
        ].join(' · ');

        return Card(
          key: mapLeakCardKey(leak.id),
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => onLeakTapped(leak),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeakPhotoThumbnail(leak: leak, size: 76),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: leakMapStatusColor(leakMapStatusOf(leak)),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            leak.isResolved
                                ? StatusBadgePresets.resolved(context)
                                : StatusBadgePresets.active(context),
                            const Spacer(),
                            Text(
                              describeLeakAge(leak.createdAt),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          place.isEmpty ? 'Ubicación desconocida' : place,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          leak.validationCount == 1
                              ? '1 validación'
                              : '${leak.validationCount} validaciones',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Miniatura de foto de una fuga: placeholder con color e icono por estado.
/// Cuando las fotos reales estén disponibles se reemplaza el interior
/// manteniendo el mismo tamaño y radio.
class _LeakPhotoThumbnail extends StatelessWidget {
  const _LeakPhotoThumbnail({required this.leak, this.size = 64.0});

  final LeakSummary leak;
  final double size;

  @override
  Widget build(BuildContext context) {
    final status = leakMapStatusOf(leak);
    final color = leakMapStatusColor(status);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(
        leak.isResolved ? Icons.check_circle_outline : Icons.water_drop_outlined,
        color: color.withValues(alpha: 0.75),
        size: size * 0.44,
      ),
    );
  }
}

/// Vista de carga del mapa (§14).
class _MapLoadingView extends StatelessWidget {
  const _MapLoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: mapLoadingStateKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Cargando mapa…',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Vista de error del mapa (§14).
class _MapErrorView extends StatelessWidget {
  const _MapErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: mapErrorStateKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GotaIconTile(
              icon: Icons.error_outline,
              color: AppColors.danger,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vista vacía del mapa (§14).
///
/// Proporciona un mensaje específico cuando el filtro "Mi sector" está activo
/// pero no hay sector seleccionado (Sprint 05, decisión de UX).
class _MapEmptyView extends StatelessWidget {
  const _MapEmptyView({required this.filterState});

  final MapFilterState filterState;

  @override
  Widget build(BuildContext context) {
    final isMySectorWithoutSelection =
        filterState.filterType == MapFilterType.mySector &&
        filterState.selectedSectorId == null;

    return Center(
      key: mapEmptyStateKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GotaIconTile(
              icon: Icons.map_outlined,
              color: AppColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isMySectorWithoutSelection
                  ? 'Configura tu sector'
                  : 'Sin fugas para mostrar',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isMySectorWithoutSelection
                  ? 'Para usar el filtro "Mi sector", establece tu sector desde tu perfil.'
                  : 'Cambia los filtros o amplía el área para ver más resultados.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leyenda de colores del mapa: punto rojo = Activa, punto verde = Resuelta.
class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: mapLegendKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LegendDot(color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Activa',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const _LegendDot(color: AppColors.success),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Resuelta',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

