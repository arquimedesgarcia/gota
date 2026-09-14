import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Estilos reutilizables para componentes comunes (botones, cards).
/// Reduce duplicación de código y asegura consistencia visual.
abstract final class AppComponents {
  /// Botón primario (relleno, acción principal).
  /// Usado en: Reportar fuga, Validar, Confirmar, Siguiente.
  static ButtonStyle primaryButtonStyle() => FilledButton.styleFrom(
    backgroundColor: AppColors.accent,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    padding: EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  );

  /// Botón secundario (outline, acción alternativa).
  /// Usado en: Cancelar, Marcar como resuelta, Anterior.
  static ButtonStyle secondaryButtonStyle() => OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    side: const BorderSide(color: AppColors.primary, width: 1.5),
    minimumSize: const Size.fromHeight(48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    padding: EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  );

  /// Botón grande para acciones prominentes.
  /// Usado en: Llegó / Se fue (Water events).
  static ButtonStyle largeButtonStyle({Color? backgroundColor}) =>
      FilledButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(64),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
      );

  /// Botón pequeño/compacto.
  /// Usado en: Filtros, acciones de tarjetas, etc.
  static ButtonStyle compactButtonStyle() => FilledButton.styleFrom(
    minimumSize: const Size(48, 48),
    padding: EdgeInsets.all(AppSpacing.sm),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
  );
}
