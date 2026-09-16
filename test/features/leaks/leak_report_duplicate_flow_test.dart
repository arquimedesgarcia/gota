import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/leaks/data/geolocator_location_service.dart'
    show locationServiceProvider;
import 'package:gota/features/leaks/data/leak_report_repository.dart';
import 'package:gota/features/leaks/data/location_service.dart';
import 'package:gota/features/leaks/domain/create_leak_report_outcome.dart';
import 'package:gota/features/leaks/domain/leak_report_draft.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/leaks/presentation/leak_community_providers.dart';
import 'package:gota/features/leaks/presentation/leak_detail_screen.dart';
import 'package:gota/features/leaks/presentation/leak_report_controller.dart';
import 'package:gota/features/leaks/presentation/leak_report_microcopy.dart';
import 'package:gota/features/leaks/presentation/leak_report_screen.dart';
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

/// Repositorio falso que registra el `ignoreDuplicate` de CADA envío.
class _RecordingRepository implements LeakReportRepository {
  _RecordingRepository(this.outcomes);

  final List<CreateLeakReportOutcome> outcomes;
  final List<bool> ignoreHistory = [];
  int callCount = 0;

  @override
  Future<CreateLeakReportOutcome> createReport(
    LeakReportDraft draft, {
    bool ignoreDuplicate = false,
  }) async {
    callCount++;
    ignoreHistory.add(ignoreDuplicate);
    final index = outcomes.length >= callCount ? callCount - 1 : 0;
    return outcomes[index];
  }
}

/// Archivo físico mínimo para el Image.file de la grilla.
File _fakePhotoFileSync(String name) {
  final file = File('${Directory.systemTemp.path}/gota_audit_s2_$name.jpg');
  file.writeAsBytesSync(List.filled(48, 0x7f));
  return file;
}

void main() {
  // Preparación común: pantalla montada y borrador completo por hooks de
  // prueba (sin image_picker), igual que hace el flujo real en cada etapa.
  Future<({LeakReportController controller, _RecordingRepository repo})>
  prepare(
    WidgetTester tester, {
    required List<CreateLeakReportOutcome> outcomes,
  }) async {
    final repo = _RecordingRepository(outcomes);
    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        municipalityRepositoryProvider.overrideWithValue(
          _FakeMunicipalityRepository(),
        ),
        sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
        leakReportRepositoryProvider.overrideWithValue(repo),
        leakDetailProvider.overrideWith(
          (ref, id) => Future.value(
            LeakDetail(
              id: 'x',
              status: 'ACTIVE',
              validationCount: 0,
              resolutionConfirmationCount: 0,
              threshold: 3,
              createdAt: DateTime(2026),
              latitude: 10.99,
              longitude: -63.87,
              isCreator: false,
              isBlocked: false,
              alreadyValidated: false,
              alreadyConfirmed: false,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LeakReportScreen(),
        ),
      ),
    );
    await tester.pump();

    final controller = container.read(leakReportProvider.notifier);
    final photoFile = _fakePhotoFileSync('p');
    controller.completeDraftForTest(
      photo: PreparedPhoto(
        id: 'p1',
        originalPath: photoFile.path,
        compressedPath: photoFile.path,
        mimeType: 'image/jpeg',
        sizeBytes: 48,
        width: 0,
        height: 0,
      ),
      municipalityId: 'm1',
      sectorId: 's1',
    );
    controller.goTo(ReportStep.review);
    await tester.pump();
    return (controller: controller, repo: repo);
  }

  testWidgets('AUD-S2-04: "Es otra fuga" reenvía una sola vez con '
      'p_ignore_duplicate=true', (tester) async {
    final (:controller, :repo) = await prepare(
      tester,
      outcomes: [
        PossibleDuplicateFound(
          candidates: [
            PossibleDuplicateCandidate(
              id: 'r-existente',
              sectorId: 's1',
              distanceMeters: 22,
              createdAt: DateTime(2026),
            ),
          ],
        ),
        const ReportCreated(reportId: 'r-nuevo'),
      ],
    );

    // Primer envío → duplicado (sin confirmación: false).
    await tester.tap(find.text('Enviar reporte'));
    await tester.pump();
    expect(repo.ignoreHistory, [false]);
    expect(
      find.textContaining('Ya existe un reporte de fuga cerca'),
      findsWidgets,
    );

    // "Es otra fuga" → segundo envío CON la confirmación explícita.
    await tester.tap(find.text('Es otra fuga'));
    await tester.pump();
    expect(repo.ignoreHistory, [false, true]);
    expect(find.text('Reporte enviado'), findsOneWidget);
  });

  testWidgets('AUD-S2-04/REQ-025 (control): el backend es el que decide; el '
      'segundo envío sin abrir el flujo no reusa confirmaciones', (
    tester,
  ) async {
    // Mismo escenario, pero el usuario da "Editar datos" y vuelve: al
    // reenviar desde "Enviar reporte" (no desde "Es otra fuga") la
    // señal NO puede ser true pegajosa.
    final (:controller, :repo) = await prepare(
      tester,
      outcomes: [
        PossibleDuplicateFound(
          candidates: [
            PossibleDuplicateCandidate(
              id: 'r-existente',
              sectorId: 's1',
              distanceMeters: 22,
              createdAt: DateTime(2026),
            ),
          ],
        ),
        PossibleDuplicateFound(
          candidates: [
            PossibleDuplicateCandidate(
              id: 'r-existente',
              sectorId: 's1',
              distanceMeters: 22,
              createdAt: DateTime(2026),
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.text('Enviar reporte'));
    await tester.pump();
    expect(repo.ignoreHistory, [false]);
    expect(
      find.textContaining('Ya existe un reporte de fuga cerca'),
      findsWidgets,
    );

    // El usuario acepta usar el existente (NO ES UNA CONFIRMACIÓN de
    // "otra fuga"): el estado pasa a result y NADA se crea.
    await tester.tap(find.text(LeakReportCopy.duplicateUseExisting));
    await tester.pump();

    // La confirmación NO sobrevive al reenvío (AUD-S2-04 corregido):
    // `submit` sin argumento nunca envía p_ignore_duplicate=true, ni
    // aunque el usuario hubiera pulsado "Es otra fuga" antes.
    await controller.submit();
    await tester.pump();

    expect(repo.ignoreHistory, [false, false]);
  });

  testWidgets('AUD-S2-06: "usar el reporte existente" NUNCA muestra "Reporte '
      'enviado"', (tester) async {
    final (:controller, :repo) = await prepare(
      tester,
      outcomes: [
        PossibleDuplicateFound(
          candidates: [
            PossibleDuplicateCandidate(
              id: 'r-existente',
              sectorId: 's1',
              distanceMeters: 8,
              createdAt: DateTime(2026),
            ),
          ],
        ),
      ],
    );
    expect(find.text('Revisa tu reporte'), findsOneWidget);
    await tester.tap(find.text('Enviar reporte'));
    await tester.pump();
    await tester.tap(find.text(LeakReportCopy.duplicateUseExisting));
    await tester.pump();

    expect(repo.callCount, 1);
    expect(find.text('Reporte enviado'), findsNothing);
    expect(find.text('No se creó un reporte nuevo'), findsOneWidget);
    expect(find.textContaining('Usaste el reporte existente'), findsOneWidget);
  });

  testWidgets(
    'AUD-S2-05: el estado duplicate ofrece "Ver y validar" que abre el '
    'detalle del candidato',
    (tester) async {
      final (:controller, :repo) = await prepare(
        tester,
        outcomes: [
          PossibleDuplicateFound(
            candidates: [
              PossibleDuplicateCandidate(
                id: 'r-candidato',
                sectorId: 's1',
                distanceMeters: 12,
                createdAt: DateTime(2026),
              ),
            ],
          ),
        ],
      );

      await tester.tap(find.text('Enviar reporte'));
      await tester.pump();

      expect(
        find.text(LeakReportCopy.duplicateViewAndValidate),
        findsOneWidget,
      );
      await tester.tap(find.text(LeakReportCopy.duplicateViewAndValidate));
      await tester.pumpAndSettle();

      // LeakDetailScreen se empuja ENCIMA del flujo (el flujo queda debajo
      // en la pila de navegación). La aserción real: se abrió el detalle
      // del candidato y NO se creó ningún reporte nuevo.
      expect(find.byType(LeakDetailScreen), findsOneWidget);
      expect(repo.callCount, 1);
    },
  );
}
