import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../features/leaks/domain/leak_age.dart';
import '../../../../features/leaks/domain/leak_community.dart';
import '../../../../features/leaks/presentation/leak_detail_screen.dart';
import '../domain/map_filter.dart';
import 'widgets/gota_map_view.dart';
import 'map_providers.dart'
    show
        mapFilterProvider,
        mapLocationActionProvider,
        mapReportsProvider,
        listReportsProvider,
        selectedMarkerProvider;

/// Claves estables para pruebas de UI (§17).
const mapScreenKey = Key('map-screen');

/// Clave para cards individuales en la vista de lista del mapa.
Key mapLeakCardKey(String reportId) => ValueKey('map-leak-card-$reportId');
const mapFilterMenuKey = Key('map-filter-menu');
const mapViewToggleKey = Key('map-view-toggle');
const mapLocateButtonKey = Key('map-locate-button');
const mapListViewKey = Key('map-list-view');
const mapEmptyStateKey = Key('map-empty-state');
const mapErrorStateKey = Key('map-error-state');
const mapLoadingStateKey = Key('map-loading-state');

/// Pantalla principal del Mapa (Sprint 05).
///
/// Muestra fugas geolocalizadas con filtros y vista Mapa/Lista.
/// Seleccionar un marker abre el detalle existente (Sprint 02/03).
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
      body: reportsAsync.when(
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
            MapViewMode.map => _MapViewContent(
              leaks: reports,
              selectedLeak: selectedLeak,
              onMarkerTapped: (leak) {
                ref.read(selectedMarkerProvider.notifier).select(leak);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LeakDetailScreen(reportId: leak.id),
                  ),
                );
              },
              centerLat: filterState.userLatitude,
              centerLng: filterState.userLongitude,
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

/// Botón de menú de filtros (§10).
class _FilterMenuButton extends ConsumerWidget {
  const _FilterMenuButton({required this.filterState});

  final MapFilterState filterState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<MapFilterType>(
      key: mapFilterMenuKey,
      tooltip: 'Filtrar',
      icon: const Icon(Icons.filter_list),
      onSelected: (filter) {
        ref.read(mapFilterProvider.notifier).setFilter(filter);
      },
      itemBuilder: (context) => MapFilterType.values.map((filter) {
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
      }).toList(),
    );
  }
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
          ref.read(mapFilterProvider.notifier).setBounds(
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
class _MapListView extends StatelessWidget {
  const _MapListView({required this.leaks, required this.onLeakTapped});

  final List<LeakSummary> leaks;
  final ValueChanged<LeakSummary> onLeakTapped;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: mapListViewKey,
      padding: const EdgeInsets.all(16),
      itemCount: leaks.length,
      itemBuilder: (context, index) {
        final leak = leaks[index];
        final place = [
          if (leak.sectorName != null) leak.sectorName!,
          if (leak.municipalityName != null) leak.municipalityName!,
        ].join(' · ');

        return Card(
          key: mapLeakCardKey(leak.id),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onLeakTapped(leak),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    leak.isResolved
                        ? Icons.check_circle_outline
                        : Icons.water_drop_outlined,
                    color: leak.isResolved
                        ? AppColors.success
                        : AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.isEmpty ? 'Ubicación desconocida' : place,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${describeLeakAge(leak.createdAt)} · '
                          '${leak.validationCount} validaciones',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(resolved: leak.isResolved),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.resolved});

  final bool resolved;

  @override
  Widget build(BuildContext context) {
    final color = resolved ? AppColors.success : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        resolved ? 'Resuelta' : 'Activa',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
          const SizedBox(height: 16),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              isMySectorWithoutSelection
                  ? 'Configura tu sector'
                  : 'Sin fugas para mostrar',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
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
