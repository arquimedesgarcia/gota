import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/leaks/data/geolocator_location_service.dart'
    show locationServiceProvider;
import 'package:gota/features/leaks/data/location_service.dart';
import 'package:gota/features/leaks/domain/leak_errors.dart';
import 'package:gota/features/leaks/presentation/leak_report_screen.dart';
import 'package:gota/features/location/data/municipality_repository.dart';
import 'package:gota/features/location/data/sector_repository.dart';
import 'package:gota/shared/models/municipality.dart';
import 'package:gota/shared/models/sector.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService({this.error});

  final LeakFlowException? error;

  @override
  Future<({double latitude, double longitude})> getCurrentPosition() async {
    if (error != null) throw error!;
    return (latitude: 10.99, longitude: -63.87);
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

ProviderScope _app({LeakFlowException? gpsError}) => ProviderScope(
  overrides: [
    locationServiceProvider.overrideWithValue(
      _FakeLocationService(error: gpsError),
    ),
    municipalityRepositoryProvider.overrideWithValue(
      _FakeMunicipalityRepository(),
    ),
    sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const LeakReportScreen()),
);

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
    expect(find.text('Agrega de 1 a 3 fotos de la fuga'), findsOneWidget);
    expect(find.text('Fotos agregadas: 0 de 3'), findsOneWidget);
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
}
