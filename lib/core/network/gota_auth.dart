import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Abstracción sobre las operaciones de autenticación de Supabase.
///
/// Es la costura de testeo: los repositorios dependen de esta interfaz,
/// nunca de [supabase.SupabaseClient] directamente.
abstract class GotaAuth {
  supabase.Session? currentSession();

  Future<supabase.Session> signInAnonymously();
}

class SupabaseGotaAuth implements GotaAuth {
  SupabaseGotaAuth(this._client);

  final supabase.SupabaseClient _client;

  @override
  supabase.Session? currentSession() => _client.auth.currentSession;

  @override
  Future<supabase.Session> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    final session = response.session;
    if (session == null) {
      throw const supabase.AuthException(
        'No se pudo crear una sesión anónima.',
      );
    }
    return session;
  }
}
