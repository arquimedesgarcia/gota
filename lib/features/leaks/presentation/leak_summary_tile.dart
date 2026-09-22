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
/// (`RecentActivityCard`). Icono y color por estado (resuelto → check verde;
/// activo → gota acento), lugar, línea `antigüedad · validaciones` y badge de
/// estado. Al tocarla abre el detalle, donde viven las acciones comunitarias.
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
              leak.isResolved
                  ? StatusBadgePresets.resolved(context)
                  : StatusBadgePresets.active(context),
            ],
          ),
        ),
      ),
    );
  }
}
