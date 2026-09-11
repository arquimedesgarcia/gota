import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/leaks/presentation/leak_detail_screen.dart';
import 'package:gota/features/leaks/presentation/recent_leaks_list.dart';

LeakSummary _summary({
  required String id,
  String status = 'ACTIVE',
  int validations = 1,
  int confirmations = 0,
  String? sector = 'La Caranta',
  String? municipality = 'Maneiro',
}) =>
    LeakSummary(
      id: id,
      status: status,
      validationCount: validations,
      resolutionConfirmationCount: confirmations,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      sectorName: sector,
      municipalityName: municipality,
    );

class _FakeLeakCommunityRepository implements LeakCommunityRepository {
  _FakeLeakCommunityRepository({this.list = const [], this.listError});

  List<LeakSummary> list;
  Object? listError;

  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async {
    if (listError != null) throw listError!;
    return list;
  }

  @override
  Future<LeakDetail> reportDetail(String reportId) async => LeakDetail(
        id: reportId,
        status: 'ACTIVE',
        validationCount: 1,
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
  Future<CommunityActionResult> validateLeak(String reportId) async =>
      throw UnimplementedError();

  @override
  Future<CommunityActionResult> confirmResolution(String reportId) async =>
      throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester,
  _FakeLeakCommunityRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        leakCommunityRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: RecentLeaksList()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin fugas muestra estado vacío honesto', (tester) async {
    await _pump(tester, _FakeLeakCommunityRepository());

    expect(find.text('Sin datos todavía'), findsOneWidget);
  });

  testWidgets('lista las fugas con su estado y contador', (tester) async {
    await _pump(
      tester,
      _FakeLeakCommunityRepository(list: [
        _summary(id: 'r1', validations: 3),
        _summary(
          id: 'r2',
          status: 'RESOLVED',
          confirmations: 3,
          sector: 'Playa El Ángel',
        ),
      ]),
    );

    expect(find.text('La Caranta · Maneiro'), findsOneWidget);
    expect(find.text('Playa El Ángel · Maneiro'), findsOneWidget);
    expect(find.textContaining('3 validaciones'), findsOneWidget);
    expect(find.text('Resuelta'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
  });

  testWidgets('abre el detalle al tocar una fuga', (tester) async {
    await _pump(
      tester,
      _FakeLeakCommunityRepository(list: [_summary(id: 'r7')]),
    );

    await tester.tap(find.byKey(leakTileKey('r7')));
    await tester.pumpAndSettle();

    expect(find.byType(LeakDetailScreen), findsOneWidget);
    expect(find.text('Fuga activa'), findsOneWidget);
  });

  testWidgets('error de carga: mensaje y reintento', (tester) async {
    final repository = _FakeLeakCommunityRepository(
      listError: const NetworkException(),
    );
    await _pump(tester, repository);

    expect(
      find.text('No pudimos cargar las fugas cercanas.'),
      findsOneWidget,
    );

    repository.listError = null;
    repository.list = [_summary(id: 'r1')];
    await tester.tap(find.byKey(recentLeaksRetryKey));
    await tester.pumpAndSettle();

    expect(find.text('La Caranta · Maneiro'), findsOneWidget);
  });
}
