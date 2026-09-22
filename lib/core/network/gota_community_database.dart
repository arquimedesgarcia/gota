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

  /// Conteo de fugas creadas en `[startIso, endIso)` (S10-C: "reportadas
  /// hoy"). [sectorId] restringe al sector de interés; `null` = cobertura
  /// global del piloto. Conteo exacto server-side, sin traer filas.
  Future<int> countReportsCreatedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  });

  /// Conteo de fugas resueltas en `[startIso, endIso)` (S10-C: "resueltas
  /// hoy", por `resolved_at` con `status = RESOLVED`). Mismo alcance que
  /// [countReportsCreatedBetween].
  Future<int> countReportsResolvedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  });

  /// Conteos de fallas ACTIVAS del ámbito, divididas por umbral de
  /// validación comunitaria (mismas reglas visuales del mapa):
  /// `reported` = ACTIVE con `validation_count < validatedThreshold`,
  /// `validated` = ACTIVE con `validation_count >= validatedThreshold`.
  Future<({int reported, int validated})> countActiveReports({
    String? sectorId,
    int validatedThreshold = 3,
  });

  /// RPC `get_leak_report_detail`: detalle + estado del usuario actual.
  Future<Map<String, dynamic>> rpcLeakReportDetail(String reportId);

  /// RPC `validate_leak`.
  Future<Map<String, dynamic>> rpcValidateLeak(String reportId);

  /// RPC `confirm_leak_resolution`.
  Future<Map<String, dynamic>> rpcConfirmLeakResolution(String reportId);

  /// RPC `get_map_reports`: fugas geolocalizadas con filtros (Sprint 05).
  Future<List<Map<String, dynamic>>> rpcGetMapReports({
    String? status,
    String? sectorId,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    String orderBy = 'recent',
    int limit = 100,
  });
}

class SupabaseGotaCommunityDatabase implements GotaCommunityDatabase {
  SupabaseGotaCommunityDatabase(this._client);

  final supabase.SupabaseClient _client;

  /// Columnas del listado: solo lo necesario para pintar la lista
  /// (docs/API_SPEC.md §5) y los contadores comunitarios.
  static const _listColumns =
      'id, status, validation_count, '
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

  /// Columna mínima para los conteos (S10-C): petición explícita sin
  /// `select=*`, porque `created_by` está revocado para `anon` y un select
  /// implícito responde HTTP 401 (PG 42501).
  static const _countColumns = 'id';

  @override
  Future<int> countReportsCreatedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) async {
    var query = _client
        .from('reports')
        .select(_countColumns)
        .gte('created_at', startIso)
        .lt('created_at', endIso);
    if (sectorId != null) query = query.eq('sector_id', sectorId);
    final res = await query.count(supabase.CountOption.exact);
    return res.count;
  }

  @override
  Future<int> countReportsResolvedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) async {
    var query = _client
        .from('reports')
        .select(_countColumns)
        .eq('status', 'RESOLVED')
        .gte('resolved_at', startIso)
        .lt('resolved_at', endIso);
    if (sectorId != null) query = query.eq('sector_id', sectorId);
    final res = await query.count(supabase.CountOption.exact);
    return res.count;
  }

  @override
  Future<({int reported, int validated})> countActiveReports({
    String? sectorId,
    int validatedThreshold = 3,
  }) async {
    Future<int> count({required bool validated}) async {
      var query = _client
          .from('reports')
          .select(_countColumns)
          .eq('status', 'ACTIVE');
      query = validated
          ? query.gte('validation_count', validatedThreshold)
          : query.lt('validation_count', validatedThreshold);
      if (sectorId != null) query = query.eq('sector_id', sectorId);
      final res = await query.count(supabase.CountOption.exact);
      return res.count;
    }

    final results = await Future.wait([
      count(validated: false),
      count(validated: true),
    ]);
    return (reported: results[0], validated: results[1]);
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

  @override
  Future<List<Map<String, dynamic>>> rpcGetMapReports({
    String? status,
    String? sectorId,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    String orderBy = 'recent',
    int limit = 100,
  }) async {
    final params = <String, dynamic>{'p_order_by': orderBy, 'p_limit': limit};
    if (status != null) params['p_status'] = status;
    if (sectorId != null) params['p_sector_id'] = sectorId;
    if (minLat != null) params['p_min_lat'] = minLat;
    if (minLng != null) params['p_min_lng'] = minLng;
    if (maxLat != null) params['p_max_lat'] = maxLat;
    if (maxLng != null) params['p_max_lng'] = maxLng;

    final data = await _client.rpc<dynamic>('get_map_reports', params: params);

    if (data is List) {
      return data
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    throw StateError('get_map_reports devolvió un formato inesperado.');
  }

  Map<String, dynamic> _asMap(Object? data, String rpcName) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('$rpcName devolvió un formato inesperado.');
  }
}
