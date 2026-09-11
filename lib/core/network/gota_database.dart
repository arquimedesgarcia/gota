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
  Future<Map<String, dynamic>> ensureAppUser() async {
    final data = await _client.rpc('ensure_app_user');
    Map<String, dynamic> row;
    if (data is Map) {
      row = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty && data.first is Map) {
      row = Map<String, dynamic>.from(data.first as Map);
    } else {
      throw StateError('ensure_app_user devolvió un formato inesperado.');
    }
    // Sin sesión (sesión a medio expirar): la RPC responde UNAUTHORIZED
    // controlado en lugar de una fila; se traduce a error de autenticación.
    if (row['status_code'] == 'UNAUTHORIZED') {
      throw const supabase.AuthException(
        'Tu sesión expiró. Reinicia la app para continuar.',
      );
    }
    return row;
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
