/// Errores tipados de la aplicación.
///
/// Cada excepción expone un [userMessage] en español, apto para mostrar
/// directamente en la UI. Los repositorios son los responsables de mapear
/// las excepciones crudas de Supabase/red a estos tipos.
sealed class AppException implements Exception {
  const AppException(this.userMessage);

  /// Mensaje amigable para el usuario final.
  final String userMessage;
}

/// Las credenciales o la URL de Supabase no están configuradas.
class ConfigMissingException extends AppException {
  const ConfigMissingException()
    : super('Falta configuración de la aplicación.');
}

/// Fallo al crear o recuperar la sesión anónima.
class AuthException extends AppException {
  const AuthException([
    super.userMessage = 'Ocurrió un problema al iniciar tu sesión. Cierra y abre la app de nuevo.',
  ]);
}

/// Sin conexión o timeout de red.
class NetworkException extends AppException {
  const NetworkException([
    super.userMessage = 'No pudimos conectar. Revisa tu conexión a internet e intenta de nuevo.',
  ]);
}

/// La consulta al backend falló o devolvió datos inválidos.
class QueryException extends AppException {
  const QueryException([
    super.userMessage = 'No pudimos cargar la información. Intenta de nuevo.',
  ]);
}
