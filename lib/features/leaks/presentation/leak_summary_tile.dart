import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/leak_age.dart';
import '../domain/leak_community.dart';
import 'leak_community_microcopy.dart';
import 'leak_community_providers.dart';
import 'leak_detail_screen.dart';

/// Clave estable de cada fuga en la lista (pruebas de UI).
Key leakTileKey(String reportId) => ValueKey('leak-tile-$reportId');

/// Fila reutilizable de una falla: la usan tanto la lista de Inicio
/// (`RecentLeaksList`) como la tarjeta "Actividad reciente"
/// (`RecentActivityCard`). Miniatura de estado, lugar, antigüedad y badge.
/// Al tocarla abre el detalle con las acciones comunitarias.
class LeakSummaryTile extends ConsumerWidget {
  const LeakSummaryTile({super.key, required this.leak});

  final LeakSummary leak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = [
      if (leak.sectorName != null) leak.sectorName!,
      if (leak.municipalityName != null) leak.municipalityName!,
    ].join(' · ');

    // Carga la primera foto en segundo plano; el placeholder queda hasta que
    // llega (o si no hay fotos). CachedNetworkImage persiste en disco.
    final photosAsync = ref.watch(leakPhotosProvider(leak.id));
    final firstThumb = photosAsync.value?.isNotEmpty == true
        ? photosAsync.value!.first.displayThumbnailUrl
        : null;

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
              _LeakThumbnail(leak: leak, thumbnailUrl: firstThumb),
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
                        Text(
                          leak.isResolved ? 'Resuelta' : 'Activa',
                          style: TextStyle(
                            color: leak.isResolved
                                ? AppColors.success
                                : AppColors.danger,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
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
  const _LeakThumbnail({required this.leak, this.thumbnailUrl});

  final LeakSummary leak;
  final String? thumbnailUrl;
  static const double size = 64.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: size,
        height: size,
        child: thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => _placeholder(),
                errorWidget: (_, _, _) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surface,
      child: Icon(
        leak.isResolved ? Icons.check_circle_outline : Icons.water_drop_outlined,
        size: size * 0.45,
        color: AppColors.textMuted,
      ),
    );
  }
}
