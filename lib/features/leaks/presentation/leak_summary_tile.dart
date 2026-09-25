import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/gota_status_badge.dart';
import '../domain/leak_age.dart';
import '../domain/leak_community.dart';
import 'leak_community_microcopy.dart';
import 'leak_detail_screen.dart';

/// Clave estable de cada fuga en la lista (pruebas de UI).
Key leakTileKey(String reportId) => ValueKey('leak-tile-$reportId');

/// Fila reutilizable de una falla: la usan tanto la lista de Inicio
/// (`RecentLeaksList`) como la tarjeta "Actividad reciente"
/// (`RecentActivityCard`). Miniatura de estado, lugar, antigüedad y badge.
/// Al tocarla abre el detalle con las acciones comunitarias.
class LeakSummaryTile extends StatelessWidget {
  const LeakSummaryTile({super.key, required this.leak});

  final LeakSummary leak;

  @override
  Widget build(BuildContext context) {
    final place = [
      if (leak.sectorName != null) leak.sectorName!,
      if (leak.municipalityName != null) leak.municipalityName!,
    ].join(' · ');

    return Card(
      child: InkWell(
        key: leakTileKey(leak.id),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LeakDetailScreen(reportId: leak.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeakThumbnail(leak: leak),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: leak.isResolved
                                ? AppColors.success
                                : AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        leak.isResolved
                            ? StatusBadgePresets.resolved(context)
                            : StatusBadgePresets.active(context),
                        const Spacer(),
                        Text(
                          describeLeakAge(leak.createdAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      place.isEmpty ? LeakCommunityCopy.screenTitle : place,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      LeakCommunityCopy.validationCount(leak.validationCount),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeakThumbnail extends StatelessWidget {
  const _LeakThumbnail({required this.leak});

  final LeakSummary leak;
  static const double size = 64.0;

  @override
  Widget build(BuildContext context) {
    final color = leak.isResolved ? AppColors.success : AppColors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(
        leak.isResolved ? Icons.check_circle_outline : Icons.water_drop_outlined,
        color: color.withValues(alpha: 0.75),
        size: size * 0.44,
      ),
    );
  }
}
