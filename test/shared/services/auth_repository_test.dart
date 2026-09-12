import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/core/network/gota_auth.dart';
import 'package:gota/core/network/gota_database.dart';
import 'package:gota/shared/services/auth_repository.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class MockGotaAuth extends Mock implements GotaAuth {}

class MockGotaDatabase extends Mock implements GotaDatabase {}

void main() {
  late MockGotaAuth auth;
  late MockGotaDatabase database;
  late SupabaseAuthRepository repository;

  setUp(() {
    auth = MockGotaAuth();
    database = MockGotaDatabase();
    repository = SupabaseAuthRepository(auth, database);
  });

  supabase.Session fakeSession() => supabase.Session.fromJson(const {
    'access_token': 'access-token',
    'token_type': 'bearer',
    'user': {'id': 'auth-user-1'},
  })!;

  Map<String, dynamic> appUserRow() => {
    'id': 'app-user-1',
    'auth_user_id': 'auth-user-1',
    'created_at': '2024-01-01T00:00:00.000Z',
    'last_seen_at': '2024-01-02T00:00:00.000Z',
    'is_blocked': false,
  };

  group('SupabaseAuthRepository.ensureSessionAndProfile', () {
    test(
      'sin sesión existente: inicia sesión anónima una vez y crea el perfil',
      () async {
        when(() => auth.currentSession()).thenReturn(null);
        when(() => auth.signInAnonymously())
            .thenAnswer((_) async => fakeSession());
        when(() => database.ensureAppUser())
            .thenAnswer((_) async => appUserRow());

        final user = await repository.ensureSessionAndProfile();

        verify(() => auth.signInAnonymously()).called(1);
        verify(() => database.ensureAppUser()).called(1);
        expect(user.id, 'app-user-1');
        expect(user.authUserId, 'auth-user-1');
        expect(user.isBlocked, isFalse);
        expect(user.lastSeenAt, isNotNull);
      },
    );

    test(
      'con sesión existente: no inicia sesión pero sí crea el perfil',
      () async {
        when(() => auth.currentSession()).thenReturn(fakeSession());
        when(() => database.ensureAppUser())
            .thenAnswer((_) async => appUserRow());

        final user = await repository.ensureSessionAndProfile();

        verifyNever(() => auth.signInAnonymously());
        verify(() => database.ensureAppUser()).called(1);
        expect(user.id, 'app-user-1');
      },
    );

    test(
      'SocketException al iniciar sesión se mapea a NetworkException',
      () async {
        when(() => auth.currentSession()).thenReturn(null);
        when(() => auth.signInAnonymously())
            .thenThrow(const SocketException('sin red'));

        expect(
          () => repository.ensureSessionAndProfile(),
          throwsA(
            isA<NetworkException>().having(
              (e) => e.userMessage,
              'userMessage',
              'No pudimos conectar. Revisa tu conexión a internet e intenta de nuevo.',
            ),
          ),
        );
        verifyNever(() => database.ensureAppUser());
      },
    );

    test(
      'ClientException al iniciar sesión se mapea a NetworkException',
      () async {
        when(() => auth.currentSession()).thenReturn(null);
        when(() => auth.signInAnonymously())
            .thenThrow(http.ClientException('sin red'));

        expect(
          () => repository.ensureSessionAndProfile(),
          throwsA(isA<NetworkException>()),
        );
      },
    );

    test('AuthException de Supabase se mapea a AuthException', () async {
      when(() => auth.currentSession()).thenReturn(null);
      when(() => auth.signInAnonymously())
          .thenThrow(supabase.AuthException('fallo de autenticación'));

      expect(
        () => repository.ensureSessionAndProfile(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.userMessage,
            'userMessage',
            contains('iniciar tu sesión'),
          ),
        ),
      );
    });

    test(
      'PostgrestException en ensureAppUser se mapea a QueryException',
      () async {
        when(() => auth.currentSession()).thenReturn(fakeSession());
        when(() => database.ensureAppUser()).thenThrow(
          const supabase.PostgrestException(message: 'error de consulta'),
        );

        expect(
          () => repository.ensureSessionAndProfile(),
          throwsA(isA<QueryException>()),
        );
      },
    );
  });
}
