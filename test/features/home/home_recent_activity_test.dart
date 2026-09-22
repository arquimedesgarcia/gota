import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/features/home/presentation/home_screen.dart';
import 'package:gota/features/leaks/data/community_summary_repository.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/community_activity.dart';
import 'package:gota/features/leaks/domain/community_summary.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/leaks/presentation/recent_activity_card.dart';
import 'package:gota/features/notifications/data/notification_repository.dart';
import 'package:gota/features/notifications/domain/notification_page.dart';
import 'package:gota/features/notifications/domain/notification_preferences.dart';

class _FakeSummaryRepository implements CommunitySummaryRepository {
  @override
  Future<CommunitySummary> todaySummary({
    String? sectorId,
    DateTime? nowUtc,
    int validatedThreshold = 3,
  }) async => const CommunitySummary(
    reportedToday: 0,
    resolvedToday: 0,
    activeReported: 0,
    activeValidated: 0,
  );
}

class _FakeLeakCommunityRepository implements LeakCommunityRepository {
  _FakeLeakCommunityRepository(this.activity);

  final CommunityActivity? activity;

  @override
  Future<CommunityActivity?> latestActivity() async => activity;

  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async => const [];

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
  }) async => const [];
}

class _FakeNotificationRepository implements NotificationRepository {
  @override
  Future<NotificationPreferences?> getPreferences() async => null;

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

CommunityActivity _activity() => CommunityActivity(
  type: CommunityActivityType.reported,
  at: DateTime.now().subtract(const Duration(hours: 1)),
  reportId: 'r1',
  status: 'ACTIVE',
  validationCount: 1,
  resolutionConfirmationCount: 0,
  createdAt: DateTime.now().subtract(const Duration(hours: 1)),
  sectorName: 'La Caranta',
  municipalityName: 'Maneiro',
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required CommunityActivity? activity,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communitySummaryRepositoryProvider.overrideWithValue(
          _FakeSummaryRepository(),
        ),
        notificationRepositoryProvider.overrideWithValue(
          _FakeNotificationRepository(),
        ),
        leakCommunityRepositoryProvider.overrideWithValue(
          _FakeLeakCommunityRepository(activity),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'la tarjeta se renderiza después de "Fugas activas en el mapa"',
    (tester) async {
      await _pumpHome(tester, activity: _activity());

      expect(find.byType(RecentActivityCard), findsOneWidget);
      expect(find.text('Actividad reciente'), findsOneWidget);

      final mapDy = tester
          .getTopLeft(find.text('Fugas activas en el mapa'))
          .dy;
      final activityDy = tester
          .getTopLeft(find.text('Actividad reciente'))
          .dy;
      expect(activityDy, greaterThan(mapDy));
    },
  );

  testWidgets('sin actividad la tarjeta sigue visible con el respaldo', (
    tester,
  ) async {
    await _pumpHome(tester, activity: null);

    expect(find.byType(RecentActivityCard), findsOneWidget);
    expect(find.text('Sin actividad reciente'), findsOneWidget);
  });
}
