// Mutation control para R1, R2 y R3 (commit abc71ac).
// Cada test FALLA si se restaura la lógica eliminada y PASA con ella eliminada.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/leaks/data/geolocator_location_service.dart'
    show locationServiceProvider;
import 'package:gota/features/leaks/data/draft_photo_store.dart';
import 'package:gota/features/leaks/data/draft_store.dart';
import 'package:gota/features/leaks/data/leak_report_repository.dart';
import 'package:gota/features/leaks/data/location_service.dart';
import 'package:gota/features/leaks/data/reverse_geocoding_service.dart';
import 'package:gota/features/leaks/domain/create_leak_report_outcome.dart';
import 'package:gota/features/leaks/domain/leak_report_draft.dart';
import 'package:gota/features/leaks/domain/location_suggestion.dart';
import 'package:gota/features/leaks/presentation/leak_report_controller.dart';
import 'package:gota/features/leaks/presentation/leak_report_screen.dart';
import 'package:gota/features/leaks/presentation/location_map_picker.dart';
import 'package:gota/features/location/data/municipality_repository.dart';
import 'package:gota/features/location/data/sector_repository.dart';
import 'package:gota/shared/models/municipality.dart';
import 'package:gota/shared/models/sector.dart';

class _FakeLocationService implements LocationService {
  @override
  Future<({double latitude, double longitude, double? accuracyMeters})>
  getCurrentPosition() async =>
      (latitude: 10.99, longitude: -63.87, accuracyMeters: 12.0);
}

class _FakeReverseGeocoder implements ReverseGeocodingService {
  @override
  Future<LocationSuggestion?> reverse({
    required double latitude,
    required double longitude,
  }) async => LocationSuggestion(
    latitude: latitude,
    longitude: longitude,
    displayText: 'Cerca de La Asunción',
    municipality: 'Municipio Arismendi',
    state: 'Nueva Esparta',
    provider: 'test',
  );
}

class _FakeMunicipalityRepository implements MunicipalityRepository {
  @override
  Future<List<Municipality>> getActive() async => const [
    Municipality(
      id: 'm1',
      name: 'Maneiro',
      state: 'Nueva Esparta',
      country: 'Venezuela',
      isActive: true,
    ),
  ];
}

class _FakeSectorRepository implements SectorRepository {
  @override
  Future<List<Sector>> getByMunicipality(String municipalityId) async => [
    const Sector(
      id: 's1',
      municipalityId: 'm1',
      name: 'La Caranta',
      isActive: true,
    ),
  ];

  @override
  Future<Sector?> getById(String id) async => null;
}

/// Repositorio falso que devuelve un ReportCreated con ID conocido (R3).
class _FakeLeakReportRepository implements LeakReportRepository {
  @override
  Future<CreateLeakReportOutcome> createReport(
    LeakReportDraft draft, {
    bool ignoreDuplicate = false,
  }) async => const ReportCreated(reportId: 'abc-123');
}

ProviderScope _app() => ProviderScope(
  overrides: [
    locationServiceProvider.overrideWithValue(_FakeLocationService()),
    reverseGeocodingServiceProvider.overrideWithValue(_FakeReverseGeocoder()),
    locationMapBuilderProvider.overrideWithValue(
      ({required latitude, required longitude, required onMapTapped}) =>
          const SizedBox(key: Key('fake-location-map')),
    ),
    municipalityRepositoryProvider.overrideWithValue(
      _FakeMunicipalityRepository(),
    ),
    sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
    draftStoreProvider.overrideWithValue(InMemoryDraftStore()),
    draftPhotoStoreProvider.overrideWithValue(InMemoryDraftPhotoStore()),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const LeakReportScreen()),
);

ProviderContainer _container({LeakReportRepository? repository}) {
  final c = ProviderContainer(
    overrides: [
      locationServiceProvider.overrideWithValue(_FakeLocationService()),
      reverseGeocodingServiceProvider.overrideWithValue(_FakeReverseGeocoder()),
      municipalityRepositoryProvider.overrideWithValue(
        _FakeMunicipalityRepository(),
      ),
      sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
      draftStoreProvider.overrideWithValue(InMemoryDraftStore()),
      draftPhotoStoreProvider.overrideWithValue(InMemoryDraftPhotoStore()),
      if (repository != null)
        leakReportRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets(
    'R1: el paso de ubicación no muestra la leyenda descriptiva',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // R1: la leyenda 'Usa tu GPS o indica la zona manualmente…' fue
      // eliminada. Mutación que hace fallar este test: restaurar el Text(...)
      // y el SizedBox(height:4) en leak_report_screen.dart.
      expect(find.textContaining('Usa tu GPS'), findsNothing);
    },
  );

  testWidgets(
    'R2: en el paso de ubicación la dirección queda encima de las coordenadas',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // Pedir GPS → fija location y dispara reverse-geocode.
      await tester.tap(find.text('Usar mi ubicación (GPS)'));
      await tester.pumpAndSettle();

      final addressFinder = find.text('Ubicación aproximada');
      final coordFinder = find.textContaining('Lat:');

      // Los widgets viven en un ListView: asegurar que estén construidos.
      await tester.scrollUntilVisible(
        addressFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        coordFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      final addressDy = tester.getTopLeft(addressFinder).dy;
      final coordDy = tester.getTopLeft(coordFinder).dy;
      expect(
        addressDy,
        lessThan(coordDy),
        reason: 'la dirección debe aparecer ENCIMA de las coordenadas',
      );
    },
  );

  test('R3: el mensaje de confirmación no contiene el GUID del reporte',
      () async {
    final container = _container(repository: _FakeLeakReportRepository());

    final controller = container.read(leakReportProvider.notifier);
    controller.completeDraftForTest(
      photo: const PreparedPhoto(
        id: '1',
        originalPath: '/a',
        compressedPath: '/a_gota.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1000,
        width: 0,
        height: 0,
      ),
      municipalityId: 'm1',
      sectorId: 's1',
    );

    await controller.submit();

    final msg = container.read(leakReportProvider).message ?? '';
    expect(
      msg,
      isNot(contains('abc-123')),
      reason: 'el GUID no debe ser visible al usuario',
    );
    expect(msg, contains('Reporte enviado'));
  });
}
