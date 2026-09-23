import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/leaks/data/geolocator_location_service.dart'
    show locationServiceProvider;
import 'package:gota/features/leaks/data/location_service.dart';
import 'package:gota/features/leaks/data/photo_service.dart';
import 'package:gota/features/leaks/data/reverse_geocoding_service.dart';
import 'package:gota/features/leaks/domain/leak_errors.dart';
import 'package:gota/features/leaks/domain/leak_report_draft.dart';
import 'package:gota/features/leaks/domain/location_source.dart';
import 'package:gota/features/leaks/domain/location_suggestion.dart';
import 'package:gota/features/leaks/presentation/leak_report_controller.dart';
import 'package:gota/features/leaks/presentation/location_map_picker.dart';
import 'package:gota/features/leaks/presentation/leak_report_screen.dart';
import 'package:gota/features/location/data/municipality_repository.dart';
import 'package:gota/features/location/data/sector_repository.dart';
import 'package:gota/shared/models/municipality.dart';
import 'package:gota/shared/models/sector.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService({this.error});

  final LeakFlowException? error;

  @override
  Future<({double latitude, double longitude, double? accuracyMeters})>
  getCurrentPosition() async {
    if (error != null) throw error!;
    return (latitude: 10.99, longitude: -63.87, accuracyMeters: 12.0);
  }
}

typedef _GeocoderBuilder =
    LocationSuggestion? Function(double lat, double lng);

class _FakeReverseGeocoder implements ReverseGeocodingService {
  _FakeReverseGeocoder({this._builder, this._fails = false});

  final _GeocoderBuilder? _builder;
  final bool _fails;

  @override
  Future<LocationSuggestion?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    if (_fails) throw const ReverseGeocodingException();
    final b = _builder;
    if (b != null) return b(latitude, longitude);
    return LocationSuggestion(
      latitude: latitude,
      longitude: longitude,
      displayText: 'Cerca de La Asunción',
      municipality: 'Municipio Arismendi',
      state: 'Nueva Esparta',
      provider: 'test',
    );
  }
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

ProviderScope _app({
  LeakFlowException? gpsError,
  ReverseGeocodingService? geocoder,
}) => ProviderScope(
  overrides: [
    locationServiceProvider.overrideWithValue(
      _FakeLocationService(error: gpsError),
    ),
    reverseGeocodingServiceProvider.overrideWithValue(
      geocoder ?? _FakeReverseGeocoder(),
    ),
    locationMapBuilderProvider.overrideWithValue(
      ({required latitude, required longitude, required onMapTapped}) =>
          const SizedBox(key: Key('fake-location-map')),
    ),
    municipalityRepositoryProvider.overrideWithValue(
      _FakeMunicipalityRepository(),
    ),
    sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const LeakReportScreen()),
);

/// Crea un ProviderContainer standalone para tests de controller sin widgets.
ProviderContainer _container({ReverseGeocodingService? geocoder}) {
  final c = ProviderContainer(
    overrides: [
      locationServiceProvider.overrideWithValue(_FakeLocationService()),
      reverseGeocodingServiceProvider.overrideWithValue(
        geocoder ?? _FakeReverseGeocoder(),
      ),
      municipalityRepositoryProvider.overrideWithValue(
        _FakeMunicipalityRepository(),
      ),
      sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
    ],
  );
  return c;
}

void main() {
  testWidgets('flujo completo con GPS: ubicación → fotos → datos → revisar', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Etapa 1: ubicación.
    expect(find.text('¿Dónde está la fuga?'), findsOneWidget);
    await tester.tap(find.text('Usar mi ubicación (GPS)'));
    await tester.pumpAndSettle();

    expect(find.text('Ubicación por GPS'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Etapa 2: fotos. Sin fotos, continuar avisa mínimo 1.
    // kReportPhotoMaxCount fue reducido a 2 (C1); las cadenas reflejan el nuevo límite.
    expect(find.text('Agrega de 1 a 2 fotos de la fuga'), findsOneWidget);
    expect(find.text('Fotos agregadas: 0 de 2'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Necesitas al menos 1 foto para continuar.'),
      findsOneWidget,
    );
  });

  testWidgets('GPS denegado muestra mensaje con opción manual', (tester) async {
    await tester.pumpWidget(
      _app(gpsError: const LocationPermissionDeniedException()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usar mi ubicación (GPS)'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No tenemos permiso para usar tu GPS'),
      findsOneWidget,
    );
    // La UI nunca asume que GPS funcionó: no aparece ninguna etiqueta GPS.
    expect(find.text('Ubicación por GPS'), findsNothing);
  });

  testWidgets('GPS apagado muestra feedback visible', (tester) async {
    await tester.pumpWidget(
      _app(gpsError: const LocationServiceOffException()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar mi ubicación (GPS)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GPS parece estar apagado'), findsOneWidget);
  });

  testWidgets('ubicación no disponible muestra feedback visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(gpsError: const LocationUnavailableException()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar mi ubicación (GPS)'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No pudimos obtener tu ubicación'),
      findsOneWidget,
    );
  });

  testWidgets('manual: la fuente visible es "Ubicación manual"', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indicar ubicación manual'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Latitud'), '10.99');
    await tester.enterText(
      find.widgetWithText(TextField, 'Longitud'),
      '-63.87',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Ubicación manual'), findsOneWidget);
    expect(find.text('Ubicación por GPS'), findsNothing);
  });

  testWidgets('estado inicial muestra carga de municipios y sin GPS', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // La pantalla de ubicación no asume GPS ya obtenido.
    expect(find.textContaining('Sin ubicación todavía'), findsOneWidget);
  });

  // ── B1: tests de controller ───────────────────────────────────────────────

  // B1-01: municipality text matches catalog → suggestedMunicipalityId set.
  test('B1-01: suggestion.municipality coincide con catálogo → suggestedMunicipalityId', () async {
    final c = _container(
      geocoder: _FakeReverseGeocoder(
        builder: (lat, lng) => LocationSuggestion(
          latitude: lat,
          longitude: lng,
          municipality: 'Maneiro',
          locality: 'La Caranta',
          provider: 'test',
        ),
      ),
    );
    addTearDown(c.dispose);

    await c.read(leakReportProvider.notifier).requestGps();

    final state = c.read(leakReportProvider);
    expect(state.suggestedMunicipalityId, 'm1');
    expect(state.suggestedSectorId, 's1');
    // Draft NOT mutated by suggestion.
    expect(state.draft.municipalityId, isNull);
    expect(state.draft.sectorId, isNull);
  });

  // B1-02: no match → suggestedMunicipalityId null, no crash.
  test('B1-02: sin match → suggestedMunicipalityId null, sin excepción', () async {
    // Default geocoder returns 'Municipio Arismendi' — no match in fake repo.
    final c = _container();
    addTearDown(c.dispose);

    await c.read(leakReportProvider.notifier).requestGps();

    final state = c.read(leakReportProvider);
    expect(state.suggestedMunicipalityId, isNull);
    expect(state.suggestedSectorId, isNull);
    // GPS location still set.
    expect(state.draft.location?.latitude, 10.99);
  });

  // B1-03: user called selectMunicipality before DataStep → draft takes
  // precedence in UI (suggestedMunicipalityId may still be set in state,
  // but the effective value in the dropdown is draft.municipalityId).
  test('B1-03: selectMunicipality previo → draft.municipalityId tiene precedencia', () async {
    final c = _container(
      geocoder: _FakeReverseGeocoder(
        builder: (lat, lng) => LocationSuggestion(
          latitude: lat,
          longitude: lng,
          municipality: 'Maneiro',
          provider: 'test',
        ),
      ),
    );
    addTearDown(c.dispose);

    c.read(leakReportProvider.notifier).selectMunicipality('other-m');
    await c.read(leakReportProvider.notifier).requestGps();

    final state = c.read(leakReportProvider);
    // suggestedMunicipalityId is computed from suggestion (Maneiro → m1),
    // but draft.municipalityId retains the explicit user choice.
    expect(state.draft.municipalityId, 'other-m');
    // The effective dropdown value (draft ?? suggested) = 'other-m'.
    final effectiveId = state.draft.municipalityId ?? state.suggestedMunicipalityId;
    expect(effectiveId, 'other-m');
  });

  // B1-04: locationSuggestion null (geocoder returned null) → no crash.
  test('B1-04: locationSuggestion null → flujo continúa sin excepción', () async {
    final c = _container(
      geocoder: _FakeReverseGeocoder(fails: true),
    );
    addTearDown(c.dispose);

    await c.read(leakReportProvider.notifier).requestGps();

    final state = c.read(leakReportProvider);
    expect(state.locationSuggestion, isNull);
    expect(state.suggestedMunicipalityId, isNull);
    expect(state.draft.location?.latitude, 10.99);
  });

  // B1-05: incomplete suggestion with no municipality → matching skipped.
  test('B1-05: sugerencia incompleta sin municipality → suggestedMunicipalityId null', () async {
    final c = _container(
      geocoder: _FakeReverseGeocoder(
        builder: (lat, lng) => LocationSuggestion(
          latitude: lat,
          longitude: lng,
          incomplete: true,
          // municipality is null
          provider: 'test',
        ),
      ),
    );
    addTearDown(c.dispose);

    await c.read(leakReportProvider.notifier).requestGps();

    expect(c.read(leakReportProvider).suggestedMunicipalityId, isNull);
  });

  // B1-06: suggestedSectorId only applies when active municipality equals
  // suggestedMunicipalityId.
  test('B1-06: suggestedSectorId ignorado si municipio activo ≠ suggestedMunicipalityId', () async {
    final c = _container(
      geocoder: _FakeReverseGeocoder(
        builder: (lat, lng) => LocationSuggestion(
          latitude: lat,
          longitude: lng,
          municipality: 'Maneiro',
          locality: 'La Caranta',
          provider: 'test',
        ),
      ),
    );
    addTearDown(c.dispose);

    await c.read(leakReportProvider.notifier).requestGps();

    final state = c.read(leakReportProvider);
    expect(state.suggestedMunicipalityId, 'm1');
    expect(state.suggestedSectorId, 's1');

    // Effective sector when active municipality is DIFFERENT from suggested:
    const differentMunicipalityId = 'other-m';
    final effectiveSectorId = state.draft.sectorId ??
        (differentMunicipalityId == state.suggestedMunicipalityId
            ? state.suggestedSectorId
            : null);
    expect(effectiveSectorId, isNull);
  });

  // GPS coordinate preservation (part of spec invariant).
  test('B1: coordenadas GPS del draft son exactamente las del receptor', () async {
    final c = _container(
      geocoder: _FakeReverseGeocoder(
        builder: (lat, lng) => LocationSuggestion(
          latitude: lat + 0.5,
          longitude: lng - 0.5,
          municipality: 'Maneiro',
          provider: 'test',
        ),
      ),
    );
    addTearDown(c.dispose);

    await c.read(leakReportProvider.notifier).requestGps();

    final loc = c.read(leakReportProvider).draft.location!;
    expect(loc.latitude, 10.99);
    expect(loc.longitude, -63.87);
    expect(loc.source, LocationSource.gps);
  });

  // ── Fotos: seam C0 ───────────────────────────────────────────────────────

  test('agregar foto cuando el servicio lanza Error no cierra el flujo y muestra banner', () async {
    // Requiere el seam C0 (photoServiceProvider); antes era imposible sin device.
    final c = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        reverseGeocodingServiceProvider.overrideWithValue(_FakeReverseGeocoder()),
        municipalityRepositoryProvider.overrideWithValue(_FakeMunicipalityRepository()),
        sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
        photoServiceProvider.overrideWithValue(_ExplodingPhotoService()),
      ],
    );
    addTearDown(c.dispose);

    await c.read(leakReportProvider.notifier).addPhoto(fromCamera: false);

    final state = c.read(leakReportProvider);
    expect(state.message, isNotNull, reason: 'debe mostrar banner de error');
    expect(
      state.message,
      contains('No pudimos procesar esa foto'),
      reason: 'el mensaje debe ser el mensaje tipado, no un stack trace técnico',
    );
    expect(state.draft.photos, isEmpty, reason: 'no debe agregar la foto al draft');
  });

  test('el máximo de fotos es 2', () async {
    final c = _container();
    addTearDown(c.dispose);

    final notifier = c.read(leakReportProvider.notifier);
    final syntheticPhoto = PreparedPhoto(
      id: 'test-1',
      originalPath: '/tmp/a.jpg',
      compressedPath: '/tmp/a_gota.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      width: 0,
      height: 0,
    );
    notifier.addPreparedPhotoForTest(syntheticPhoto);
    notifier.addPreparedPhotoForTest(
      PreparedPhoto(
        id: 'test-2',
        originalPath: '/tmp/b.jpg',
        compressedPath: '/tmp/b_gota.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        width: 0,
        height: 0,
      ),
    );
    expect(c.read(leakReportProvider).draft.photos.length, 2);

    // Intentar agregar una tercera foto debe rechazarla antes de llamar al servicio.
    await notifier.addPhoto(fromCamera: false);

    final state = c.read(leakReportProvider);
    expect(state.draft.photos.length, 2, reason: 'no debe superar 2');
    expect(
      state.message,
      contains('máximo de 2 fotos'),
      reason: 'debe mostrar el mensaje del contrato',
    );
  });

    // ── T1-T4: tests de widget para la preselección GPS ─────────────────

  testWidgets('T1: preselección GPS habilita Continuar (widget)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        reverseGeocodingServiceProvider.overrideWithValue(
          _FakeReverseGeocoder(
            builder: (lat, lng) => LocationSuggestion(
              latitude: lat,
              longitude: lng,
              municipality: 'Maneiro',
              locality: 'La Caranta',
              provider: 'test',
            ),
          ),
        ),
        municipalityRepositoryProvider.overrideWithValue(
          _FakeMunicipalityRepository(),
        ),
        sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
        locationMapBuilderProvider.overrideWithValue(
          ({required latitude, required longitude, required onMapTapped}) =>
              const SizedBox(key: Key('fake-location-map')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const LeakReportScreen()),
      ),
    );
    await tester.pump();

    final controller = container.read(leakReportProvider.notifier);
    await controller.requestGps();
    controller.goTo(ReportStep.data);
    await tester.pump();

    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continuar'),
      ).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'T2: pulsar Continuar con preselección escribe el borrador y avanza',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(_FakeLocationService()),
          reverseGeocodingServiceProvider.overrideWithValue(
            _FakeReverseGeocoder(
              builder: (lat, lng) => LocationSuggestion(
                latitude: lat,
                longitude: lng,
                municipality: 'Maneiro',
                locality: 'La Caranta',
                provider: 'test',
              ),
            ),
          ),
          municipalityRepositoryProvider.overrideWithValue(
            _FakeMunicipalityRepository(),
          ),
          sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
          locationMapBuilderProvider.overrideWithValue(
            ({required latitude, required longitude, required onMapTapped}) =>
                const SizedBox(key: Key('fake-location-map')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: AppTheme.light, home: const LeakReportScreen()),
        ),
      );
      await tester.pump();

      final controller = container.read(leakReportProvider.notifier);
      await controller.requestGps();
      controller.goTo(ReportStep.data);
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pump();

      expect(container.read(leakReportProvider).draft.municipalityId, 'm1');
      expect(container.read(leakReportProvider).draft.sectorId, 's1');
      expect(
        find.widgetWithText(FilledButton, 'Continuar'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'T3: sin sugerencia el botón Continuar sigue deshabilitado (widget)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(_FakeLocationService()),
          reverseGeocodingServiceProvider.overrideWithValue(
            _FakeReverseGeocoder(
              builder: (lat, lng) => LocationSuggestion(
                latitude: lat,
                longitude: lng,
                municipality: 'Municipio Arismendi',
                provider: 'test',
              ),
            ),
          ),
          municipalityRepositoryProvider.overrideWithValue(
            _FakeMunicipalityRepository(),
          ),
          sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
          locationMapBuilderProvider.overrideWithValue(
            ({required latitude, required longitude, required onMapTapped}) =>
                const SizedBox(key: Key('fake-location-map')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light, home: const LeakReportScreen()),
        ),
      );
      await tester.pump();

      final controller = container.read(leakReportProvider.notifier);
      await controller.requestGps();
      controller.goTo(ReportStep.data);
      await tester.pump();

      expect(
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Continuar'),
        ).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'T4: cambiar el municipio a mano limpia el sector y deshabilita Continuar',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(_FakeLocationService()),
          reverseGeocodingServiceProvider.overrideWithValue(
            _FakeReverseGeocoder(
              builder: (lat, lng) => LocationSuggestion(
                latitude: lat,
                longitude: lng,
                municipality: 'Maneiro',
                locality: 'La Caranta',
                provider: 'test',
              ),
            ),
          ),
          municipalityRepositoryProvider.overrideWithValue(
            _FakeMunicipalityRepositoryMultiple(),
          ),
          sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
          locationMapBuilderProvider.overrideWithValue(
            ({required latitude, required longitude, required onMapTapped}) =>
                const SizedBox(key: Key('fake-location-map')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light, home: const LeakReportScreen()),
        ),
      );
      await tester.pump();

      final controller = container.read(leakReportProvider.notifier);
      await controller.requestGps();
      controller.goTo(ReportStep.data);
      await tester.pump();

      // Continuar habilitado con preselección.
      expect(
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Continuar'),
        ).onPressed,
        isNotNull,
      );

      // Cambiar el municipio a otro distinto por la UI.
      // El dropdown de municipio vive dentro del ListView del paso de datos: los
      // items fuera de pantalla no se construyen, así que hay que desplazarse
      // hasta él. El botón "Continuar" está fuera de la lista.
      final municipalityDropdown = find.byType(DropdownButtonFormField<String>).first;
      await tester.scrollUntilVisible(
        municipalityDropdown,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(municipalityDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Municipio Arismendi').last);
      await tester.pumpAndSettle();
      expect(
        container.read(leakReportProvider).draft.municipalityId,
        'm2',
        reason: 'la selección manual debe quedar en el borrador',
      );

      // Continuar deshabilitado porque el sector ya no coincide con la sugerencia.
      expect(
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Continuar'),
        ).onPressed,
        isNull,
      );
    },
  );
}

class _ExplodingPhotoService implements PhotoService {
  @override
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera}) async {
    throw StateError('fallo nativo simulado (test de mutación C2)');
  }

  @override
  Future<PreparedPhoto> prepareFromFile(String path) async {
    throw StateError('fallo nativo simulado');
  }
}

class _FakeMunicipalityRepositoryMultiple implements MunicipalityRepository {
  @override
  Future<List<Municipality>> getActive() async => const [
    Municipality(
      id: 'm1',
      name: 'Maneiro',
      state: 'Nueva Esparta',
      country: 'Venezuela',
      isActive: true,
    ),
    Municipality(
      id: 'm2',
      name: 'Municipio Arismendi',
      state: 'Nueva Esparta',
      country: 'Venezuela',
      isActive: true,
    ),
  ];
}
