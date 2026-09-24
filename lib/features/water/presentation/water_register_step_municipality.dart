import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/municipality.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../location/presentation/location_providers.dart';
import 'water_copy.dart';
import 'water_register_controller.dart';

/// Segundo paso: seleccionar municipio.
class WaterRegisterStepMunicipality extends ConsumerWidget {
  const WaterRegisterStepMunicipality({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final municipalitiesAsync = ref.watch(municipalitiesProvider);
    final currentMunicipalityId = ref
        .watch(waterRegisterControllerProvider)
        .municipalityId;

    return municipalitiesAsync.when(
      loading: () => const LoadingView(message: 'Cargando municipios…'),
      error: (error, _) => ErrorView(
        message: 'No pudimos cargar los municipios.',
        onRetry: () => ref.invalidate(municipalitiesProvider),
      ),
      data: (municipalities) => _MunicipalityList(
        municipalities: municipalities,
        selectedId: currentMunicipalityId,
        onSelected: (municipality) => ref
            .read(waterRegisterControllerProvider.notifier)
            .selectMunicipality(municipality),
      ),
    );
  }
}

class _MunicipalityList extends StatelessWidget {
  const _MunicipalityList({
    required this.municipalities,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Municipality> municipalities;
  final String? selectedId;
  final ValueChanged<Municipality> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WaterCopy.stepMunicipality,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final m in municipalities)
          _MunicipalityTile(
            municipality: m,
            isSelected: m.id == selectedId,
            onSelected: () => onSelected(m),
          ),
      ],
    );
  }
}

class _MunicipalityTile extends StatelessWidget {
  const _MunicipalityTile({
    required this.municipality,
    required this.isSelected,
    required this.onSelected,
  });

  final Municipality municipality;
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
                municipality.name,
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
