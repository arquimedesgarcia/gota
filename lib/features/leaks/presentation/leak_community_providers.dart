import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/leak_community_repository.dart';
import '../data/leak_photo_repository.dart';
import '../domain/leak_community.dart';
import '../domain/leak_photo.dart';

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

/// Fotos de un reporte (signed URLs, Sprint 13).
///
/// Se invalida externamente cuando se sospecha que las URLs han expirado.
/// La renovación la inicia el widget al detectar [LeakPhoto.isExpiringSoon].
final leakPhotosProvider = FutureProvider.family<List<LeakPhoto>, String>(
  (ref, reportId) =>
      ref.watch(leakPhotoRepositoryProvider).getPhotos(reportId),
);
