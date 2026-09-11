import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_exception.dart';

/// Configuración de la aplicación, inyectada vía `--dart-define`.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.environment = 'development',
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// 'development' o 'production' (dart-define `SUPABASE_ENV`).
  final String environment;

  /// Lee la configuración de las variables de compilación.
  ///
  /// Lanza [ConfigMissingException] si faltan valores o la URL no es http(s).
  static AppConfig fromEnvironment() => fromValues(
        supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
        environment: const String.fromEnvironment(
          'SUPABASE_ENV',
          defaultValue: 'development',
        ),
      );

  /// Punto de entrada comprobable: valida los valores y construye el objeto.
  static AppConfig fromValues({
    required String supabaseUrl,
    required String supabaseAnonKey,
    String environment = 'development',
  }) {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw const ConfigMissingException();
    }
    final uri = Uri.tryParse(supabaseUrl);
    final isHttp = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!isHttp) {
      throw const ConfigMissingException();
    }
    return AppConfig(
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      environment: environment,
    );
  }
}

/// Configuración de la app; es `null` cuando falta o es inválida.
///
/// En ese caso la app muestra [ConfigMissingView] en lugar de crashear.
/// El bootstrap de `main.dart` sobreescribe este provider con el valor ya
/// validado (e incluyendo cualquier fallo de `Supabase.initialize`).
final appConfigProvider = Provider<AppConfig?>((ref) {
  try {
    return AppConfig.fromEnvironment();
  } on ConfigMissingException {
    return null;
  }
});
