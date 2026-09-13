import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/models/sector.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../location/presentation/location_providers.dart';
import 'notification_providers.dart';

/// Selección del sector de interés (Sprint 06): municipio + sector. Al
/// guardar vuelve automáticamente a Ajustes.
class SectorSelectionScreen extends ConsumerStatefulWidget {
  const SectorSelectionScreen({super.key});

  @override
  ConsumerState<SectorSelectionScreen> createState() =>
      _SectorSelectionScreenState();
}

class _SectorSelectionScreenState
    extends ConsumerState<SectorSelectionScreen> {
  bool _saving = false;

  void _selectSector(String sectorId) {
    setState(() => _saving = true);
    ref
        .read(notificationPreferencesControllerProvider.notifier)
        .selectSector(sectorId);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationPreferencesControllerProvider, (previous, next) {
      if (!_saving || next is AsyncLoading) return;
      final saveError = ref
          .read(notificationPreferencesControllerProvider.notifier)
          .saveError;
      if (saveError != null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saveError is AppException
                  ? saveError.userMessage
                  : 'No pudimos guardar el sector. Intenta de nuevo.',
            ),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    });

    final municipalities = ref.watch(municipalitiesProvider);
    final selectedMunicipalityId = ref.watch(selectedMunicipalityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Seleccionar sector')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          municipalities.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              message: 'No pudimos cargar los municipios.',
              onRetry: () => ref.invalidate(municipalitiesProvider),
            ),
            data: (municipalities) => DropdownButtonFormField<String>(
              initialValue: selectedMunicipalityId,
              decoration: const InputDecoration(labelText: 'Municipio'),
              items: [
                for (final municipality in municipalities)
                  DropdownMenuItem<String>(
                    value: municipality.id,
                    child: Text(municipality.name),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                ref.read(selectedMunicipalityProvider.notifier).select(id);
              },
            ),
          ),
          const SizedBox(height: 16),
          if (selectedMunicipalityId != null)
            _SectorListView(
              municipalityId: selectedMunicipalityId,
              onSelected: _selectSector,
            )
          else
            Text(
              'Elige un municipio para ver sus sectores.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _SectorListView extends ConsumerWidget {
  const _SectorListView({
    required this.municipalityId,
    required this.onSelected,
  });

  final String municipalityId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectors = ref.watch(sectorsProvider(municipalityId));
    return sectors.when(
      loading: () => const LoadingView(message: 'Cargando sectores…'),
      error: (error, _) => ErrorView(
        message: 'No pudimos cargar los sectores.',
        onRetry: () => ref.invalidate(sectorsProvider(municipalityId)),
      ),
      data: (sectors) => _SectorList(sectors: sectors, onSelected: onSelected),
    );
  }
}

class _SectorList extends StatelessWidget {
  const _SectorList({required this.sectors, required this.onSelected});

  final List<Sector> sectors;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (sectors.isEmpty) {
      return Center(
        child: Text(
          'Sin sectores disponibles.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sector', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final sector in sectors)
          _SectorTile(sector: sector, onSelected: () => onSelected(sector.id)),
      ],
    );
  }
}

class _SectorTile extends ConsumerWidget {
  const _SectorTile({required this.sector, required this.onSelected});

  final Sector sector;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saving = ref.watch(
      notificationPreferencesControllerProvider.select(
        (state) => state.isLoading,
      ),
    );
    return GestureDetector(
      onTap: saving ? null : onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                sector.name,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (saving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
