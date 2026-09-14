import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Tile de icono cuadrado reutilizable (patrón del prototipo §agua/
/// notificaciones): contenedor de 32dp con icono teñido, usado dentro de
/// tarjetas de eventos y notificaciones. Asegura coherencia del patrón
/// "icon-enco-caja" sin duplicar decoraciones por pantalla.
class GotaIconTile extends StatelessWidget {
  const GotaIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 32,
  });

  final IconData icon;

  /// Color semántico del icono; el fondo se deriva como tinte 12%.
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: color, size: size * 0.6),
    );
  }
}
