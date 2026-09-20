import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../leaks/domain/leak_community.dart';
import '../../domain/leak_map_status.dart';
import '../map_providers.dart';

/// Claves estables para pruebas de UI (§17).
const gotaMapContainerKey = Key('gota-map-container');
Key mapMarkerKey(String reportId) => ValueKey('map-marker-$reportId');

/// URL del estilo de mapa, configurable vía dart-define MAP_TILE_STYLE_URL.
///
/// Por defecto usa el estilo vectorial "Liberty" de OpenFreeMap (datos
/// OpenStreetMap): calles, nombres de calles, sectores, edificaciones, parques
/// y cuerpos de agua. Gratuito y sin API key; la atribución requerida (©
/// OpenStreetMap / OpenFreeMap) la muestra MapLibre automáticamente desde el
/// propio estilo. Se puede sobreescribir:
///   flutter run --dart-define=MAP_TILE_STYLE_URL=https://...
const kMapLibreDefaultStyle = String.fromEnvironment(
  'MAP_TILE_STYLE_URL',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
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
  double? _lastCenteredLat;
  double? _lastCenteredLng;
  bool _mapCreated = false;
  bool _styleLoaded = false;

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _mapCreated = false;
    _styleLoaded = false;
    controller.onCircleTapped.add((circle) {
      final leak = _circleToLeak[circle];
      if (leak != null) {
        widget.onMarkerTapped(leak);
      }
    });
    _mapCreated = true;
  }

  void _onStyleLoaded() {
    _styleLoaded = true;
    _updateMarkers();
  }

  void _onCameraIdle() {
    if (!_mapCreated || !_styleLoaded) return;
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

    // Detecta cambios en la posición central (ej: usuario toca "Mi ubicación")
    // y anima la cámara si el controlador está disponible (Sprint 05).
    final centerChanged = oldWidget.initialLat != widget.initialLat ||
        oldWidget.initialLng != widget.initialLng;
    if (centerChanged) {
      _animateToNewCenter(widget.initialLat, widget.initialLng);
    }
  }

  /// Anima la cámara hacia una nueva posición central (§13, Sprint 05).
  Future<void> _animateToNewCenter(double lat, double lng) async {
    final c = _controller;
    if (c == null) return;
    if (!_mapCreated || !_styleLoaded) return;
    if (lat == _lastCenteredLat && lng == _lastCenteredLng) return;

    try {
      _lastCenteredLat = lat;
      _lastCenteredLng = lng;
      await c.animateCamera(
        CameraUpdate.newLatLng(LatLng(lat, lng)),
        duration: const Duration(milliseconds: 300),
      );
    } catch (_) {
      // Ignorar errores transitorios del controlador nativo
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
    if (!_mapCreated || !_styleLoaded) return;

    try {
      await c.clearCircles();
      _circleToLeak.clear();

      for (final leak in widget.leaks) {
        if (!leak.hasCoordinates) continue;

        // Estado visual derivado: reportada/validada/resuelta (§leyenda).
        final color = leakMapStatusColor(leakMapStatusOf(leak));
        final hexColor = _colorToHex(color);

        final isSelected = widget.selectedLeak?.id == leak.id;
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
  void dispose() {
    _mapCreated = false;
    _styleLoaded = false;
    super.dispose();
  }

  Future<void> _zoomBy(double delta) async {
    final c = _controller;
    if (c == null) return;
    if (!_mapCreated || !_styleLoaded) return;
    try {
      await c.moveCamera(CameraUpdate.zoomBy(delta));
      // Tras un zoom programático el callback onCameraIdle puede no dispararse
      // (quirk del plugin Android): emite los bounds visibles explícitamente
      // para que el provider refetchee los reportes del nuevo viewport. Se
      // emite dos veces porque getVisibleRegion puede devolver la región
      // previa al movimiento si la cámara aún no asentó.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _emitVisibleBounds();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await _emitVisibleBounds();
    } catch (_) {
      // Ignorar errores transitorios del controlador nativo
    }
  }

  Future<void> _emitVisibleBounds() async {
    final c = _controller;
    if (c == null) return;
    if (!_mapCreated || !_styleLoaded) return;
    if (widget.onBoundsChanged == null) return;
    try {
      final region = await c.getVisibleRegion();
      widget.onBoundsChanged!(
        LatLngBounds(
          minLat: region.southwest.latitude,
          minLng: region.southwest.longitude,
          maxLat: region.northeast.latitude,
          maxLng: region.northeast.longitude,
        ),
      );
    } catch (_) {
      // Ignorar errores transitorios del controlador nativo
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapLibreMap(
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
        ),
        // Controles de zoom explícitos (§13): complementan el pinch del gesto
        // nativo; usan el mismo controlador, no crean un segundo mapa.
        Positioned(
          right: AppSpacing.md,
          top: AppSpacing.md,
          child: Column(
            children: [
              _ZoomButton(
                key: const Key('map-zoom-in'),
                icon: Icons.add,
                tooltip: 'Acercar',
                onPressed: () => _zoomBy(1.0),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ZoomButton(
                key: const Key('map-zoom-out'),
                icon: Icons.remove,
                tooltip: 'Alejar',
                onPressed: () => _zoomBy(-1.0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Botón circular de zoom sobre el mapa (patrón prototipo §mapa).
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.95),
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: AppColors.primary),
        ),
      ),
    );
  }
}
