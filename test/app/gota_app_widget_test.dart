import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gota/app/app.dart';
import 'package:gota/core/config/app_config.dart';
import 'package:gota/features/location/data/municipality_repository.dart';
import 'package:gota/features/location/data/sector_repository.dart';
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
        ],
        child: const GotaApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Header y acciones principales del home.
    expect(find.text('GOTA'), findsOneWidget);
    expect(find.text('Reportar fuga'), findsOneWidget);
    expect(find.text('Llegó / Se fue el agua'), findsOneWidget);

    // Etiquetas de la barra de navegación.
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Reportar'), findsOneWidget);
    expect(find.text('Agua'), findsOneWidget);
    expect(find.text('Más'), findsOneWidget);
  });

  testWidgets('Navegar a Más muestra la pantalla de placeholder', (
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
        ],
        child: const GotaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Más'), findsOneWidget);
    expect(
      find.text('Esta función estará disponible próximamente.'),
      findsOneWidget,
    );
  });
}
