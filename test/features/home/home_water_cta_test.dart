import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/home/presentation/home_screen.dart';
import 'package:gota/features/leaks/data/community_summary_repository.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/community_activity.dart';
import 'package:gota/features/leaks/domain/community_summary.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/location/data/sector_repository.dart';
import 'package:gota/features/notifications/data/notification_repository.dart';
import 'package:gota/features/notifications/domain/notification_page.dart';
import 'package:gota/features/notifications/domain/notification_preferences.dart';
import 'package:gota/features/water/data/water_event_repository.dart';
import 'package:gota/core/network/gota_water_database.dart';
import 'package:gota/features/water/domain/water_event.dart';
import 'package:gota/features/water/domain/water_event_detail.dart';
import 'package:gota/features/water/domain/water_event_type.dart';
import 'package:gota/shared/models/sector.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

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
  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async => [];
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
  Future<CommunityActivity?> latestActivity() async => null;
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
  }) async => [];
}

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this._prefs);

  final NotificationPreferences? _prefs;

  @override
  Future<NotificationPreferences?> getPreferences() async => _prefs;

  @override
  Future<NotificationPreferences> savePreferences({
    String? sectorId,
    required bool enabled,
  }) => throw UnimplementedError();

  @override
  Future<NotificationInboxPage> fetchInbox({
    int limit = 20,
    String? beforeIso,
  }) => throw UnimplementedError();

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
  Future<List<Sector>> getByMunicipality(String municipalityId) async => [];

  @override
  Future<Sector?> getById(String id) async => const Sector(
    id: 's1',
    municipalityId: 'm1',
    name: 'La Caranta',
    isActive: true,
  );
}

class _FakeWaterEventRepository implements WaterEventRepository {
  WaterEventSummary? latestEventResult;

  @override
  Future<WaterEventSummary?> latestEvent({String? sectorId}) async =>
      latestEventResult;

  @override
  Future<(WaterEventSummary, bool isConfirmation)> register({
    required String municipalityId,
    required String sectorId,
    required WaterEventType type,
    required DateTime eventTime,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<int> validate(String eventId) => throw UnimplementedError();

  @override
  Future<WaterEventDetail> detail(String eventId) =>
      throw UnimplementedError();

  @override
  Future<WaterEventsPage> recentEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  }) => throw UnimplementedError();
}

NotificationPreferences _prefs({required String sectorId}) =>
    NotificationPreferences(
      userId: 'u1',
      preferredSectorId: sectorId,
      waterNotificationsEnabled: false,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

Future<void> _pumpHome(
  WidgetTester tester, {
  NotificationPreferences? preferences,
  WaterEventSummary? waterEvent,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final waterRepo = _FakeWaterEventRepository()..latestEventResult = waterEvent;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communitySummaryRepositoryProvider.overrideWithValue(
          _FakeSummaryRepository(),
        ),
        notificationRepositoryProvider.overrideWithValue(
          _FakeNotificationRepository(preferences),
        ),
        sectorRepositoryProvider.overrideWithValue(_FakeSectorRepository()),
        leakCommunityRepositoryProvider.overrideWithValue(
          _FakeLeakCommunityRepository(),
        ),
        waterEventRepositoryProvider.overrideWithValue(waterRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('S13 _WaterMetric — rescope del sector de interés', () {
    testWidgets(
      'sin sector seleccionado muestra CTA accionable',
      (tester) async {
        await _pumpHome(tester); // preferences = null → sin sector

        expect(
          find.text(
            'Selecciona tu sector para ver el estado del agua en tu zona',
          ),
          findsOneWidget,
        );
        // "Sin información del agua" NO debe aparecer cuando se muestra la CTA.
        expect(find.text('Sin información del agua'), findsNothing);
      },
    );

    testWidgets(
      'con sector pero sin eventos de agua muestra "Sin información del agua"',
      (tester) async {
        await _pumpHome(
          tester,
          preferences: _prefs(sectorId: 's1'),
          // waterEvent = null → sin eventos
        );

        expect(find.text('Sin información del agua'), findsOneWidget);
        expect(
          find.text(
            'Selecciona tu sector para ver el estado del agua en tu zona',
          ),
          findsNothing,
        );
        // La etiqueta del sector se muestra.
        expect(find.text('Agua en tu sector'), findsWidgets);
      },
    );

    testWidgets(
      'con sector y evento "llegó" muestra "Llegó"',
      (tester) async {
        final event = WaterEventSummary(
          id: 'w1',
          type: WaterEventType.arrived,
          eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          validationCount: 0,
          createdAt: DateTime.now().toUtc(),
        );

        await _pumpHome(
          tester,
          preferences: _prefs(sectorId: 's1'),
          waterEvent: event,
        );

        expect(find.text('Llegó'), findsOneWidget);
        expect(
          find.text(
            'Selecciona tu sector para ver el estado del agua en tu zona',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'con sector y evento "se fue" muestra "Se fue"',
      (tester) async {
        final event = WaterEventSummary(
          id: 'w2',
          type: WaterEventType.left,
          eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          validationCount: 1,
          createdAt: DateTime.now().toUtc(),
        );

        await _pumpHome(
          tester,
          preferences: _prefs(sectorId: 's1'),
          waterEvent: event,
        );

        expect(find.text('Se fue'), findsOneWidget);
      },
    );

    testWidgets(
      'CTA es tappable (al menos no explota al tocarlo)',
      (tester) async {
        await _pumpHome(tester); // sin sector → muestra CTA

        final cta = find.text(
          'Selecciona tu sector para ver el estado del agua en tu zona',
        );
        expect(cta, findsOneWidget);

        // Tap: puede que SectorSelectionScreen requiera Supabase; solo
        // verificamos que el gesto no lanza excepción no controlada.
        await tester.tap(cta, warnIfMissed: false);
        await tester.pump(); // no pumpAndSettle: puede iniciar navegación
      },
    );
  });
}
