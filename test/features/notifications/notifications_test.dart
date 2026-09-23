import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/providers.dart';
import 'package:gota/app/router/app_navigator.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/features/location/presentation/location_providers.dart';
import 'package:gota/features/notifications/data/notification_repository.dart';
import 'package:gota/features/notifications/data/push_service.dart';
import 'package:gota/features/notifications/domain/notification_page.dart';
import 'package:gota/features/notifications/domain/notification_preferences.dart';
import 'package:gota/features/notifications/domain/water_notification.dart';
import 'package:gota/features/notifications/presentation/notification_providers.dart';
import 'package:gota/features/notifications/presentation/notifications_screen.dart';
import 'package:gota/features/notifications/presentation/settings_screen.dart';
import 'package:gota/shared/widgets/loading_view.dart';
import 'package:gota/features/water/data/water_event_repository.dart';
import 'package:gota/features/water/domain/water_event.dart';
import 'package:gota/features/water/domain/water_event_detail.dart';
import 'package:gota/features/water/domain/water_event_type.dart';
import 'package:gota/core/network/gota_water_database.dart';
import 'package:gota/features/water/presentation/water_event_detail_screen.dart';
import 'package:gota/shared/models/app_user.dart';

WaterNotification _notification({
  required String id,
  WaterEventType type = WaterEventType.arrived,
  bool unread = true,
  String? eventId,
}) => WaterNotification(
  id: id,
  type: type,
  title: 'Llegó el agua',
  body: 'Sector Centro',
  createdAt: DateTime(2026, 9, 12, 10),
  readAt: unread ? null : DateTime(2026, 9, 12, 11),
  eventTime: DateTime(2026, 9, 12, 9, 55),
  eventId: eventId,
  sectorName: 'Centro',
  municipalityName: 'Maneiro',
);

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository({List<WaterNotification>? inbox})
    : inbox = inbox ?? const [];

  NotificationPreferences? preferences;
  Object? preferencesError;
  List<WaterNotification> inbox;
  Object? inboxError;
  final List<String> readIds = [];
  final List<(String, String)> registeredTokens = [];
  final List<String> unregisteredTokens = [];
  final savedPreferences = <(String?, bool)>[];

  @override
  Future<NotificationPreferences?> getPreferences() async {
    if (preferencesError != null) throw preferencesError!;
    return preferences;
  }

  @override
  Future<NotificationPreferences> savePreferences({
    String? sectorId,
    required bool enabled,
  }) async {
    if (preferencesError != null) throw preferencesError!;
    savedPreferences.add((sectorId, enabled));
    final current = preferences;
    final saved = NotificationPreferences(
      userId: current?.userId ?? 'user-1',
      preferredSectorId: sectorId,
      waterNotificationsEnabled: enabled,
      createdAt: current?.createdAt ?? DateTime(2026),
      updatedAt: DateTime(2026),
    );
    preferences = saved;
    return saved;
  }

  @override
  Future<NotificationInboxPage> fetchInbox({
    int limit = 20,
    String? beforeIso,
  }) async {
    if (inboxError != null) throw inboxError!;
    return NotificationInboxPage(items: inbox);
  }

  @override
  Future<void> markRead(String id) async => readIds.add(id);

  @override
  Future<void> registerToken(String token, String platform) async {
    registeredTokens.add((token, platform));
  }

  @override
  Future<void> unregisterToken(String token) async =>
      unregisteredTokens.add(token);

  @override
  Stream<String> watchNotifications(String userId) =>
      const Stream<String>.empty();
}

class _FakeWaterRepository implements WaterEventRepository {
  @override
  Future<WaterEventDetail> detail(String eventId) async => WaterEventDetail(
    id: eventId,
    type: WaterEventType.arrived,
    eventTime: DateTime(2026, 9, 12, 9, 55),
    validationCount: 0,
    createdAt: DateTime(2026, 9, 12, 10),
    isCreator: false,
    isBlocked: false,
    alreadyValidated: false,
  );

  @override
  Future<WaterEventSummary> register({
    required String municipalityId,
    required String sectorId,
    required WaterEventType type,
    required DateTime eventTime,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<int> validate(String eventId) => throw UnimplementedError();

  @override
  Future<WaterEventsPage> recentEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  }) => throw UnimplementedError();

  @override
  Future<WaterEventSummary?> latestEvent({String? sectorId}) async => null;
}

class _FakePushService implements PushService {
  final openedController = StreamController<RemoteMessage>.broadcast();
  RemoteMessage? initialMessage;
  String? token = 'fcm-token-1';

  @override
  Future<PushPermissionStatus> requestPermission() async =>
      PushPermissionStatus.granted;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get tokenRefresh => const Stream<String>.empty();

  @override
  Stream<RemoteMessage> get onMessageForeground =>
      const Stream<RemoteMessage>.empty();

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => openedController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;
}

class _BlockedSaveRepository extends _FakeNotificationRepository {
  _BlockedSaveRepository(this._completer);

  final Completer<NotificationPreferences> _completer;

  @override
  Future<NotificationPreferences> savePreferences({
    String? sectorId,
    required bool enabled,
  }) => _completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationInboxController', () {
    test('carga inicial: inbox con datos y conteo de no leídas', () async {
      final repo = _FakeNotificationRepository(
        inbox: [
          _notification(id: 'n1'),
          _notification(id: 'n2', unread: false),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          sessionBootstrapProvider.overrideWith(
            (ref) async => _sessionUserValue,
          ),
        ],
      );
      addTearDown(container.dispose);

      await _waitForInbox(container);
      final state = container.read(notificationInboxControllerProvider);
      expect(state.items.value, hasLength(2));
      expect(container.read(unreadCountProvider), 1);
    });

    test('inbox vacío y error de carga', () async {
      final emptyRepo = _FakeNotificationRepository();
      final emptyContainer = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(emptyRepo),
          sessionBootstrapProvider.overrideWith(
            (ref) async => _sessionUserValue,
          ),
        ],
      );
      addTearDown(emptyContainer.dispose);
      await _waitForInbox(emptyContainer);
      expect(
        emptyContainer.read(notificationInboxControllerProvider).items.value,
        isEmpty,
      );

      final failingRepo = _FakeNotificationRepository()
        ..inboxError = const QueryException('x');
      final failingContainer = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(failingRepo),
          sessionBootstrapProvider.overrideWith(
            (ref) async => _sessionUserValue,
          ),
        ],
      );
      addTearDown(failingContainer.dispose);
      await _waitForInbox(failingContainer);
      expect(
        failingContainer
            .read(notificationInboxControllerProvider)
            .items
            .hasError,
        isTrue,
      );
    });

    test('markRead actualiza optimista y persiste', () async {
      final repo = _FakeNotificationRepository(
        inbox: [_notification(id: 'n1')],
      );
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          sessionBootstrapProvider.overrideWith(
            (ref) async => _sessionUserValue,
          ),
        ],
      );
      addTearDown(container.dispose);
      await _waitForInbox(container);

      await container
          .read(notificationInboxControllerProvider.notifier)
          .markRead('n1');

      final items = container
          .read(notificationInboxControllerProvider)
          .items
          .value!;
      expect(items.single.isUnread, isFalse);
      expect(repo.readIds, ['n1']);
    });
  });

  testWidgets('tap marca leída y navega solo al Water Event válido', (
    tester,
  ) async {
    final repo = _FakeNotificationRepository(
      inbox: [_notification(id: 'n1', eventId: 'event-42')],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          sessionBootstrapProvider.overrideWith(
            (ref) async => _sessionUserValue,
          ),
          waterEventRepositoryProvider.overrideWithValue(
            _FakeWaterRepository(),
          ),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Llegó el agua'));
    await tester.pumpAndSettle();
    expect(repo.readIds, ['n1']);
    expect(find.byType(WaterEventDetailScreen), findsOneWidget);
  });

  testWidgets('tap sin destino conserva la bandeja y no inventa navegación', (
    tester,
  ) async {
    final repo = _FakeNotificationRepository(inbox: [_notification(id: 'n2')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          sessionBootstrapProvider.overrideWith(
            (ref) async => _sessionUserValue,
          ),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Llegó el agua'));
    await tester.pumpAndSettle();
    expect(repo.readIds, ['n2']);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(WaterEventDetailScreen), findsNothing);
  });

  group('NotificationPreferencesController', () {
    test(
      'seleccionar, quitar sector y toggle ON/OFF conservan la regla 0..1',
      () async {
        final repo = _FakeNotificationRepository();
        final container = ProviderContainer(
          overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        await _waitForPreferences(container);

        await container
            .read(notificationPreferencesControllerProvider.notifier)
            .selectSector('sector-x');
        expect(repo.savedPreferences.last, ('sector-x', false));

        await container
            .read(notificationPreferencesControllerProvider.notifier)
            .setWaterNotificationsEnabled(true);
        expect(repo.savedPreferences.last, ('sector-x', true));

        await container
            .read(notificationPreferencesControllerProvider.notifier)
            .clearSector();
        expect(repo.savedPreferences.last, (null, true));

        final state = container.read(notificationPreferencesControllerProvider);
        expect(state.value!.preferredSectorId, isNull);
        expect(state.value!.waterNotificationsEnabled, isTrue);
      },
    );

    test('fallo de guardado: saveError expuesto y estado revertido', () async {
      final repo = _FakeNotificationRepository();
      repo.preferences = NotificationPreferences(
        userId: 'user-1',
        preferredSectorId: 'sector-x',
        waterNotificationsEnabled: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final container = ProviderContainer(
        overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await _waitForPreferences(container);

      repo.preferencesError = const QueryException('red');
      await container
          .read(notificationPreferencesControllerProvider.notifier)
          .selectSector('sector-y');

      final controller = container.read(
        notificationPreferencesControllerProvider.notifier,
      );
      expect(controller.saveError, isA<QueryException>());
      // El estado conserva el dato previo (sector-x), no el fallido.
      expect(
        container
            .read(notificationPreferencesControllerProvider)
            .value!
            .preferredSectorId,
        'sector-x',
      );
    });

    test(
      'guardar antes de que la carga complete no borra el sector',
      () async {
        final repo = _FakeNotificationRepository();
        repo.preferences = NotificationPreferences(
          userId: 'user-1',
          preferredSectorId: 'sector-x',
          waterNotificationsEnabled: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final container = ProviderContainer(
          overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        // Sin esperar la carga inicial
        await container
            .read(notificationPreferencesControllerProvider.notifier)
            .setWaterNotificationsEnabled(true);

        // El guard bloquea: ningún guardado con sectorId null
        expect(repo.savedPreferences.where((p) => p.$1 == null), isEmpty);

        // Esperar carga y verificar que el sector se conserva
        await _waitForPreferences(container);
        expect(
          container
              .read(notificationPreferencesControllerProvider)
              .value
              ?.preferredSectorId,
          'sector-x',
        );
      },
    );

    test(
      'el guard publica el estado y libera a los llamadores',
      () async {
        final repo = _FakeNotificationRepository();
        final container = ProviderContainer(
          overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        // Invocar selectSector antes de que la carga inicial complete
        await container
            .read(notificationPreferencesControllerProvider.notifier)
            .selectSector('x');

        // El estado cambió (ya no es AsyncLoading)
        expect(
          container
              .read(notificationPreferencesControllerProvider)
              .isLoading,
          isFalse,
        );
        // El saveError es StateError
        expect(
          container
              .read(notificationPreferencesControllerProvider.notifier)
              .saveError,
          isA<StateError>(),
        );
      },
    );

    test(
      'el guardado conserva el valor previo en el estado',
      () async {
        final repo = _FakeNotificationRepository();
        repo.preferences = NotificationPreferences(
          userId: 'user-1',
          preferredSectorId: 'sector-a',
          waterNotificationsEnabled: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final container = ProviderContainer(
          overrides: [notificationRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        await _waitForPreferences(container);

        final states = <AsyncValue<NotificationPreferences?>>[];
        container.listen(
          notificationPreferencesControllerProvider,
          (_, next) => states.add(next),
        );

        await container
            .read(notificationPreferencesControllerProvider.notifier)
            .selectSector('sector-b');

        final refreshingState = states.firstWhere(
          (s) => s.isLoading,
          orElse: () => throw StateError('no se encontró estado de carga'),
        );
        expect(refreshingState.isRefreshing, isTrue);
        expect(refreshingState.hasValue, isTrue);
      },
    );

    testWidgets(
      'el sector sigue visible mientras se guarda',
      (tester) async {
        final saveCompleter = Completer<NotificationPreferences>();
        final repo = _BlockedSaveRepository(saveCompleter);
        repo.preferences = NotificationPreferences(
          userId: 'user-1',
          preferredSectorId: 'sector-a',
          waterNotificationsEnabled: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              notificationRepositoryProvider.overrideWithValue(repo),
              pushBootstrapProvider.overrideWith(
                (ref) async => PushPermissionStatus.granted,
              ),
              sessionBootstrapProvider.overrideWith(
                (ref) async => _sessionUserValue,
              ),
              sectorNameProvider('sector-a').overrideWith(
                (ref) async => 'Sector A',
              ),
            ],
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sector A'), findsOneWidget);
        expect(find.byType(LoadingView), findsNothing);

        // Disparar el toggle para iniciar un guardado lento
        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();

        // El sector sigue visible durante el guardado (isRefreshing: true)
        expect(find.text('Sector A'), findsOneWidget);
        expect(find.byType(LoadingView), findsNothing);

        // Completar el guardado
        saveCompleter.complete(
          NotificationPreferences(
            userId: 'user-1',
            preferredSectorId: 'sector-a',
            waterNotificationsEnabled: false,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
        await tester.pumpAndSettle();
      },
    );
  });

  group('Push: registro de token y navegación', () {
    testWidgets('background: tap push navega al Water Event (water_event_id)', (
      tester,
    ) async {
      final push = _FakePushService();
      final notifications = _FakeNotificationRepository();
      await _pumpApp(tester, push, notifications);

      push.openedController.add(_messageWith(waterEventId: 'event-42'));
      await tester.pumpAndSettle();

      expect(find.byType(WaterEventDetailScreen), findsOneWidget);
      expect(
        tester
            .widget<WaterEventDetailScreen>(find.byType(WaterEventDetailScreen))
            .eventId,
        'event-42',
      );
    });

    testWidgets('terminated: getInitialMessage navega al Water Event', (
      tester,
    ) async {
      final push = _FakePushService()
        ..initialMessage = _messageWith(waterEventId: 'event-77');
      final notifications = _FakeNotificationRepository();
      await _pumpApp(tester, push, notifications);
      await tester.pumpAndSettle();

      expect(find.byType(WaterEventDetailScreen), findsOneWidget);
    });

    testWidgets('push sin water_event_id navega a la bandeja', (tester) async {
      final push = _FakePushService();
      final notifications = _FakeNotificationRepository();
      await _pumpApp(tester, push, notifications);

      push.openedController.add(_messageWith());
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    test('el token FCM se registra con la plataforma correcta', () async {
      final push = _FakePushService();
      final notifications = _FakeNotificationRepository();
      final container = ProviderContainer(
        overrides: [
          pushServiceProvider.overrideWithValue(push),
          notificationRepositoryProvider.overrideWithValue(notifications),
          sessionBootstrapProvider.overrideWith(
            (ref) async => _sessionUserValue,
          ),
        ],
      );
      addTearDown(container.dispose);

      final status = await container.read(pushBootstrapProvider.future);
      expect(status, PushPermissionStatus.granted);
      expect(notifications.registeredTokens, [('fcm-token-1', 'android')]);
    });
  });
}

// Valor de sesión usado en los overrides de provider.
final _sessionUserValue = AppUser(
  id: 'user-1',
  authUserId: 'auth-1',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  lastSeenAt: null,
  isBlocked: false,
);

RemoteMessage _messageWith({String? waterEventId}) => RemoteMessage(
  data: {
    'water_event_id': ?waterEventId,
    'notification_id': 'n1',
    'type': 'WATER_ARRIVED',
  },
);

/// Los controllers cargan en un microtask; se espera a que el AsyncValue
/// deje de estar en loading (o registre error) antes de afirmar.
Future<void> _waitForInbox(ProviderContainer container) async {
  for (var i = 0; i < 100; i++) {
    if (!container.read(notificationInboxControllerProvider).items.isLoading) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('el inbox no terminó de cargar');
}

Future<void> _waitForPreferences(ProviderContainer container) async {
  for (var i = 0; i < 100; i++) {
    if (!container.read(notificationPreferencesControllerProvider).isLoading) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('las preferencias no terminaron de cargar');
}

Future<void> _pumpApp(
  WidgetTester tester,
  _FakePushService push,
  _FakeNotificationRepository notifications,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pushServiceProvider.overrideWithValue(push),
        notificationRepositoryProvider.overrideWithValue(notifications),
        sessionBootstrapProvider.overrideWith((ref) async => _sessionUserValue),
        // WaterEventDetailScreen carga su detalle desde este repo.
        waterEventRepositoryProvider.overrideWithValue(_FakeWaterRepository()),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  // Dispara el bootstrap del push (equivale al ref.watch del _SessionGate).
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  );
  unawaited(container.read(pushBootstrapProvider.future));
  await tester.pump();
}
