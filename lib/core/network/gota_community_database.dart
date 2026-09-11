import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Abstracción de las consultas del ciclo comunitario (Sprint 03):
/// lectura de fugas recientes, detalle con estado del usuario y las RPC
/// protegidas de validación y resolución.
///
/// Mantiene el patrón de Sprint 01/02: los repositorios dependen de esta
/// costura, nunca de [supabase.SupabaseClient] (docs/ARCHITECTURE.md §4).
abstract class GotaCommunityDatabase {
  /// Reportes recientes (ACTIVE primero). Lectura simple por SDK + RLS.
  Future<List<Map<String, dynamic>>> fetchRecentLeakReports({int limit});

  /// RPC `get_leak_report_detail`: detalle + estado del usuario actual.
  Future<Map<String, dynamic>> rpcLeakReportDetail(String reportId);

  /// RPC `validate_leak`.
  Future<Map<String, dynamic>> rpcValidateLeak(String reportId);

  /// RPC `confirm_leak_resolution`.
  Future<Map<String, dynamic>> rpcConfirmLeakResolution(String reportId);
}

class SupabaseGotaCommunityDatabase implements GotaCommunityDatabase {
  SupabaseGotaCommunityDatabase(this._client);

  final supabase.SupabaseClient _client;

  /// Columnas del listado: solo lo necesario para pintar la lista
  /// (docs/API_SPEC.md §5) y los contadores comunitarios.
  static const _listColumns = 'id, status, validation_count, '
      'resolution_confirmation_count, created_at, resolved_at, description, '
      'sectors(name), municipalities(name)';

  @override
  Future<List<Map<String, dynamic>>> fetchRecentLeakReports({
    int limit = 20,
  }) async {
    final rows = await _client
        .from('reports')
        .select(_listColumns)
        .order('status')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows;
  }

  @override
  Future<Map<String, dynamic>> rpcLeakReportDetail(String reportId) async {
    final data = await _client.rpc<dynamic>(
      'get_leak_report_detail',
      params: {'p_report_id': reportId},
    );
    return _asMap(data, 'get_leak_report_detail');
  }

  @override
  Future<Map<String, dynamic>> rpcValidateLeak(String reportId) async {
    final data = await _client.rpc<dynamic>(
      'validate_leak',
      params: {'p_report_id': reportId},
    );
    return _asMap(data, 'validate_leak');
  }

  @override
  Future<Map<String, dynamic>> rpcConfirmLeakResolution(String reportId) async {
    final data = await _client.rpc<dynamic>(
      'confirm_leak_resolution',
      params: {'p_report_id': reportId},
    );
    return _asMap(data, 'confirm_leak_resolution');
  }

  Map<String, dynamic> _asMap(Object? data, String rpcName) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('$rpcName devolvió un formato inesperado.');
  }
}
