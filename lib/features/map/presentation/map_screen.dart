import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../features/leaks/domain/leak_age.dart';
import '../../../../features/leaks/domain/leak_community.dart';
import '../../../../features/leaks/presentation/leak_detail_screen.dart';
import '../../../../shared/widgets/gota_filter_chip.dart';
import '../../../../shared/widgets/gota_icon_tile.dart';
import '../../../../shared/widgets/gota_status_badge.dart';
import '../domain/map_filter.dart';
import 'map_providers.dart'
    show
        mapFilterProvider,
        mapLocationActionProvider,
        mapReportsProvider,
        listReportsProvider,
        selectedMarkerProvider;
import 'widgets/gota_map_view.dart';

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

/// Pantalla principal del Mapa (Sprint 05).
///
/// Muestra fugas geolocalizadas con filtros y vista Mapa/Lista.
/// Seleccionar un marker abre el detalle existente (Sprint 02/03).
///
/// Sprint 09-UI: superficie de filtros con chips (patrón prototipo) y
/// botón "más filtros" con el menú popup existente; leyenda Activa/
/// Resuelta sobre el mapa; lista y estados visuales alineados al
/// Design System. Sin cambios funcionales.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(mapFilterProvider);
    // Lista usa listReportsProvider (sin bbox); mapa usa mapReportsProvider (con bbox).
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
            child: reportsAsync.when(
              loading: () => const _MapLoadingView(),
              error: (error, _) => _MapErrorView(
                message: _mapErrorMessage(error),
                // El reintento debe refrescar el proveedor que está observando la
                // pantalla en este modo (lista: sin bbox; mapa: con bbox).
                onRetry: () => ref.invalidate(
                  filterState.viewMode == MapViewMode.list
                      ? listReportsProvider
                      : mapReportsProvider,
                ),
              ),
              data: (reports) {
                if (reports.isEmpty) {
                  return _MapEmptyView(filterState: filterState);
                }

                return switch (filterState.viewMode) {
                  MapViewMode.map => Stack(
                    children: [
                      _MapViewContent(
                        leaks: reports,
                        selectedLeak: selectedLeak,
                        onMarkerTapped: (leak) {
                          ref
                              .read(selectedMarkerProvider.notifier)
                              .select(leak);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  LeakDetailScreen(reportId: leak.id),
                            ),
                          );
                        },
                        centerLat: filterState.userLatitude,
                        centerLng: filterState.userLongitude,
                      ),
                      const _MapLegend(),
                    ],
                  ),
                  MapViewMode.list => _MapListView(
                    leaks: reports,
                    onLeakTapped: (leak) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LeakDetailScreen(reportId: leak.id),
                      ),
                    ),
                  ),
                };
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _LocateButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
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
}

/// Barra de chips de filtro (patrón prototipo §mapa). Chips directos para
/// los filtros de alcance (Todas/Activas/Resueltas) y botón de menú para
/// los avances (Mi sector, Recientes, Más validadas) que mantiene el
/// PopupMenu funcional existente.
class _FilterChipsBar extends ConsumerWidget {
  const _FilterChipsBar({required this.filterState});

  final MapFilterState filterState;

  static const _directFilters = [
    MapFilterType.all,
    MapFilterType.active,
    MapFilterType.resolved,
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
                  onSelected: () =>
                      ref.read(mapFilterProvider.notifier).setFilter(filter),
                ),
              ),
            if (filterState.filterType == MapFilterType.mySector)
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: GotaFilterChip(
                  label: 'Mi sector',
                  selected: true,
                  onSelected: _noop,
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

  static void _noop() {}
}

/// Botón de menú de filtros (§10). En AppBar usa icono; como chip de la
/// superficie usa texto "Más filtros" + insignia del filtro activo.
class _FilterMenuButton extends ConsumerWidget {
  const _FilterMenuButton({required this.filterState, this.asChip = false});

  final MapFilterState filterState;
  final bool asChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (asChip) {
      return PopupMenuButton<MapFilterType>(
        key: mapMoreFiltersChipKey,
        tooltip: 'Filtrar',
        onSelected: (filter) {
          ref.read(mapFilterProvider.notifier).setFilter(filter);
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
        ref.read(mapFilterProvider.notifier).setFilter(filter);
      },
      itemBuilder: _items,
    );
  }

  List<PopupMenuEntry<MapFilterType>> _items(BuildContext context) =>
      MapFilterType.values.map((filter) {
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
      }).toList();
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

/// Leyenda Activa/Resuelta sobre el mapa (patrón prototipo §mapa):
/// color + texto, nunca color solo.
class _MapLegend extends StatelessWidget {
  const _MapLegend();

  static const _dot = 9.0;

  Widget _entry(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: _dot,
        height: _dot,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: AppSpacing.lg,
      bottom: AppSpacing.lg,
      child: Container(
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
            _entry(AppColors.danger, 'Activa'),
            const SizedBox(width: AppSpacing.lg),
            _entry(AppColors.success, 'Resuelta'),
          ],
        ),
      ),
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
  });

  final List<LeakSummary> leaks;
  final LeakSummary? selectedLeak;
  final ValueChanged<LeakSummary> onMarkerTapped;
  final double? centerLat;
  final double? centerLng;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GotaMapView(
      leaks: leaks,
      selectedLeak: selectedLeak,
      onMarkerTapped: onMarkerTapped,
      centerLat: centerLat,
      centerLng: centerLng,
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
    );
  }
}

/// Vista de lista sincronizada con los mismos filtros (§12).
///
/// Sprint 09-UI: patrón de tarjeta del prototipo — dot de estado + badge
/// semántico y texto + validaciones acentuadas (texto + color, nunca solo
/// color). Reutiliza [StatusBadgePresets] y tokens del Design System.
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
            borderRadius: BorderRadius.circular(14),
            onTap: () => onLeakTapped(leak),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  GotaIconTile(
                    icon: leak.isResolved
                        ? Icons.check_circle_outline
                        : Icons.water_drop_outlined,
                    color: leak.isResolved
                        ? AppColors.success
                        : AppColors.accent,
                  ),
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
                                color: leak.isResolved
                                    ? AppColors.success
                                    : AppColors.danger,
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
