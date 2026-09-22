import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/community_activity.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/leaks/presentation/leak_detail_screen.dart';
import 'package:gota/features/leaks/presentation/leak_summary_tile.dart';
import 'package:gota/features/leaks/presentation/recent_activity_card.dart';
import 'package:gota/features/leaks/presentation/recent_activity_providers.dart';

CommunityActivity _activity({
  CommunityActivityType type = CommunityActivityType.reported,
  String status = 'ACTIVE',
  String reportId = 'r1',
}) => CommunityActivity(
  type: type,
  at: DateTime.now().subtract(const Duration(hours: 2)),
  reportId: reportId,
  status: status,
  validationCount: 3,
  resolutionConfirmationCount: 0,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  sectorName: 'La Caranta',
  municipalityName: 'Maneiro',
);

class _FakeRepo implements LeakCommunityRepository {
  _FakeRepo({this.activity, this.activityError});

  final CommunityActivity? activity;
  final Object? activityError;

  @override
  Future<CommunityActivity?> latestActivity() async {
    if (activityError != null) throw activityError!;
    return activity;
  }

  @override
  Future<LeakDetail> reportDetail(String reportId) async => LeakDetail(
    id: reportId,
    status: 'ACTIVE',
    validationCount: 3,
    resolutionConfirmationCount: 0,
    threshold: 3,
    createdAt: DateTime.now(),
    latitude: 10.99,
    longitude: -63.87,
    isCreator: false,
    isBlocked: false,
    alreadyValidated: false,
    alreadyConfirmed: false,
    sectorName: 'La Caranta',
    municipalityName: 'Maneiro',
  );

  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async => const [];

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
  }) async => const [];
}

Future<void> _pumpRepo(WidgetTester tester, _FakeRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [leakCommunityRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: RecentActivityCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('con dato: encabezado, lugar, antigüedad y navegación', (
    tester,
  ) async {
    await _pumpRepo(tester, _FakeRepo(activity: _activity(reportId: 'r7')));

    expect(find.text('Actividad reciente'), findsOneWidget);
    expect(find.text('La Caranta · Maneiro'), findsOneWidget);
    expect(find.textContaining('3 validaciones'), findsOneWidget);
    expect(find.textContaining('hace 2 h'), findsOneWidget);

    await tester.tap(find.byKey(leakTileKey('r7')));
    await tester.pumpAndSettle();

    expect(find.byType(LeakDetailScreen), findsOneWidget);
  });

  testWidgets('un evento REPORTED de falla ACTIVE se pinta como activa', (
    tester,
  ) async {
    await _pumpRepo(tester, _FakeRepo(activity: _activity()));

    // Estado real (ACTIVE), no el tipo de evento.
    expect(find.text('Activa'), findsOneWidget);
    expect(find.text('Resuelta'), findsNothing);
  });

  testWidgets('sin dato: respaldo "Sin actividad reciente" sin reintento', (
    tester,
  ) async {
    await _pumpRepo(tester, _FakeRepo());

    expect(find.text('Sin actividad reciente'), findsOneWidget);
    expect(find.byKey(recentActivityRetryKey), findsNothing);
  });

  testWidgets('provider tolerante: un fallo del repositorio degrada a vacío', (
    tester,
  ) async {
    // El provider real traga el error y devuelve null (no error): la tarjeta
    // muestra el respaldo sin tumbar el Home.
    await _pumpRepo(tester, _FakeRepo(activityError: Exception('boom')));

    expect(find.text('Sin actividad reciente'), findsOneWidget);
  });

  testWidgets('estado de error: respaldo + reintento funcional', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          latestActivityProvider.overrideWith((ref) async {
            if (fail) throw Exception('boom');
            return _activity();
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: RecentActivityCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin actividad reciente'), findsOneWidget);
    expect(find.byKey(recentActivityRetryKey), findsOneWidget);

    fail = false;
    await tester.tap(find.byKey(recentActivityRetryKey));
    await tester.pumpAndSettle();

    expect(find.text('Actividad reciente'), findsOneWidget);
    expect(find.text('La Caranta · Maneiro'), findsOneWidget);
  });
}
