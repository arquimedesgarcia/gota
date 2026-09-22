import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/create_leak_report_outcome.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/leaks/presentation/leak_community_providers.dart';
import 'package:gota/features/leaks/presentation/leak_report_controller.dart';
import 'package:gota/features/leaks/presentation/leak_report_screen.dart';
import 'package:gota/features/leaks/presentation/recent_leaks_list.dart';

LeakSummary _summary(String id) => LeakSummary(
  id: id,
  status: 'ACTIVE',
  validationCount: 1,
  resolutionConfirmationCount: 0,
  createdAt: DateTime(2026, 9, 15, 8, 0),
  sectorName: 'La Caranta',
  municipalityName: 'Maneiro',
);

class _FakeLeakCommunityRepository implements LeakCommunityRepository {
  _FakeLeakCommunityRepository(this.list);

  List<LeakSummary> list;

  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async =>
      list.take(limit).toList();

  @override
  Future<LeakDetail> reportDetail(String reportId) =>
      throw UnimplementedError();

  @override
  Future<CommunityActionResult> validateLeak(String reportId) =>
      throw UnimplementedError();

  @override
  Future<CommunityActionResult> confirmResolution(String reportId) =>
      throw UnimplementedError();

  @override
  Future<List<LeakSummary>> mapReports({
    String? status,
    String? sectorId,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    String orderBy = 'recent',
    int limit = 100,
  }) async => throw UnimplementedError();
}

/// Stub del controller del flujo para fijar el estado de resultado.
class _StubLeakReport extends LeakReportController {
  _StubLeakReport(this._fixed);

  final LeakReportState _fixed;

  @override
  LeakReportState build() => _fixed;
}

/// Host que abre `ResultStepView` como ruta y captura el retorno,
/// replicando el cableado S10-B.
class _ResultHost extends StatefulWidget {
  const _ResultHost();

  @override
  State<_ResultHost> createState() => _ResultHostState();
}

class _ResultHostState extends State<_ResultHost> {
  bool? returned;

  Future<void> _open() async {
    final value = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ResultStepView()),
    );
    if (!mounted) return;
    setState(() => returned = value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(onPressed: _open, child: const Text('abrir resultado')),
        Text('retorno: $returned'),
      ],
    );
  }
}

Future<void> _pumpResultHost(
  WidgetTester tester,
  LeakReportState state,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [leakReportProvider.overrideWith(() => _StubLeakReport(state))],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: _ResultHost()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('abrir resultado'));
  await tester.pumpAndSettle();
  expect(find.byType(ResultStepView), findsOneWidget);
  await tester.tap(find.text('Volver al inicio'));
  await tester.pumpAndSettle();
}

void main() {
  group('S10-B refresh Home tras crear fuga', () {
    testWidgets('TEST 1: nuevo leak visible tras invalidate', (tester) async {
      // Viewport alto: la lista es perezosa y necesita espacio.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repo = _FakeLeakCommunityRepository([_summary('r1')]);
      late ProviderContainer container;

      // El listado de fugas ya no vive en Home: se verifica el contrato
      // S10-B sobre el widget que lo mostrará en su página definitiva.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leakCommunityRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(body: RecentLeaksList());
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(leakTileKey('r1')), findsOneWidget);
      expect(find.byKey(leakTileKey('r2')), findsNothing);

      // Simula la llegada del nuevo reporte al backend.
      repo.list = [_summary('r1'), _summary('r2')];
      // Esto es exactamente lo que hacen HomeScreen._openReport y
      // AppShell._openReportFlow cuando el flujo devuelve true.
      container.invalidate(recentLeaksProvider);
      await tester.pumpAndSettle();

      expect(find.byKey(leakTileKey('r1')), findsOneWidget);
      expect(find.byKey(leakTileKey('r2')), findsOneWidget);
    });

    testWidgets('resultado creado devuelve true', (tester) async {
      await _pumpResultHost(
        tester,
        const LeakReportState(
          currentStep: ReportStep.result,
          submitState: ReportSubmitState.done,
          outcome: ReportCreated(reportId: 'abc'),
        ),
      );
      expect(find.text('retorno: true'), findsOneWidget);
    });

    testWidgets('duplicado aceptado devuelve false', (tester) async {
      await _pumpResultHost(
        tester,
        const LeakReportState(
          currentStep: ReportStep.result,
          submitState: ReportSubmitState.duplicate,
        ),
      );
      expect(find.text('retorno: false'), findsOneWidget);
    });
  });
}
