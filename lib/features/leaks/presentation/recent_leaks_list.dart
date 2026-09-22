import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import 'leak_community_microcopy.dart';
import 'leak_community_providers.dart';
import 'leak_summary_tile.dart';

// `leakTileKey` vive en leak_summary_tile.dart junto al widget que lo usa; se
// reexporta aquí para no romper los tests e imports que lo toman de este
// archivo.
export 'leak_summary_tile.dart' show LeakSummaryTile, leakTileKey;

const recentLeaksRetryKey = Key('recent-leaks-retry');

/// Lista de fugas recientes de Inicio ("Fugas cerca de ti",
/// docs/FUNCTIONAL_SPEC.md §2). Es la entrada al detalle, donde viven las
/// acciones comunitarias de Sprint 03.
class RecentLeaksList extends ConsumerWidget {
  const RecentLeaksList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaksAsync = ref.watch(recentLeaksProvider);

    return leaksAsync.when(
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
                'Cargando fugas…',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                LeakCommunityCopy.listError,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: recentLeaksRetryKey,
                onPressed: () => ref.invalidate(recentLeaksProvider),
                child: const Text(LeakCommunityCopy.retry),
              ),
            ],
          ),
        ),
      ),
      data: (leaks) {
        if (leaks.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                LeakCommunityCopy.emptyList,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          );
        }

        return Column(
          children: [
            for (final leak in leaks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LeakSummaryTile(leak: leak),
              ),
          ],
        );
      },
    );
  }
}
