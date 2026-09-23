// Mutation control para R4 (T4-1 a T4-8): borrador persistente (commit abc71ac).
// Reglas: stores en memoria siempre; sin reimplementar lógica de producción;
// cada test nombra la mutación que lo haría fallar.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/features/leaks/data/geolocator_location_service.dart'
    show locationServiceProvider;
import 'package:gota/features/leaks/data/draft_photo_store.dart';
import 'package:gota/features/leaks/data/draft_store.dart';
import 'package:gota/features/leaks/data/leak_report_repository.dart';
import 'package:gota/features/leaks/data/location_service.dart';
import 'package:gota/features/leaks/data/photo_service.dart';
import 'package:gota/features/leaks/data/reverse_geocoding_service.dart';
import 'package:gota/features/leaks/domain/create_leak_report_outcome.dart';
import 'package:gota/features/leaks/domain/leak_report_draft.dart';
import 'package:gota/features/leaks/domain/location_suggestion.dart';
import 'package:gota/features/leaks/presentation/leak_report_controller.dart';
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

/// T4-3: store que lanza al leer (simula JSON corrupto).
class _ThrowingDraftStore implements DraftStore {
  @override
  Future<LeakDraftSnapshot?> read() async =>
      throw const FormatException('JSON corrupto');

  @override
  Future<void> write(LeakDraftSnapshot s) async {}

  @override
  Future<void> clear() async {}
}

/// T4-4: captura si el borrador ya estaba persistido cuando el picker abre.
class _CapturingPhotoService implements PhotoService {
  _CapturingPhotoService(this.store);

  bool savedBeforePick = false;
  final DraftStore store;

  @override
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera}) async {
    final snapshot = await store.read();
    savedBeforePick = snapshot != null;
    return const PreparedPhoto(
      id: '1',
      originalPath: '/a',
      compressedPath: '/a_gota.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 100,
      width: 0,
      height: 0,
    );
  }

  @override
  Future<PreparedPhoto> prepareFromFile(String path) async =>
      throw UnimplementedError();

  @override
  Future<List<String>> retrieveLostData() async => const [];
}

/// T4-8: servicio que reporta lost data de una sesión matada.
class _LostDataPhotoService implements PhotoService {
  _LostDataPhotoService(this.lostPaths);

  final List<String> lostPaths;

  @override
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera}) async =>
      throw UnimplementedError();

  @override
  Future<PreparedPhoto> prepareFromFile(String path) async => PreparedPhoto(
    id: path.hashCode.toString(),
    originalPath: path,
    compressedPath: '${path}_gota.jpg',
    mimeType: 'image/jpeg',
    sizeBytes: 100,
    width: 0,
    height: 0,
  );

  @override
  Future<List<String>> retrieveLostData() async => lostPaths;
}

/// T4-5a/T4-8: repositorio falso que devuelve ReportCreated.
class _FakeLeakReportRepository implements LeakReportRepository {
  @override
  Future<CreateLeakReportOutcome> createReport(
    LeakReportDraft draft, {
    bool ignoreDuplicate = false,
  }) async => const ReportCreated(reportId: 'r-test');
}

ProviderContainer _container({
  DraftStore? draftStore,
  DraftPhotoStore? draftPhotoStore,
  PhotoService? photoService,
  LeakReportRepository? repository,
}) {
  final c = ProviderContainer(
    overrides: [
      locationServiceProvider.overrideWithValue(_FakeLocationService()),
      reverseGeocodingServiceProvider.overrideWithValue(_FakeReverseGeocoder()),
      municipalityRepositoryProvider.overrideWithValue(
        _FakeMunicipalityRepository(),
      ),
      sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
      draftStoreProvider.overrideWithValue(
        draftStore ?? InMemoryDraftStore(),
      ),
      draftPhotoStoreProvider.overrideWithValue(
        draftPhotoStore ?? InMemoryDraftPhotoStore(),
      ),
      if (photoService != null)
        photoServiceProvider.overrideWithValue(photoService),
      if (repository != null)
        leakReportRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Deja correr cadenas de microtasks (store.read → exists → state updates).
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future.delayed(Duration.zero);
  }
}

void main() {
  test('T4-1: mutar el borrador llama a write() con los campos correctos',
      () async {
    final store = InMemoryDraftStore();
    final container = _container(draftStore: store);
    await _settle();

    final controller = container.read(leakReportProvider.notifier);
    controller.selectMunicipality('m1');
    controller.selectSector('s1');
    controller.setDescription('fuga grave');
    // _saveDraft es fire-and-forget; darle una vuelta para que complete.
    await _settle();

    final snapshot = await store.read();
    expect(snapshot, isNotNull);
    expect(snapshot!.municipalityId, 'm1');
    expect(snapshot.sectorId, 's1');
    expect(snapshot.description, 'fuga grave');
  });

  test('T4-2: build() con snapshot válido restaura borrador y paso', () async {
    final store = InMemoryDraftStore();
    final photoStore = InMemoryDraftPhotoStore();

    // Pre-popular el store con un snapshot válido. La foto necesita existir
    // en photoStore para no ser descartada.
    const photoId = 'p1';
    final durablePath = await photoStore.copyToDurable(
      compressedPath: '/cache/photo.jpg',
      photoId: photoId,
    );
    await store.write(
      LeakDraftSnapshot(
        schemaVersion: LeakDraftSnapshot.currentSchemaVersion,
        savedAt: DateTime.now(),
        stepIndex: ReportStep.photos.index,
        latitude: 10.99,
        longitude: -63.87,
        locationSource: 'gps',
        municipalityId: 'm1',
        sectorId: 's1',
        description: 'test',
        photos: [
          PhotoSnapshot(
            id: photoId,
            compressedPath: durablePath,
            mimeType: 'image/jpeg',
            sizeBytes: 500,
            width: 0,
            height: 0,
            originalPath: '/orig',
          ),
        ],
      ),
    );

    final container = _container(draftStore: store, draftPhotoStore: photoStore);
    container.read(leakReportProvider); // dispara build()
    await _settle();

    final state = container.read(leakReportProvider);
    expect(state.hasDraftRestored, isTrue);
    expect(state.currentStep, ReportStep.photos);
    expect(state.draft.municipalityId, 'm1');
    expect(state.draft.sectorId, 's1');
    expect(state.draft.description, 'test');
    expect(state.draft.location?.latitude, closeTo(10.99, 0.001));
    expect(state.draft.photos, hasLength(1));
  });

  test('T4-3: snapshot corrupto → estado vacío y ninguna excepción', () async {
    final container = _container(draftStore: _ThrowingDraftStore());
    // No debe lanzar durante build():
    expect(() => container.read(leakReportProvider), returnsNormally);
    await _settle();

    final state = container.read(leakReportProvider);
    expect(state.hasDraftRestored, isFalse);
    expect(state.draft.photos, isEmpty);
    expect(state.draft.location, isNull);
  });

  test('T4-4: addPhoto guarda el borrador ANTES de abrir el picker', () async {
    final store = InMemoryDraftStore();
    final service = _CapturingPhotoService(store);
    final container = _container(draftStore: store, photoService: service);
    await _settle();

    // Poner algo en el borrador primero para que el snapshot tenga contenido.
    container
        .read(leakReportProvider.notifier)
        .setManualLocation(latitude: 10.0, longitude: -63.0);
    await _settle(); // deja que _saveDraft fire-and-forget complete

    await container.read(leakReportProvider.notifier).addPhoto(fromCamera: false);

    expect(
      service.savedBeforePick,
      isTrue,
      reason: 'el borrador debe estar persistido antes de que el picker abra',
    );
  });

  test('T4-5a: submit exitoso limpia el store', () async {
    final store = InMemoryDraftStore();
    await store.write(
      LeakDraftSnapshot(
        schemaVersion: LeakDraftSnapshot.currentSchemaVersion,
        savedAt: DateTime.now(),
        stepIndex: 0,
      ),
    );

    final container = _container(
      draftStore: store,
      repository: _FakeLeakReportRepository(),
    );
    await _settle();

    final controller = container.read(leakReportProvider.notifier);
    controller.completeDraftForTest(
      photo: const PreparedPhoto(
        id: '1',
        originalPath: '/a',
        compressedPath: '/a_gota.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 100,
        width: 0,
        height: 0,
      ),
      municipalityId: 'm1',
      sectorId: 's1',
    );
    await controller.submit();
    await _settle();

    expect(
      await store.read(),
      isNull,
      reason: 'submit exitoso debe limpiar el borrador',
    );
  });

  test('T4-5b: useExistingReport limpia el store', () async {
    final store = InMemoryDraftStore();
    await store.write(
      LeakDraftSnapshot(
        schemaVersion: LeakDraftSnapshot.currentSchemaVersion,
        savedAt: DateTime.now(),
        stepIndex: 0,
      ),
    );
    final container = _container(draftStore: store);
    await _settle();

    container.read(leakReportProvider.notifier).useExistingReport();
    await _settle();

    expect(await store.read(), isNull);
  });

  test('T4-6: snapshot con TTL vencido no restaura el borrador y purga el store',
      () async {
    final store = InMemoryDraftStore();
    // Snapshot de hace 25 horas (> TTL de 24h).
    await store.write(
      LeakDraftSnapshot(
        schemaVersion: LeakDraftSnapshot.currentSchemaVersion,
        savedAt: DateTime.now().subtract(const Duration(hours: 25)),
        stepIndex: ReportStep.photos.index,
        municipalityId: 'm1',
      ),
    );

    final container = _container(draftStore: store);
    container.read(leakReportProvider);
    await _settle();

    final state = container.read(leakReportProvider);
    expect(state.hasDraftRestored, isFalse);
    expect(state.draft.municipalityId, isNull);
    // El store debe haber sido purgado.
    expect(await store.read(), isNull);
  });

  test('T4-7: foto restaurada cuyo archivo no existe se descarta silenciosamente',
      () async {
    final store = InMemoryDraftStore();
    // InMemoryDraftPhotoStore vacío → exists() devuelve false para cualquier ruta.
    final photoStore = InMemoryDraftPhotoStore();

    await store.write(
      LeakDraftSnapshot(
        schemaVersion: LeakDraftSnapshot.currentSchemaVersion,
        savedAt: DateTime.now(),
        stepIndex: 0,
        photos: const [
          PhotoSnapshot(
            id: 'p1',
            compressedPath: '/memory/draft_photos/p1.jpg', // no está en photoStore
            mimeType: 'image/jpeg',
            sizeBytes: 100,
            width: 0,
            height: 0,
            originalPath: '/orig',
          ),
        ],
      ),
    );

    final container = _container(draftStore: store, draftPhotoStore: photoStore);
    container.read(leakReportProvider);
    await _settle();

    final state = container.read(leakReportProvider);
    expect(
      state.draft.photos,
      isEmpty,
      reason: 'la foto cuyo archivo ya no existe debe ser descartada',
    );
  });

  test('T4-8: lost data se añade al borrador respetando el tope de 2 fotos',
      () async {
    // Caso A: 1 lost data → se añade.
    final container = _container(
      photoService: _LostDataPhotoService(['/lost/photo1.jpg']),
    );
    container.read(leakReportProvider);
    await _settle();

    expect(container.read(leakReportProvider).draft.photos, hasLength(1));
    container.dispose();

    // Caso B: 3 lost data pero tope es 2 → solo se añaden 2.
    final container2 = _container(
      photoService: _LostDataPhotoService([
        '/lost/photo1.jpg',
        '/lost/photo2.jpg',
        '/lost/photo3.jpg',
      ]),
    );
    container2.read(leakReportProvider);
    await _settle();

    expect(container2.read(leakReportProvider).draft.photos, hasLength(2));
  });
}
