import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gota/core/config/app_config.dart';
import 'package:gota/core/errors/app_exception.dart';

void main() {
  group('AppConfig', () {
    test('fromEnvironment sin dart-defines lanza ConfigMissingException', () {
      // Los tests se compilan sin --dart-define, por lo que las variables
      // llegan vacías y la configuración se considera faltante.
      expect(
        () => AppConfig.fromEnvironment(),
        throwsA(isA<ConfigMissingException>()),
      );
    });

    test('fromValues con URL y clave válidas parsea los campos', () {
      final config = AppConfig.fromValues(
        supabaseUrl: 'https://demo.supabase.co',
        supabaseAnonKey: 'anon-key',
      );

      expect(config.supabaseUrl, 'https://demo.supabase.co');
      expect(config.supabaseAnonKey, 'anon-key');
      expect(config.environment, 'development');
    });

    test('fromValues respeta el ambiente indicado', () {
      final config = AppConfig.fromValues(
        supabaseUrl: 'https://demo.supabase.co',
        supabaseAnonKey: 'anon-key',
        environment: 'production',
      );

      expect(config.environment, 'production');
    });

    test('fromValues rechaza URL o clave vacías', () {
      expect(
        () => AppConfig.fromValues(supabaseUrl: '', supabaseAnonKey: 'k'),
        throwsA(isA<ConfigMissingException>()),
      );
      expect(
        () => AppConfig.fromValues(
          supabaseUrl: 'https://demo.supabase.co',
          supabaseAnonKey: '',
        ),
        throwsA(isA<ConfigMissingException>()),
      );
    });

    test('fromValues rechaza URLs que no sean http(s)', () {
      expect(
        () => AppConfig.fromValues(
          supabaseUrl: 'ftp://demo.supabase.co',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<ConfigMissingException>()),
      );
      expect(
        () => AppConfig.fromValues(
          supabaseUrl: 'no-es-una-url',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<ConfigMissingException>()),
      );
    });
  });

  group('appConfigProvider', () {
    test('devuelve null cuando falta la configuración', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appConfigProvider), isNull);
    });
  });
}
