import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Abstracción de las consultas del ciclo de notificaciones (Sprint 06):
/// preferencias del usuario, bandeja, token de push y suscripción realtime.
///
/// Mantiene el patrón de los sprints anteriores: los repositorios dependen
/// de esta costura, nunca de [supabase.SupabaseClient]
/// (docs/ARCHITECTURE.md §4).
abstract class GotaNotificationsDatabase {
  /// Preferencias del usuario actual (0..1 filas).
  Future<Map<String, dynamic>?> fetchPreferences();

  /// RPC `save_notification_preferences`.
  Future<Map<String, dynamic>> rpcSavePreferences({
    required String? sectorId,
    required bool enabled,
  });

  /// Bandeja paginada de notificaciones (keyset sobre `created_at` desc).
  Future<List<Map<String, dynamic>>> fetchNotifications({
    int limit = 20,
    String? beforeCreatedAtIso,
  });

  /// Marca una notificación como leída (solo `read_at`, según el grant RLS).
  Future<void> markNotificationRead(String notificationId, DateTime readAt);

  /// RPC `register_notification_token`.
  Future<Map<String, dynamic>> rpcRegisterToken({
    required String token,
    required String platform,
  });

  /// RPC `unregister_notification_token`.
  Future<Map<String, dynamic>> rpcUnregisterToken(String token);

  /// Emite un evento cada vez que cambia la bandeja del usuario (realtime).
  Stream<String> watchNotifications(String userId);
}

class SupabaseGotaNotificationsDatabase implements GotaNotificationsDatabase {
  SupabaseGotaNotificationsDatabase(this._client);

  final supabase.SupabaseClient _client;

  static const _listColumns =
      'id, type, title, body, created_at, read_at, water_event_id, '
      'water_events(event_time, sectors(name), municipalities(name))';

  @override
  Future<Map<String, dynamic>?> fetchPreferences() async {
    final data = await _client
        .from('notification_preferences')
        .select()
        .limit(1);
    if (data.isEmpty) return null;
    return Map<String, dynamic>.from(data.first);
  }

  @override
  Future<Map<String, dynamic>> rpcSavePreferences({
    required String? sectorId,
    required bool enabled,
  }) async {
    final data = await _client.rpc<dynamic>(
      'save_notification_preferences',
      params: {
        'p_preferred_sector_id': sectorId,
        'p_water_notifications_enabled': enabled,
      },
    );
    final result = _asMap(data, 'save_notification_preferences');
    if (result['status_code'] == 'OK') {
      final prefs = await fetchPreferences();
      if (prefs != null) {
        result['preferences'] = prefs;
      }
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNotifications({
    int limit = 20,
    String? beforeCreatedAtIso,
  }) async {
    var query = _client.from('notifications').select(_listColumns);
    if (beforeCreatedAtIso != null) {
      query = query.lt('created_at', beforeCreatedAtIso);
    }
    final rows = await query
        .order('created_at', ascending: false)
        .limit(limit);
    return rows;
  }

  @override
  Future<void> markNotificationRead(String notificationId, DateTime readAt) {
    return _client
        .from('notifications')
        .update({'read_at': readAt.toUtc().toIso8601String()})
        .eq('id', notificationId);
  }

  @override
  Future<Map<String, dynamic>> rpcRegisterToken({
    required String token,
    required String platform,
  }) async {
    final data = await _client.rpc<dynamic>(
      'register_notification_token',
      params: {'p_token': token, 'p_platform': platform},
    );
    return _asMap(data, 'register_notification_token');
  }

  @override
  Future<Map<String, dynamic>> rpcUnregisterToken(String token) async {
    final data = await _client.rpc<dynamic>(
      'unregister_notification_token',
      params: {'p_token': token},
    );
    return _asMap(data, 'unregister_notification_token');
  }

  @override
  Stream<String> watchNotifications(String userId) {
    final controller = StreamController<String>();
    final channel = _client
        .channel('notifications-$userId')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: supabase.PostgresChangeFilter(
            type: supabase.PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => controller.add('change'),
        )
        .subscribe();
    controller.onCancel = () => _client.removeChannel(channel);
    return controller.stream;
  }

  Map<String, dynamic> _asMap(Object? data, String rpcName) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('$rpcName devolvió un formato inesperado.');
  }
}
