import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/home/presentation/community_summary_providers.dart';
import 'package:gota/features/home/presentation/home_screen.dart';
import 'package:gota/features/leaks/data/community_summary_repository.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/community_summary.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/location/data/sector_repository.dart';
import 'package:gota/features/notifications/data/notification_repository.dart';
import 'package:gota/features/notifications/domain/notification_page.dart';
import 'package:gota/features/notifications/domain/notification_preferences.dart';
import 'package:gota/shared/models/sector.dart';

class _FakeSummaryRepository implements CommunitySummaryRepository {
  int reported = 0;
  int resolved = 0;
  Object? error;
  String? lastSectorId;

  @override
  Future<CommunitySummary> todaySummary({
    String? sectorId,
    DateTime? nowUtc,
  }) async {
    if (error != null) throw error!;
    lastSectorId = sectorId;
    return CommunitySummary(
      reportedToday: reported,
      resolvedToday: resolved,
    );
  }
}

class _FakeLeakCommunityRepository implements LeakCommunityRepository {
  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async => [
    LeakSummary(
      id: 'r1',
      status: 'ACTIVE',
      validationCount: 1,
      resolutionConfirmationCount: 0,
      createdAt: DateTime.utc(2026, 9, 15, 10),
      sectorName: 'La Caranta',
      municipalityName: 'Maneiro',
    ),
  ];

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

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this.preferences);

  NotificationPreferences? preferences;

  @override
  Future<NotificationPreferences?> getPreferences() async => preferences;

  @override
  Future<NotificationPreferences> savePreferences({
    String? sectorId,
    required bool enabled,
  }) => throw UnimplementedError();

  @override
  Future<NotificationInboxPage> fetchInbox({int limit = 20, String? beforeIso}) =>
      throw UnimplementedError();

  @override
  Future<void> markRead(String id) => throw UnimplementedError();

  @override
  Future<void> registerToken(String token, String platform) =>
      throw UnimplementedError();

  @override
  Future<void> unregisterToken(String token) => throw UnimplementedError();

  @override
  Stream<String> watchNotifications(String userId) =>
      throw UnimplementedError();
}

class _FakeSectorRepository implements SectorRepository {
  @override
  Future<List<Sector>> getByMunicipality(String municipalityId) async =>
      const [];

  @override
  Future<Sector?> getById(String id) async => const Sector(
    id: 's1',
    municipalityId: 'm1',
    name: 'La Caranta',
    isActive: true,
  );
}

NotificationPreferences _prefs({String? sectorId}) => NotificationPreferences(
  userId: 'u1',
  preferredSectorId: sectorId,
  waterNotificationsEnabled: false,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required _FakeSummaryRepository summary,
  NotificationPreferences? preferences,
}) async {
  // Viewport alto: HomeScreen usa ListView perezoso (ver test S10-B).
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communitySummaryRepositoryProvider.overrideWithValue(summary),
        notificationRepositoryProvider.overrideWithValue(
          _FakeNotificationRepository(preferences),
        ),
        sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
        leakCommunityRepositoryProvider.overrideWithValue(
          _FakeLeakCommunityRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const HomeScreen();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('S10-C tarjeta Hoy en tu comunidad', () {
    testWidgets('Caso 1: muestra reportadas y resueltas de hoy', (
      tester,
    ) async {
      final summary = _FakeSummaryRepository()
        ..reported = 3
        ..resolved = 1;
      await _pumpHome(tester, summary: summary);

      expect(find.text('Hoy en tu comunidad'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('reportadas hoy'), findsOneWidget);
      expect(find.text('resueltas hoy'), findsOneWidget);
      expect(find.text('Sin datos todavía'), findsNothing);
    });

    testWidgets('Caso 7: sin actividad muestra 0/0 sin ocultar la tarjeta', (
      tester,
    ) async {
      await _pumpHome(tester, summary: _FakeSummaryRepository());

      expect(find.text('Hoy en tu comunidad'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      // El único "Sin datos todavía" visible es el de la tarjeta (la lista
      // de fugas tiene un item en este test).
      expect(find.text('Sin datos todavía'), findsOneWidget);
      expect(find.text('Cobertura del piloto'), findsOneWidget);
    });

    testWidgets('Caso 5: con sector de interés etiqueta y filtra por sector', (
      tester,
    ) async {
      final summary = _FakeSummaryRepository()
        ..reported = 2
        ..resolved = 0;
      await _pumpHome(
        tester,
        summary: summary,
        preferences: _prefs(sectorId: 's1'),
      );

      expect(find.text('La Caranta'), findsOneWidget);
      expect(find.text('Cobertura del piloto'), findsNothing);
      expect(summary.lastSectorId, 's1');
    });

    testWidgets('Caso 6: sin sector el alcance es global', (tester) async {
      final summary = _FakeSummaryRepository();
      await _pumpHome(tester, summary: summary);

      expect(find.text('Cobertura del piloto'), findsOneWidget);
      expect(summary.lastSectorId, isNull);
    });

    testWidgets('Caso 8: error no se convierte en ceros y admite retry', (
      tester,
    ) async {
      final summary = _FakeSummaryRepository()
        ..error = Exception('backend caído');
      final container = await _pumpHome(tester, summary: summary);

      expect(
        find.text('No pudimos cargar la actividad de hoy.'),
        findsOneWidget,
      );
      expect(find.byKey(communitySummaryRetryKey), findsOneWidget);
      // La lista de fugas sigue funcionando (resto de Home intacto).
      expect(find.text('Fugas cerca de ti'), findsOneWidget);

      summary.error = null;
      summary.reported = 1;
      await tester.tap(find.byKey(communitySummaryRetryKey));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(
        find.text('No pudimos cargar la actividad de hoy.'),
        findsNothing,
      );
      container.invalidate(communitySummaryProvider);
    });

    testWidgets('Caso 9: tras invalidate refleja el nuevo reporte', (
      tester,
    ) async {
      final summary = _FakeSummaryRepository();
      final container = await _pumpHome(tester, summary: summary);
      expect(find.text('0'), findsNWidgets(2));

      summary.reported = 1;
      container.invalidate(communitySummaryProvider);
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });
}
