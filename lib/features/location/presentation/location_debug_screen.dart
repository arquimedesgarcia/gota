import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import 'location_providers.dart';

/// Pantalla de diagnóstico: lista los municipios y, al seleccionar uno,
/// sus sectores. Sirve para verificar la conexión con Supabase.
class LocationDebugScreen extends ConsumerWidget {
  const LocationDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final municipalities = ref.watch(municipalitiesProvider);
    final selectedId = ref.watch(selectedMunicipalityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Datos de ubicación')),
      body: municipalities.when(
        loading: () => const LoadingView(message: 'Cargando municipios…'),
        error: (error, _) => ErrorView(
          message: error is AppException ? error.userMessage : '$error',
          onRetry: () => ref.invalidate(municipalitiesProvider),
        ),
        data: (municipalities) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final municipality in municipalities)
              Card(
                child: ListTile(
                  title: Text(municipality.name),
                  subtitle: Text(municipality.state),
                  trailing: selectedId == municipality.id
                      ? const Icon(Icons.expand_less)
                      : const Icon(Icons.expand_more),
                  onTap: () {
                    final notifier = ref.read(
                      selectedMunicipalityProvider.notifier,
                    );
                    if (selectedId == municipality.id) {
                      notifier.clear();
                    } else {
                      notifier.select(municipality.id);
                    }
                  },
                ),
              ),
            if (selectedId != null) ...[
              const SizedBox(height: 16),
              Text('Sectores', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _SectorsList(municipalityId: selectedId),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectorsList extends ConsumerWidget {
  const _SectorsList({required this.municipalityId});

  final String municipalityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectors = ref.watch(sectorsProvider(municipalityId));
    return sectors.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingView(),
      ),
      error: (error, _) => ErrorView(
        message: error is AppException ? error.userMessage : '$error',
        onRetry: () => ref.invalidate(sectorsProvider(municipalityId)),
      ),
      data: (sectors) => sectors.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Sin datos todavía'),
            )
          : Column(
              children: [
                for (final sector in sectors)
                  Card(child: ListTile(dense: true, title: Text(sector.name))),
              ],
            ),
    );
  }
}
