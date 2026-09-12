import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../leaks/domain/leak_community.dart';
import '../map_providers.dart';

/// Claves estables para pruebas de UI (§17).
const gotaMapContainerKey = Key('gota-map-container');
Key mapMarkerKey(String reportId) => ValueKey('map-marker-$reportId');

/// URL del estilo de mapa, configurable vía dart-define MAP_TILE_STYLE_URL.
///
/// Por defecto apunta a los tiles de demostración de MapLibre, únicamente
/// para desarrollo y staging. En producción debe suministrarse una URL real:
///   flutter run --dart-define=MAP_TILE_STYLE_URL=https://...
const kMapLibreDefaultStyle = String.fromEnvironment(
  'MAP_TILE_STYLE_URL',
  defaultValue: 'https://demotiles.maplibre.org/style.json',
);

/// Bounding box de un viewport MapLibre (Sprint 05).
class LatLngBounds {
  LatLngBounds({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });

  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;

  @override
  String toString() =>
      'LatLngBounds($minLat, $minLng, $maxLat, $maxLng)';
}

/// Abstracción de renderizado del mapa (§5).
///
/// Permite desacoplar la UI de MapLibre y renderizar una representación
/// comprobable en pruebas de widget donde el motor nativo OpenGL no está disponible.
typedef MapWidgetBuilder = Widget Function(
  BuildContext context, {
  required List<LeakSummary> leaks,
  required LeakSummary? selectedLeak,
  required ValueChanged<LeakSummary> onMarkerTapped,
  required double initialLat,
  required double initialLng,
  required ValueChanged<LatLngBounds?>? onBoundsChanged,
});

/// Provider para inyectar la implementación del mapa (producción o test).
final mapWidgetBuilderProvider = Provider<MapWidgetBuilder>((ref) {
  return (
    context, {
    required leaks,
    required selectedLeak,
    required onMarkerTapped,
    required initialLat,
    required initialLng,
    required onBoundsChanged,
  }) {
    return _MapLibreMapView(
      leaks: leaks,
      selectedLeak: selectedLeak,
      onMarkerTapped: onMarkerTapped,
      initialLat: initialLat,
      initialLng: initialLng,
      onBoundsChanged: onBoundsChanged,
    );
  };
});

/// Componente principal del mapa geolocalizado (§5, §11).
class GotaMapView extends ConsumerWidget {
  const GotaMapView({
    super.key,
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

  /// Callback invocado cuando cambia el viewport visible (Sprint 05).
  final ValueChanged<LatLngBounds?>? onBoundsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builder = ref.watch(mapWidgetBuilderProvider);
    final lat = centerLat ?? kDefaultMapCenterLat;
    final lng = centerLng ?? kDefaultMapCenterLng;

    return Container(
      key: gotaMapContainerKey,
      color: Colors.grey.shade200,
      child: builder(
        context,
        leaks: leaks,
        selectedLeak: selectedLeak,
        onMarkerTapped: onMarkerTapped,
        initialLat: lat,
        initialLng: lng,
        onBoundsChanged: onBoundsChanged,
      ),
    );
  }
}

/// Implementación concreta de MapLibre (§5).
class _MapLibreMapView extends StatefulWidget {
  const _MapLibreMapView({
    required this.leaks,
    required this.selectedLeak,
    required this.onMarkerTapped,
    required this.initialLat,
    required this.initialLng,
    this.onBoundsChanged,
  });

  final List<LeakSummary> leaks;
  final LeakSummary? selectedLeak;
  final ValueChanged<LeakSummary> onMarkerTapped;
  final double initialLat;
  final double initialLng;
  final ValueChanged<LatLngBounds?>? onBoundsChanged;

  @override
  State<_MapLibreMapView> createState() => _MapLibreMapViewState();
}

class _MapLibreMapViewState extends State<_MapLibreMapView> {
  MapLibreMapController? _controller;
  final Map<Circle, LeakSummary> _circleToLeak = {};

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add((circle) {
      final leak = _circleToLeak[circle];
      if (leak != null) {
        widget.onMarkerTapped(leak);
      }
    });
    _updateMarkers();
  }

  void _onStyleLoaded() {
    _updateMarkers();
  }

  void _onCameraIdle() {
    // Captura los límites visibles cuando la cámara está en reposo (Sprint 05).
    _controller?.getVisibleRegion().then((region) {
      if (widget.onBoundsChanged != null) {
        final bounds = LatLngBounds(
          minLat: region.southwest.latitude,
          minLng: region.southwest.longitude,
          maxLat: region.northeast.latitude,
          maxLng: region.northeast.longitude,
        );
        widget.onBoundsChanged!(bounds);
      }
    }).catchError((_) {
      // Ignorar errores transitorios del controlador nativo
    });
  }

  @override
  void didUpdateWidget(covariant _MapLibreMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compara por contenido (IDs) para evitar redraws innecesarios cuando
    // Riverpod retorna una nueva instancia de lista con los mismos datos.
    final leaksChanged = !_sameIds(oldWidget.leaks, widget.leaks);
    final selectedChanged = oldWidget.selectedLeak?.id != widget.selectedLeak?.id;
    if (leaksChanged || selectedChanged) {
      _updateMarkers();
    }
  }

  static bool _sameIds(List<LeakSummary> a, List<LeakSummary> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _updateMarkers() async {
    final c = _controller;
    if (c == null) return;

    try {
      await c.clearCircles();
      _circleToLeak.clear();

      for (final leak in widget.leaks) {
        if (!leak.hasCoordinates) continue;

        // ACTIVE vs RESOLVED: Distinción visual (§11)
        final isResolved = leak.isResolved;
        final isSelected = widget.selectedLeak?.id == leak.id;

        final color = isResolved ? AppColors.success : AppColors.accent;
        final hexColor = _colorToHex(color);

        final circle = await c.addCircle(
          CircleOptions(
            geometry: LatLng(leak.latitude!, leak.longitude!),
            circleColor: hexColor,
            circleRadius: isSelected ? 12.0 : 8.0,
            circleStrokeWidth: isSelected ? 3.0 : 1.5,
            circleStrokeColor: '#FFFFFF',
            circleOpacity: 0.9,
          ),
        );
        _circleToLeak[circle] = leak;
      }
    } catch (_) {
      // Ignorar errores transitorios del controlador nativo
    }
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).toInt().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).toInt().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).toInt().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: kMapLibreDefaultStyle,
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.initialLat, widget.initialLng),
        zoom: 12.0,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      onCameraIdle: _onCameraIdle,
      myLocationEnabled: false,
      trackCameraPosition: false,
    );
  }
}
