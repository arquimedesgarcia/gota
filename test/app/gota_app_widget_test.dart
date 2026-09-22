import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gota/app/app.dart';
import 'package:gota/core/config/app_config.dart';
import 'package:gota/features/location/data/municipality_repository.dart';
import 'package:gota/features/location/data/sector_repository.dart';
import 'package:gota/features/notifications/data/notification_repository.dart';
import 'package:gota/features/notifications/data/push_service.dart';
import 'package:gota/features/notifications/domain/notification_page.dart';
import 'package:gota/features/notifications/domain/notification_preferences.dart';
import 'package:gota/shared/models/app_user.dart';
import 'package:gota/shared/models/municipality.dart';
import 'package:gota/shared/models/sector.dart';
import 'package:gota/shared/services/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  Future<AppUser> ensureSessionAndProfile() async => AppUser.fromJson(const {
    'id': 'app-user-1',
    'auth_user_id': 'auth-user-1',
    'created_at': '2024-01-01T00:00:00.000Z',
    'last_seen_at': null,
    'is_blocked': false,
  });
}

class FakeMunicipalityRepository implements MunicipalityRepository {
  @override
  Future<List<Municipality>> getActive() async => const [];
}

class FakeSectorRepository implements SectorRepository {
  @override
  Future<List<Sector>> getByMunicipality(String municipalityId) async =>
      const [];

  @override
  Future<Sector?> getById(String id) async => null;
}

/// Mínimo necesario para que la pestaña Más (Ajustes, Sprint 06) construya
/// sin Supabase: bandeja vacía y preferencias inexistentes.
class FakeNotificationRepository implements NotificationRepository {
  @override
  Future<NotificationPreferences?> getPreferences() async => null;

  @override
  Future<NotificationPreferences> savePreferences({
    String? sectorId,
    required bool enabled,
  }) => throw UnimplementedError();

  @override
  Future<NotificationInboxPage> fetchInbox({
    int limit = 20,
    String? beforeIso,
  }) async => const NotificationInboxPage(items: []);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> registerToken(String token, String platform) async {}

  @override
  Future<void> unregisterToken(String token) async {}

  @override
  Stream<String> watchNotifications(String userId) =>
      const Stream<String>.empty();
}

void main() {
  testWidgets('GotaApp muestra el home y la navegación de cinco destinos', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              supabaseUrl: 'https://demo.supabase.co',
              supabaseAnonKey: 'anon-key',
            ),
          ),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          municipalityRepositoryProvider.overrideWithValue(
            FakeMunicipalityRepository(),
          ),
          sectorRepositoryProvider.overrideWithValue(FakeSectorRepository()),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          pushServiceProvider.overrideWithValue(const NoopPushService()),
        ],
        child: const GotaApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Header y acciones principales del home.
    expect(find.text('GOTA'), findsOneWidget);
    expect(find.text('Reportar fuga'), findsOneWidget);
    expect(find.text('Reportar agua'), findsOneWidget);

    // Etiquetas de la barra de navegación.
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Reportar'), findsOneWidget);
    expect(find.text('Agua'), findsOneWidget);
    expect(find.text('Más'), findsOneWidget);
  });

  testWidgets('Navegar a Más muestra Ajustes (Sprint 06)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              supabaseUrl: 'https://demo.supabase.co',
              supabaseAnonKey: 'anon-key',
            ),
          ),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          municipalityRepositoryProvider.overrideWithValue(
            FakeMunicipalityRepository(),
          ),
          sectorRepositoryProvider.overrideWithValue(FakeSectorRepository()),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          pushServiceProvider.overrideWithValue(const NoopPushService()),
        ],
        child: const GotaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Ajustes'), findsOneWidget);
    // Estado sin sector de interés seleccionado.
    expect(
      find.text('No tienes un sector de interés seleccionado.'),
      findsOneWidget,
    );
    // Preferencia de notificaciones de agua separada del sector.
    expect(find.text('Notificaciones de agua'), findsOneWidget);
  });
}
