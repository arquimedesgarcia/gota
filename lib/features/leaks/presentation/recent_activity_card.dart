import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/community_activity.dart';
import '../domain/leak_community.dart';
import 'leak_community_microcopy.dart';
import 'leak_summary_tile.dart';
import 'recent_activity_providers.dart';

/// Clave estable del botón de reintento (pruebas de UI).
const recentActivityRetryKey = Key('recent-activity-retry');

/// Tarjeta "Actividad reciente" del Home (docs/FUNCTIONAL_SPEC.md §2): una
/// sola fila con el último evento comunitario global sobre fallas
/// (REPORTED / VALIDATED / RESOLVED, el más reciente en el tiempo).
///
/// Nunca se oculta: sin actividad o ante un error muestra el texto de respaldo
/// "Sin actividad reciente", para que el bloque no aparezca y desaparezca
/// entre refrescos.
class RecentActivityCard extends ConsumerWidget {
  const RecentActivityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(latestActivityProvider);

    return activityAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text(
                'Cargando actividad…',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      // El provider es tolerante a fallos (devuelve null), así que en producción
      // este `error` casi no ocurre; se mantiene para no anunciar éxito ante un
      // fallo inesperado y ofrecer reintento.
      error: (_, _) => _fallback(ref, withRetry: true),
      data: (activity) =>
          activity == null ? _fallback(ref) : _withData(context, activity),
    );
  }

  Widget _withData(BuildContext context, CommunityActivity activity) {
    // Se reutiliza la fila del listado. El estado visual (resuelto/activo) sale
    // del `status` REAL de la falla, no del tipo de evento: un REPORTED o un
    // VALIDATED de una falla que sigue ACTIVE se pinta como activa.
    final leak = LeakSummary(
      id: activity.reportId,
      status: activity.status,
      validationCount: activity.validationCount,
      resolutionConfirmationCount: activity.resolutionConfirmationCount,
      createdAt: activity.createdAt,
      resolvedAt: activity.resolvedAt,
      description: activity.description,
      sectorName: activity.sectorName,
      municipalityName: activity.municipalityName,
      sectorId: activity.sectorId,
      municipalityId: activity.municipalityId,
    );

    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actividad reciente',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            LeakSummaryTile(leak: leak),
          ],
        ),
      ),
    );
  }

  Widget _fallback(WidgetRef ref, {bool withRetry = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sin actividad reciente',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            if (withRetry) ...[
              const SizedBox(height: 8),
              TextButton(
                key: recentActivityRetryKey,
                onPressed: () => ref.invalidate(latestActivityProvider),
                child: const Text(LeakCommunityCopy.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
