import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/leak_community_repository.dart';
import '../domain/leak_community.dart';

/// Fugas recientes para Inicio ("Fugas cerca de ti", FUNCTIONAL_SPEC §2).
final recentLeaksProvider = FutureProvider<List<LeakSummary>>(
  (ref) => ref.watch(leakCommunityRepositoryProvider).recentReports(),
);

/// Detalle de una fuga con el estado del usuario actual (¿ya validó?,
/// ¿ya confirmó?, ¿es el creador?). La respuesta viene del backend.
final leakDetailProvider = FutureProvider.family<LeakDetail, String>(
  (ref, reportId) =>
      ref.watch(leakCommunityRepositoryProvider).reportDetail(reportId),
);
