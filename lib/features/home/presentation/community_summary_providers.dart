import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leaks/data/community_summary_repository.dart';
import '../../leaks/domain/community_summary.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../water/data/water_event_repository.dart';
import '../../water/domain/water_event.dart';

/// Resumen "Hoy en tu comunidad" (S10-C), ampliado con los acumulados de
/// fallas activas (reportadas + validadas, umbral comunitario del mapa).
///
/// El ámbito efectivo sale de las preferencias existentes: sector de
/// interés cuando hay uno, cobertura global del piloto cuando no.
/// Como `HomeScreen` vive en el `IndexedStack`, el provider conserva su
/// estado y solo reconsulta al invalidarse (retorno `true` del flujo de
/// Reportar, reintento manual), igual que `recentLeaksProvider` (S10-B).
final communitySummaryProvider = FutureProvider<CommunitySummary>((ref) async {
  final prefs = await ref.watch(notificationPreferencesProvider.future);
  return ref
      .watch(communitySummaryRepositoryProvider)
      .todaySummary(sectorId: prefs?.preferredSectorId);
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
  } catch (_) {
    return null;
  }
});
