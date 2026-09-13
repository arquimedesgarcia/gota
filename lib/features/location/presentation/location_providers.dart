import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/municipality.dart';
import '../../../shared/models/sector.dart';
import '../data/municipality_repository.dart'
    show municipalityRepositoryProvider;
import '../data/sector_repository.dart' show sectorRepositoryProvider;

final municipalitiesProvider = FutureProvider<List<Municipality>>(
  (ref) => ref.watch(municipalityRepositoryProvider).getActive(),
);

/// Municipio seleccionado en la pantalla de datos de ubicación.
final selectedMunicipalityProvider =
    NotifierProvider<SelectedMunicipality, String?>(SelectedMunicipality.new);

class SelectedMunicipality extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String municipalityId) => state = municipalityId;

  void clear() => state = null;
}

final sectorsProvider = FutureProvider.autoDispose.family<List<Sector>, String>(
  (ref, municipalityId) =>
      ref.watch(sectorRepositoryProvider).getByMunicipality(municipalityId),
);

/// Nombre de un sector por id (p. ej. para resolver el sector de interés
/// guardado en preferencias).
final sectorNameProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, sectorId) =>
          ref.watch(sectorRepositoryProvider).getById(sectorId).then(
            (sector) => sector?.name,
          ),
    );
