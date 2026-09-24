import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_community_database.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/utils/rate_limit.dart';
import '../../../core/utils/rpc_helper.dart';
import '../domain/community_activity.dart';
import '../domain/leak_community.dart';
import '../domain/leak_community_errors.dart';

/// Repositorio de las acciones comunitarias sobre una fuga (Sprint 03).
///
/// No decide reglas: las reglas viven en el backend. Aquí solo se llama a
/// las RPC protegidas y se traduce la respuesta real a resultados o errores
/// con mensaje para el usuario.
abstract class LeakCommunityRepository {
  /// Fugas recientes para la lista de Inicio (ACTIVE primero).
  Future<List<LeakSummary>> recentReports({int limit = 20});

  /// Detalle de una fuga + estado del usuario actual.
  Future<LeakDetail> reportDetail(String reportId);

  /// Valida una fuga activa de otro usuario (REQ-040..REQ-044).
  Future<CommunityActionResult> validateLeak(String reportId);

  /// Confirma que una fuga parece resuelta (REQ-050..REQ-053).
  Future<CommunityActionResult> confirmResolution(String reportId);

  /// Fugas geolocalizadas con filtros para Mapa y Lista (Sprint 05: Map).
  Future<List<LeakSummary>> mapReports({
    String? status,
    String? sectorId,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    String orderBy = 'recent',
    int limit = 100,
  });

  /// Última actividad comunitaria global sobre fallas (tarjeta de Inicio).
  /// `null` si no hay actividad.
  Future<CommunityActivity?> latestActivity();
}

class SupabaseLeakCommunityRepository implements LeakCommunityRepository {
  SupabaseLeakCommunityRepository(this._database);

  final GotaCommunityDatabase _database;

  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async {
    try {
      final rows = await _database.fetchRecentLeakReports(limit: limit);
      return rows.map(LeakSummary.fromJson).toList();
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
  Future<List<LeakSummary>> mapReports({
    String? status,
    String? sectorId,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    String orderBy = 'recent',
    int limit = 100,
  }) async {
    try {
      final rows = await _database.rpcGetMapReports(
        status: status,
        sectorId: sectorId,
        minLat: minLat,
        minLng: minLng,
        maxLat: maxLat,
        maxLng: maxLng,
        orderBy: orderBy,
        limit: limit,
      );
      return rows.map(LeakSummary.fromJson).toList();
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
  Future<CommunityActivity?> latestActivity() async {
    try {
      final row = await _database.fetchLatestCommunityActivity();
      if (row == null) return null;
      return CommunityActivity.fromJson(row);
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
  Future<LeakDetail> reportDetail(String reportId) async {
    final data = await callRpc(() => _database.rpcLeakReportDetail(reportId));

    switch (data['status_code']) {
      case 'OK':
        return LeakDetail.fromJson(data);
      case 'NOT_FOUND':
        throw const LeakReportNotFoundException();
      case 'UNAUTHORIZED':
        throw const LeakCommunityUnauthorizedException();
      default:
        throw const QueryException();
    }
  }

  @override
  Future<CommunityActionResult> validateLeak(String reportId) async {
    final data = await callRpc(() => _database.rpcValidateLeak(reportId));
    return _parseAction(data, duplicateFallback: 'Ya validaste este reporte.');
  }

  @override
  Future<CommunityActionResult> confirmResolution(String reportId) async {
    final data = await callRpc(() => _database.rpcConfirmLeakResolution(reportId));
    return _parseAction(
      data,
      duplicateFallback: 'Ya confirmaste la resolución de esta fuga.',
    );
  }

  /// Traduce `status_code` del backend a resultado o error de dominio.
  ///
  /// `DUPLICATE_ACTION` es un resultado determinista del backend (no un
  /// fallo): el contador no cambió y la UI debe avisarlo con claridad.
  CommunityActionResult _parseAction(
    Map<String, dynamic> data, {
    required String duplicateFallback,
  }) {
    switch (data['status_code']) {
      case 'VALIDATED':
      case 'CONFIRMED':
      case 'RESOLVED':
        return CommunityActionResult.fromJson(data);
      case 'DUPLICATE_ACTION':
        throw DuplicateCommunityActionException(
          data['message'] as String? ?? duplicateFallback,
        );
      case 'REPORT_ALREADY_RESOLVED':
        throw LeakReportResolvedException(
          data['message'] as String? ??
              'Esta fuga ya fue marcada como resuelta por la comunidad.',
        );
      case 'NOT_FOUND':
        throw LeakReportNotFoundException(
          data['message'] as String? ?? 'No encontramos esta fuga.',
        );
      case 'FORBIDDEN':
        throw LeakCommunityForbiddenException(
          data['message'] as String? ?? 'No puedes realizar esta acción.',
        );
      case 'UNAUTHORIZED':
        throw const LeakCommunityUnauthorizedException();
      case 'RATE_LIMIT_EXCEEDED':
        throw LeakCommunityRateLimitException(
          formatRateLimitMessage(
            data,
            defaultMessage: 'Has alcanzado el límite de acciones por hora.',
          ),
        );
      default:
        throw const QueryException(
          'No pudimos completar la acción. Intenta de nuevo.',
        );
    }
  }

}

final leakCommunityRepositoryProvider = Provider<LeakCommunityRepository>(
  (ref) =>
      SupabaseLeakCommunityRepository(ref.watch(gotaCommunityDatabaseProvider)),
);
