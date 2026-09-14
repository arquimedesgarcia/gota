import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Badge de estado reutilizable (Activa, Resuelta, etc.).
/// Muestra estado con color semántico + texto (nunca solo color).
/// Especificación: DESIGN_SYSTEM.md §5 "Estados".
class GotaStatusBadge extends StatelessWidget {
  const GotaStatusBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  /// Texto del badge (ej. "Resuelta", "Activa", "Pendiente").
  final String label;

  /// Color de fondo (con 8-12% opacity aplicada internamente).
  final Color backgroundColor;

  /// Color del texto (semántico: debe contrastar con bg).
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Presets de badges semánticos para estados comunes.
abstract final class StatusBadgePresets {
  static Widget resolved(BuildContext context) => GotaStatusBadge(
    label: 'Resuelta',
    backgroundColor: AppColors.success,
    textColor: AppColors.success,
  );

  static Widget active(BuildContext context) => GotaStatusBadge(
    label: 'Activa',
    backgroundColor: AppColors.danger,
    textColor: AppColors.danger,
  );

  static Widget pending(BuildContext context) => GotaStatusBadge(
    label: 'Pendiente',
    backgroundColor: AppColors.warning,
    textColor: AppColors.warning,
  );
}
