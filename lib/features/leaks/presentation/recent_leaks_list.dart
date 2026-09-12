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
                child: _LeakTile(leak: leak),
              ),
          ],
        );
      },
    );
  }
}

class _LeakTile extends StatelessWidget {
  const _LeakTile({required this.leak});

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
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LeakDetailScreen(reportId: leak.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                leak.isResolved
                    ? Icons.check_circle_outline
                    : Icons.water_drop_outlined,
                color: leak.isResolved ? AppColors.success : AppColors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.isEmpty ? LeakCommunityCopy.screenTitle : place,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${describeLeakAge(leak.createdAt)} · '
                      '${LeakCommunityCopy.validationCount(leak.validationCount)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(resolved: leak.isResolved),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.resolved});

  final bool resolved;

  @override
  Widget build(BuildContext context) {
    final color = resolved ? AppColors.success : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        resolved ? 'Resuelta' : 'Activa',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
