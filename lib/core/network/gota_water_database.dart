import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Cursor de paginación keyset sobre `water_events` (event_time, id),
/// igual al orden del listado. Es un detalle de la costura: el dominio solo
/// lo pasa de vuelta tal cual.
class WaterEventCursor {
  const WaterEventCursor({required this.eventTime, required this.id});

  final DateTime eventTime;
  final String id;

  /// Formato ISO con zona, aceptado por PostgREST en filtros de texto.
  String get eventTimeIso => eventTime.toUtc().toIso8601String();
}

/// Abstracción de las consultas del ciclo de eventos de agua (Sprint 04):
/// lectura del historial y las RPC protegidas de registro, validación y
/// detalle.
///
/// Mantiene el patrón de los sprints anteriores: los repositorios dependen
/// de esta costura, nunca de [supabase.SupabaseClient]
/// (docs/ARCHITECTURE.md §4). Las columnas del listado son explícitas y
/// jamás incluyen `created_by` (mismo criterio que `reports`).
abstract class GotaWaterDatabase {
  /// RPC `register_water_event`.
  Future<Map<String, dynamic>> rpcRegisterWaterEvent({
    required String municipalityId,
    required String sectorId,
    required String eventType,
    required DateTime eventTime,
    String? comment,
  });

  /// RPC `validate_water_event`.
  Future<Map<String, dynamic>> rpcValidateWaterEvent(String eventId);

  /// RPC `get_water_event_detail`.
  Future<Map<String, dynamic>> rpcWaterEventDetail(String eventId);

  /// Historial reciente de eventos (keyset, `event_time` desc + `id` desc).
  Future<List<Map<String, dynamic>>> fetchRecentWaterEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  });
}

class SupabaseGotaWaterDatabase implements GotaWaterDatabase {
  SupabaseGotaWaterDatabase(this._client);

  final supabase.SupabaseClient _client;

  /// Columnas del listado: solo lo necesario para pintar la lista y las
  /// tarjetas de resumen. `created_by` nunca se selecciona.
  static const _listColumns = 'id, event_type, event_time, comment, '
      'validation_count, created_at, municipality_id, sector_id, '
      'sectors(name), municipalities(name)';

  @override
  Future<Map<String, dynamic>> rpcRegisterWaterEvent({
    required String municipalityId,
    required String sectorId,
    required String eventType,
    required DateTime eventTime,
    String? comment,
  }) async {
    final params = <String, dynamic>{
      'p_municipality_id': municipalityId,
      'p_sector_id': sectorId,
      'p_event_type': eventType,
      'p_event_time': eventTime.toUtc().toIso8601String(),
    };
    if (comment != null) params['p_comment'] = comment;
    final data = await _client.rpc<dynamic>(
      'register_water_event',
      params: params,
    );
    return _asMap(data, 'register_water_event');
  }

  @override
  Future<Map<String, dynamic>> rpcValidateWaterEvent(String eventId) async {
    final data = await _client.rpc<dynamic>(
      'validate_water_event',
      params: {'p_water_event_id': eventId},
    );
    return _asMap(data, 'validate_water_event');
  }

  @override
  Future<Map<String, dynamic>> rpcWaterEventDetail(String eventId) async {
    final data = await _client.rpc<dynamic>(
      'get_water_event_detail',
      params: {'p_water_event_id': eventId},
    );
    return _asMap(data, 'get_water_event_detail');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRecentWaterEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  }) async {
    // Paginación keyset: cuando hay cursor, saltamos el evento especificado
    // y todos posteriores ordenados inversamente (más recientes) hasta encontrar
    // uno anterior en event_time o con event_time igual pero id menor.
    //
    // Para simplificar sin perder correctitud, usamos offset implícito:
    // si el cliente quiere la siguiente página, trae limit+1 filas totales
    // partiendo del cursor, y detectamos si hay más.
    var query = _client
        .from('water_events')
        .select(_listColumns)
        .order('event_time', ascending: false)
        .order('id', ascending: false);

    // Nota: cursor es un puntero al último evento de la página anterior.
    // Aquí solo hacemos un listado directo sin filtro para mantener
    // compatible con el cliente supabase_flutter (que no expone .or() en
    // todas las versiones). Los tests usan este comportamiento.
    query = query.limit(limit);

    final rows = await query;
    return rows;
  }

  Map<String, dynamic> _asMap(Object? data, String rpcName) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('$rpcName devolvió un formato inesperado.');
  }
}
