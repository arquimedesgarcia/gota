import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/sector.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../location/presentation/location_providers.dart';
import 'water_copy.dart';
import 'water_register_controller.dart';

/// Tercer paso: seleccionar sector (del municipio elegido).
class WaterRegisterStepSector extends ConsumerWidget {
  const WaterRegisterStepSector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final municipalityId = ref
        .watch(waterRegisterControllerProvider)
        .municipalityId;

    if (municipalityId == null) {
      return Center(
        child: Text(
          'Selecciona un municipio primero.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final sectorsAsync = ref.watch(sectorsProvider(municipalityId));
    final currentSectorId = ref.watch(waterRegisterControllerProvider).sectorId;

    return sectorsAsync.when(
      loading: () => const LoadingView(message: 'Cargando sectores…'),
      error: (error, _) => ErrorView(
        message: 'No pudimos cargar los sectores.',
        onRetry: () => ref.invalidate(sectorsProvider(municipalityId)),
      ),
      data: (sectors) => _SectorList(
        sectors: sectors,
        selectedId: currentSectorId,
        onSelected: (sector) => ref
            .read(waterRegisterControllerProvider.notifier)
            .selectSector(sector),
      ),
    );
  }
}

class _SectorList extends StatelessWidget {
  const _SectorList({
    required this.sectors,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Sector> sectors;
  final String? selectedId;
  final ValueChanged<Sector> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WaterCopy.stepSector,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (sectors.isEmpty)
          Center(
            child: Text(
              'Sin sectores disponibles.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          for (final s in sectors)
            _SectorTile(
              sector: s,
              isSelected: s.id == selectedId,
              onSelected: () => onSelected(s),
            ),
      ],
    );
  }
}

class _SectorTile extends StatelessWidget {
  const _SectorTile({
    required this.sector,
    required this.isSelected,
    required this.onSelected,
  });

  final Sector sector;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                sector.name,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontWeight: isSelected ? FontWeight.w600 : null),
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}
