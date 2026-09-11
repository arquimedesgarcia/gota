import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Abstracción sobre las consultas de Supabase usadas en el sprint 01.
///
/// Devuelve filas crudas (`Map<String, dynamic>`); el mapeo a modelos y a
/// [AppException] ocurre en los repositorios.
abstract class GotaDatabase {
  Future<List<Map<String, dynamic>>> fetchActiveMunicipalities();

  Future<List<Map<String, dynamic>>> fetchSectorsForMunicipality(
    String municipalityId,
  );

  Future<Map<String, dynamic>?> fetchAppUserByAuthId(String authUserId);

  /// Crea o actualiza el perfil del usuario autenticado vía la RPC
  /// `ensure_app_user` (idempotente) y devuelve la fila de `app_users`.
  Future<Map<String, dynamic>> ensureAppUser();

  /// Invoca la RPC protegida `create_leak_report` y devuelve su `jsonb`
  /// deserializado (`status_code` + payload).
  Future<Map<String, dynamic>> rpcCreateLeakReport(
    Map<String, dynamic> params,
  );
}

class SupabaseGotaDatabase implements GotaDatabase {
  SupabaseGotaDatabase(this._client);

  final supabase.SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchActiveMunicipalities() async {
    final rows = await _client
        .from('municipalities')
        .select()
        .eq('is_active', true)
        .order('name');
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSectorsForMunicipality(
    String municipalityId,
  ) async {
    final rows = await _client
        .from('sectors')
        .select()
        .eq('municipality_id', municipalityId)
        .eq('is_active', true)
        .order('name');
    return rows;
  }

  @override
  Future<Map<String, dynamic>?> fetchAppUserByAuthId(
    String authUserId,
  ) async {
    final rows =
        await _client.from('app_users').select().eq('auth_user_id', authUserId);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  @override
  Future<Map<String, dynamic>> ensureAppUser() async {
    final data = await _client.rpc('ensure_app_user');
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    throw StateError('ensure_app_user devolvió un formato inesperado.');
  }

  @override
  Future<Map<String, dynamic>> rpcCreateLeakReport(
    Map<String, dynamic> params,
  ) async {
    final data =
        await _client.rpc<dynamic>('create_leak_report', params: params);
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('create_leak_report devolvió un formato inesperado.');
  }
}
