import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leaks/data/community_summary_repository.dart';
import '../../leaks/domain/community_summary.dart';
import '../../notifications/presentation/notification_providers.dart';

/// Resumen diario "Hoy en tu comunidad" (S10-C).
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
