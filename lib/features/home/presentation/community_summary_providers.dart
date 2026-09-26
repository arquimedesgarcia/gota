import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../leaks/data/community_summary_repository.dart';
import '../../leaks/domain/community_summary.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../water/data/water_event_repository.dart';
import '../../water/domain/water_event.dart';

/// Resumen comunitario de cobertura global del piloto (S10-C, rescope S13).
///
/// Los conteos son SIEMPRE globales (todos los sectores del piloto): no se
/// filtra por el sector de interés del usuario. El filtro por sector queda
/// únicamente en [sectorWaterStatusProvider] (estado del agua).
///
/// Como `HomeScreen` vive en el `IndexedStack`, el provider conserva su
/// estado y solo reconsulta al invalidarse.
final communitySummaryProvider = FutureProvider<CommunitySummary>((ref) {
  return ref
      .watch(communitySummaryRepositoryProvider)
      .todaySummary();
});

/// Estado actual del agua del ámbito efectivo: último evento registrado
/// (llegada o salida) por la comunidad. Es tolerante a fallos: si la
/// consulta falla devuelve `null` y la tarjeta muestra "Sin información",
/// para que un problema secundario no tumbe todo el resumen.
final sectorWaterStatusProvider =
    FutureProvider<WaterEventSummary?>((ref) async {
  final prefs = await ref.watch(notificationPreferencesProvider.future);
  try {
    return await ref
        .watch(waterEventRepositoryProvider)
        .latestEvent(sectorId: prefs?.preferredSectorId);
  } on AppException {
    return null;
  } on TimeoutException {
    return null;
  } on SocketException {
    return null;
  }
});
