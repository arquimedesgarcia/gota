/// Estado visual de un reporte en el mapa y su color asociado.
///
/// El backend solo mantiene `ACTIVE`/`RESOLVED` (migración 00007); el estado
/// "Validada" se deriva en el cliente cuando `validation_count` alcanza el
/// mismo umbral configurado para la resolución comunitaria en
/// `system_config.resolution.threshold` (= 3, migración 00013).
/// Decisión documentada en `docs/MIGRATION_NOTES.md`: no introduce un cuarto
/// status de backend ni altera las reglas de validación/resolución.
library;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../leaks/domain/leak_community.dart';

/// Umbral de validaciones comunitarias para considerar "Validada" un reporte
/// ACTIVE. Debe coincidir con `system_config.resolution.threshold` (00013).
const kValidatedCountThreshold = 3;

/// Estados visuales del marker en el mapa (exactamente tres).
enum LeakMapStatus {
  /// 🔵 Reportada — pendiente de validar.
  reported,

  /// 🔴 Validada — alcanzó el umbral de validación comunitaria.
  validated,

  /// 🟢 Resuelta — confirmada como resuelta por la comunidad.
  resolved,
}

/// Deriva el estado visual de un reporte a partir de los datos del backend.
LeakMapStatus leakMapStatusOf(LeakSummary leak) {
  if (leak.isResolved) return LeakMapStatus.resolved;
  if (leak.validationCount >= kValidatedCountThreshold) {
    return LeakMapStatus.validated;
  }
  return LeakMapStatus.reported;
}

/// Color del marker: activas (reportada/validada)=rojo, resuelta=verde.
/// Solo dos colores visibles en el mapa.
Color leakMapStatusColor(LeakMapStatus status) => switch (status) {
      LeakMapStatus.reported => AppColors.danger,
      LeakMapStatus.validated => AppColors.danger,
      LeakMapStatus.resolved => AppColors.success,
    };

/// Indica si el marker debe mostrar un halo animado (fugas confirmadas).
bool leakMapHasHalo(LeakMapStatus status) =>
    status == LeakMapStatus.validated;

/// Etiqueta corta de la leyenda.
String leakMapStatusLabel(LeakMapStatus status) => switch (status) {
      LeakMapStatus.reported => 'Reportada',
      LeakMapStatus.validated => 'Confirmada',
      LeakMapStatus.resolved => 'Resuelta',
    };
