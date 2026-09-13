import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_notifications_database.dart';
import '../../../core/network/network_providers.dart';
import '../domain/notification_errors.dart';
import '../domain/notification_page.dart';
import '../domain/notification_preferences.dart';
import '../domain/water_notification.dart';

/// Repositorio del ciclo de notificaciones (Sprint 06).
///
/// No decide reglas: las reglas viven en el backend (RPC
/// `save_notification_preferences`, `register_notification_token` y
/// `unregister_notification_token`). Aquí solo se llaman las consultas y RPC
/// protegidas y se traduce la respuesta real a resultados o errores con
/// mensaje para el usuario.
abstract class NotificationRepository {
  /// Preferencias del usuario actual; `null` si aún no tiene fila.
  Future<NotificationPreferences?> getPreferences();

  /// Crea o actualiza las preferencias del usuario.
  Future<NotificationPreferences> savePreferences({
    String? sectorId,
    required bool enabled,
  });

  /// Bandeja paginada (keyset sobre `created_at` desc).
  Future<NotificationInboxPage> fetchInbox({int limit, String? beforeIso});

  /// Marca una notificación como leída.
  Future<void> markRead(String id);

  /// Registra el token FCM del dispositivo actual.
  Future<void> registerToken(String token, String platform);

  /// Desactiva el token FCM del dispositivo actual.
  Future<void> unregisterToken(String token);

  /// Suscripción realtime a cambios en la bandeja del usuario.
  Stream<String> watchNotifications(String userId);
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._database);

  final GotaNotificationsDatabase _database;

  @override
  Future<NotificationPreferences?> getPreferences() async {
    try {
      final row = await _database.fetchPreferences();
      if (row == null) return null;
      return NotificationPreferences.fromJson(row);
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on supabase.PostgrestException {
      throw const QueryException();
    } on supabase.AuthException {
      throw const QueryException();
    }
  }

  @override
  Future<NotificationPreferences> savePreferences({
    String? sectorId,
    required bool enabled,
  }) async {
    final data = await _rpc(
      () => _database.rpcSavePreferences(sectorId: sectorId, enabled: enabled),
    );

    switch (data['status_code']) {
      case 'OK':
        final row = data['preferences'];
        if (row is Map) {
          return NotificationPreferences.fromJson(
            Map<String, dynamic>.from(row),
          );
        }
        throw const QueryException(
          'No pudimos guardar tus preferencias. Intenta de nuevo.',
        );
      case 'NOT_FOUND':
      case 'VALIDATION_ERROR':
        throw NotificationValidationException(
          data['message'] as String? ?? 'Revisa los datos e intenta de nuevo.',
        );
      case 'FORBIDDEN':
        throw NotificationForbiddenException(
          data['message'] as String? ?? 'Tu acceso está bloqueado.',
        );
      case 'UNAUTHORIZED':
        throw const AuthException();
      default:
        throw const QueryException(
          'No pudimos guardar tus preferencias. Intenta de nuevo.',
        );
    }
  }

  @override
  Future<NotificationInboxPage> fetchInbox({int limit = 20, String? beforeIso}) async {
    try {
      final rows = await _database.fetchNotifications(
        limit: limit,
        beforeCreatedAtIso: beforeIso,
      );
      final items = rows.map(WaterNotification.fromJson).toList();
      final String? nextBeforeIso =
          items.length == limit && items.isNotEmpty
          ? items.last.createdAt.toUtc().toIso8601String()
          : null;
      return NotificationInboxPage(items: items, nextBeforeIso: nextBeforeIso);
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on supabase.PostgrestException {
      throw const QueryException();
    } on supabase.AuthException {
      throw const QueryException();
    }
  }

  @override
  Future<void> markRead(String id) async {
    try {
      await _database.markNotificationRead(id, DateTime.now());
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on supabase.PostgrestException {
      throw const QueryException();
    } on supabase.AuthException {
      throw const QueryException();
    }
  }

  @override
  Future<void> registerToken(String token, String platform) async {
    final data = await _rpc(
      () => _database.rpcRegisterToken(token: token, platform: platform),
    );
    _mapTokenRpcResult(data, 'No pudimos registrar el dispositivo.');
  }

  @override
  Future<void> unregisterToken(String token) async {
    final data = await _rpc(() => _database.rpcUnregisterToken(token));
    _mapTokenRpcResult(data, 'No pudimos desactivar el dispositivo.');
  }

  @override
  Stream<String> watchNotifications(String userId) =>
      _database.watchNotifications(userId);

  void _mapTokenRpcResult(Map<String, dynamic> data, String fallbackMessage) {
    switch (data['status_code']) {
      case 'OK':
        return;
      case 'NOT_FOUND':
      case 'VALIDATION_ERROR':
        throw NotificationValidationException(
          data['message'] as String? ?? 'Revisa los datos e intenta de nuevo.',
        );
      case 'FORBIDDEN':
        throw NotificationForbiddenException(
          data['message'] as String? ?? 'Tu acceso está bloqueado.',
        );
      case 'UNAUTHORIZED':
        throw const AuthException();
      default:
        throw QueryException(fallbackMessage);
    }
  }

  Future<Map<String, dynamic>> _rpc(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    try {
      return await action();
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on supabase.PostgrestException {
      throw const QueryException(
        'No pudimos completar la acción. Intenta de nuevo.',
      );
    } on supabase.AuthException {
      throw const QueryException(
        'No pudimos completar la acción. Cierra y abre la app de nuevo.',
      );
    }
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => SupabaseNotificationRepository(
    ref.watch(gotaNotificationsDatabaseProvider),
  ),
);
