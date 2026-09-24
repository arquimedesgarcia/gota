import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_water_database.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/utils/rate_limit.dart';
import '../../../core/utils/rpc_helper.dart';
import '../domain/water_errors.dart';
import '../domain/water_event.dart';
import '../domain/water_event_detail.dart';
import '../domain/water_event_type.dart';

/// Repositorio del ciclo de eventos de agua (Sprint 04).
///
/// No decide reglas: las reglas viven en el backend (RPC `register_water_event`,
/// `validate_water_event` y `get_water_event_detail`). Aquí solo se llama a
/// las RPC protegidas y se traduce la respuesta real a resultados o errores
/// con mensaje para el usuario.
abstract class WaterEventRepository {
  /// Registra un evento de agua y devuelve el resumen creado.
  Future<WaterEventSummary> register({
    required String municipalityId,
    required String sectorId,
    required WaterEventType type,
    required DateTime eventTime,
    String? comment,
  });

  /// Valida un evento de otro usuario; devuelve el contador confirmado
  /// por el backend.
  Future<int> validate(String eventId);

  /// Detalle de un evento + estado del usuario actual.
  Future<WaterEventDetail> detail(String eventId);

  /// Historial reciente paginado (keyset).
  Future<WaterEventsPage> recentEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  });

  /// Último evento del ámbito (`sectorId == null` = todo el piloto), o
  /// `null` si no hay eventos. Para el "Estado del agua" de Home.
  Future<WaterEventSummary?> latestEvent({String? sectorId});
}

class SupabaseWaterEventRepository implements WaterEventRepository {
  SupabaseWaterEventRepository(this._database);

  final GotaWaterDatabase _database;

  @override
  Future<WaterEventSummary> register({
    required String municipalityId,
    required String sectorId,
    required WaterEventType type,
    required DateTime eventTime,
    String? comment,
  }) async {
    final trimmed = comment?.trim();
    final normalizedComment = trimmed == null || trimmed.isEmpty
        ? null
        : trimmed;

    final data = await callRpc(
      () => _database.rpcRegisterWaterEvent(
        municipalityId: municipalityId,
        sectorId: sectorId,
        eventType: type.wireName,
        eventTime: eventTime,
        comment: normalizedComment,
      ),
    );

    switch (data['status_code']) {
      case 'CREATED':
        return WaterEventSummary(
          id: data['event_id'] as String? ?? '',
          type: type,
          eventTime: _parseDate(data['event_time']) ?? eventTime,
          comment: normalizedComment,
          validationCount: 0,
          createdAt: _parseDate(data['created_at']) ?? DateTime.now(),
          municipalityId: municipalityId,
          sectorId: sectorId,
        );
      case 'VALIDATION_ERROR':
      case 'INVALID_SECTOR':
      case 'NOT_FOUND':
        throw WaterValidationException(
          data['message'] as String? ??
              'Revisa los datos del evento e intenta de nuevo.',
        );
      case 'FORBIDDEN':
        throw WaterForbiddenException(
          data['message'] as String? ?? 'Tu acceso está bloqueado.',
        );
      case 'UNAUTHORIZED':
        throw const AuthException();
      case 'RATE_LIMIT_EXCEEDED':
        throw WaterRateLimitException(
          formatRateLimitMessage(
            data,
            defaultMessage: 'Has alcanzado el límite de eventos de agua por hora.',
          ),
        );
      default:
        throw const QueryException('No pudimos registrar el evento.');
    }
  }

  @override
  Future<int> validate(String eventId) async {
    final data = await callRpc(() => _database.rpcValidateWaterEvent(eventId));

    switch (data['status_code']) {
      case 'VALIDATED':
        return (data['validation_count'] as num?)?.toInt() ?? 0;
      case 'DUPLICATE_ACTION':
        throw DuplicateValidationException(
          data['message'] as String? ?? 'Ya validaste este evento.',
        );
      case 'FORBIDDEN':
        throw WaterForbiddenException(
          data['message'] as String? ?? 'No puedes validar tu propio evento.',
        );
      case 'NOT_FOUND':
        throw WaterNotFoundException(
          data['message'] as String? ?? 'No encontramos este evento.',
        );
      case 'UNAUTHORIZED':
        throw const AuthException();
      case 'RATE_LIMIT_EXCEEDED':
        throw WaterRateLimitException(
          formatRateLimitMessage(
            data,
            defaultMessage: 'Has alcanzado el límite de eventos de agua por hora.',
          ),
        );
      default:
        throw const QueryException('No pudimos completar la acción.');
    }
  }

  @override
  Future<WaterEventDetail> detail(String eventId) async {
    final data = await callRpc(() => _database.rpcWaterEventDetail(eventId));

    switch (data['status_code']) {
      case 'OK':
        return WaterEventDetail.fromJson(data);
      case 'NOT_FOUND':
        throw WaterNotFoundException(
          data['message'] as String? ?? 'No encontramos este evento.',
        );
      case 'UNAUTHORIZED':
        throw const AuthException();
      default:
        throw const QueryException('No pudimos cargar este evento.');
    }
  }

  @override
  Future<WaterEventsPage> recentEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  }) async {
    try {
      final rows = await _database.fetchRecentWaterEvents(
        limit: limit,
        cursor: cursor,
      );
      final events = rows.map(WaterEventSummary.fromJson).toList();
      // Cursor para la siguiente página: derivado del último evento solo si
      // la página vino llena; si vino incompleta no hay más páginas.
      final WaterEventCursor? nextCursor =
          events.length == limit && events.isNotEmpty
          ? WaterEventCursor(
              eventTime: events.last.eventTime,
              id: events.last.id,
            )
          : null;
      return WaterEventsPage(events: events, nextCursor: nextCursor);
    } on TimeoutException {
      throw const NetworkException();
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
  Future<WaterEventSummary?> latestEvent({String? sectorId}) async {
    try {
      final rows = await _database.fetchLatestWaterEvent(sectorId: sectorId);
      if (rows.isEmpty) return null;
      return WaterEventSummary.fromJson(rows.first);
    } on TimeoutException {
      throw const NetworkException();
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

}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

final waterEventRepositoryProvider = Provider<WaterEventRepository>(
  (ref) => SupabaseWaterEventRepository(ref.watch(gotaWaterDatabaseProvider)),
);
