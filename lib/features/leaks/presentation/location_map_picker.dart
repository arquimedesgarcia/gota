import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/app_theme.dart';
import '../../map/presentation/widgets/gota_map_view.dart';

/// Renderizador aislado para que la pantalla de reporte no dependa de la
/// implementación concreta de MapLibre en sus pruebas.
typedef LocationMapBuilder = Widget Function({
  required double latitude,
  required double longitude,
  required ValueChanged<LatLng> onMapTapped,
});

final locationMapBuilderProvider = Provider<LocationMapBuilder>((ref) {
  return ({required latitude, required longitude, required onMapTapped}) =>
      _LocationMap(
        latitude: latitude,
        longitude: longitude,
        onMapTapped: onMapTapped,
      );
});

class _LocationMap extends StatefulWidget {
  const _LocationMap({
    required this.latitude,
    required this.longitude,
    required this.onMapTapped,
  });

  final double latitude;
  final double longitude;
  final ValueChanged<LatLng> onMapTapped;

  @override
  State<_LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<_LocationMap> {
  MapLibreMapController? _controller;
  Circle? _marker;

  Future<void> _drawMarker() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (_marker != null) await controller.removeCircle(_marker!);
      _marker = await controller.addCircle(
        CircleOptions(
          geometry: LatLng(widget.latitude, widget.longitude),
          circleColor: _colorToHex(AppColors.danger),
          circleRadius: 10,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );
    } catch (_) {
      // El mapa es una ayuda visual; no debe bloquear el reporte.
    }
  }

  @override
  void didUpdateWidget(covariant _LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _drawMarker();
      _controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(widget.latitude, widget.longitude)),
      );
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: MapLibreMap(
        styleString: kMapLibreDefaultStyle,
        initialCameraPosition: CameraPosition(
          target: LatLng(widget.latitude, widget.longitude),
          zoom: 16,
        ),
        onMapCreated: (controller) {
          _controller = controller;
        },
        onMapClick: (_, point) => widget.onMapTapped(point),
        onStyleLoadedCallback: _drawMarker,
        myLocationEnabled: false,
        trackCameraPosition: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }
}
