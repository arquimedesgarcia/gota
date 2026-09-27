import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/core/network/gota_water_database.dart';
import 'package:gota/features/leaks/data/geolocator_location_service.dart';
import 'package:gota/features/leaks/data/location_service.dart';
import 'package:gota/features/leaks/data/reverse_geocoding_service.dart';
import 'package:gota/features/leaks/domain/location_suggestion.dart';
import 'package:gota/features/location/data/municipality_repository.dart';
import 'package:gota/features/location/data/sector_repository.dart';
import 'package:gota/features/water/data/water_event_repository.dart';
import 'package:gota/features/water/domain/water_event.dart';
import 'package:gota/features/water/domain/water_event_detail.dart';
import 'package:gota/features/water/domain/water_event_type.dart';
import 'package:gota/features/water/presentation/water_register_controller.dart';
import 'package:gota/shared/models/municipality.dart';
import 'package:gota/shared/models/sector.dart';

class _FakeLocationService implements LocationService {
  @override
  Future<({double latitude, double longitude, double? accuracyMeters})>
  getCurrentPosition() async =>
      (latitude: 10.9578, longitude: -63.8489, accuracyMeters: 12.0);
}

class _FakeGeocoder implements ReverseGeocodingService {
  @override
  Future<LocationSuggestion?> reverse({
    required double latitude,
    required double longitude,
  }) async => LocationSuggestion(
    latitude: latitude,
    longitude: longitude,
    provider: 'test',
    displayText: 'Calle Bolívar, Los Pinos, Porlamar',
    locality: 'Los Pinos',
    city: 'Porlamar',
    municipality: 'Mariño',
    state: 'Nueva Esparta',
    incomplete: false,
  );
}

class _FakeMunicipalityRepository implements MunicipalityRepository {
  @override
  Future<List<Municipality>> getActive() async => const [
    Municipality(
      id: 'm1',
      name: 'Mariño',
      state: 'Nueva Esparta',
      country: 'VE',
      isActive: true,
    ),
    Municipality(
      id: 'm2',
      name: 'Maneiro',
      state: 'Nueva Esparta',
      country: 'VE',
      isActive: true,
    ),
  ];
}

class _FakeSectorRepository implements SectorRepository {
  @override
  Future<List<Sector>> getByMunicipality(String municipalityId) async {
    if (municipalityId != 'm1') return const [];
    return const [
      Sector(
        id: 's1',
        municipalityId: 'm1',
        name: 'Los Pinos',
        isActive: true,
      ),
      Sector(
        id: 's2',
        municipalityId: 'm1',
        name: 'Centro',
        isActive: true,
      ),
    ];
  }

  @override
  Future<Sector?> getById(String id) async => null;
}

class _SpyWaterRepository implements WaterEventRepository {
  ({String? address, String municipalityId, String sectorId})? lastRegister;

  @override
  Future<(WaterEventSummary, bool isConfirmation)> register({
    required String municipalityId,
    required String sectorId,
    required WaterEventType type,
    required DateTime eventTime,
    String? comment,
    String? address,
  }) async {
    lastRegister = (
      address: address,
      municipalityId: municipalityId,
      sectorId: sectorId,
    );
    return (
      WaterEventSummary(
        id: 'e1',
        type: type,
        eventTime: eventTime,
        validationCount: 0,
        createdAt: DateTime(2026, 9, 26, 12),
      ),
      false,
    );
  }

  @override
  Future<int> validate(String eventId) => throw UnimplementedError();
  @override
  Future<WaterEventDetail> detail(String eventId) => throw UnimplementedError();
  @override
  Future<WaterEventSummary?> latestEvent({String? sectorId}) async => null;
  @override
  Future<WaterEventsPage> recentEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  }) async => const WaterEventsPage(events: []);
}

void main() {
  late _SpyWaterRepository spyRepo;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        reverseGeocodingServiceProvider.overrideWithValue(_FakeGeocoder()),
        municipalityRepositoryProvider
            .overrideWithValue(_FakeMunicipalityRepository()),
        sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
        waterEventRepositoryProvider.overrideWithValue(spyRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => spyRepo = _SpyWaterRepository());

  test('GPS autocompleta municipio, sector y dirección desde el geocoder',
      () async {
    final container = makeContainer();
    final notifier = container.read(waterRegisterControllerProvider.notifier);

    await notifier.requestGps();

    final state = container.read(waterRegisterControllerProvider);
    expect(state.hasLocation, isTrue);
    expect(state.isGpsLocation, isTrue);
    expect(state.municipalityId, 'm1');
    expect(state.municipalityName, 'Mariño');
    expect(state.sectorId, 's1');
    expect(state.sectorName, 'Los Pinos');
    expect(state.address, 'Calle Bolívar, Los Pinos, Porlamar');
  });

  test('submit envía la dirección capturada al repositorio', () async {
    final container = makeContainer();
    final notifier = container.read(waterRegisterControllerProvider.notifier);

    await notifier.requestGps();
    final outcome = await notifier.submit(WaterEventType.arrived);

    expect(outcome, WaterSubmitOutcome.created);
    expect(spyRepo.lastRegister?.municipalityId, 'm1');
    expect(spyRepo.lastRegister?.sectorId, 's1');
    expect(spyRepo.lastRegister?.address, 'Calle Bolívar, Los Pinos, Porlamar');

    // submit() dispara waterHistory.refresh() (fire-and-forget), que construye
    // el WaterHistoryController de forma diferida: dejamos que ese trabajo
    // pendiente se resuelva antes de que el contenedor se disponga en tearDown.
    await Future<void>.delayed(Duration.zero);
  });

  test('cambiar de municipio reinicia el sector', () async {
    final container = makeContainer();
    final notifier = container.read(waterRegisterControllerProvider.notifier);

    await notifier.requestGps();
    expect(container.read(waterRegisterControllerProvider).sectorId, 's1');

    notifier.selectMunicipality(
      const Municipality(
        id: 'm2',
        name: 'Maneiro',
        state: 'Nueva Esparta',
        country: 'VE',
        isActive: true,
      ),
    );

    final state = container.read(waterRegisterControllerProvider);
    expect(state.municipalityId, 'm2');
    expect(state.sectorId, isNull);
    expect(state.sectorName, isNull);
  });

  test('el Stepper va de 0 a 2 y no se sale de rango', () {
    final container = makeContainer();
    final notifier = container.read(waterRegisterControllerProvider.notifier);

    expect(container.read(waterRegisterControllerProvider).currentStep, 0);
    notifier.previousStep();
    expect(container.read(waterRegisterControllerProvider).currentStep, 0);

    notifier.nextStep();
    notifier.nextStep();
    expect(container.read(waterRegisterControllerProvider).currentStep, 2);
    notifier.nextStep();
    expect(container.read(waterRegisterControllerProvider).currentStep, 2);
  });

  test('submit sin sector devuelve error de validación local', () async {
    final container = makeContainer();
    final notifier = container.read(waterRegisterControllerProvider.notifier);

    final outcome = await notifier.submit(WaterEventType.arrived);

    expect(outcome, isNull);
    final state = container.read(waterRegisterControllerProvider);
    expect(state.submitStatus, WaterRegisterSubmitStatus.error);
    expect(state.errorMessage, isNotNull);
    expect(spyRepo.lastRegister, isNull);
  });
}
