import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/leak_community_repository.dart';
import '../domain/community_activity.dart';

/// Última actividad comunitaria global para la tarjeta "Actividad reciente"
/// del Home (docs/FUNCTIONAL_SPEC.md §2).
///
/// Tolerante a fallos: un problema secundario devuelve `null` (la tarjeta
/// muestra "Sin actividad reciente") en lugar de tumbar el Home. Replica el
/// patrón de `sectorWaterStatusProvider`.
final latestActivityProvider = FutureProvider<CommunityActivity?>((ref) async {
  try {
    return await ref.watch(leakCommunityRepositoryProvider).latestActivity();
  } catch (_) {
    return null;
  }
});
