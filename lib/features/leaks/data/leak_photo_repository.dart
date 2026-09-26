import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_community_database.dart';
import '../../../core/network/network_providers.dart';
import '../domain/leak_community_errors.dart';
import '../domain/leak_photo.dart';

/// TTL de las signed URLs que genera la RPC (900 s = 15 min).
const _kSignedUrlTtlSeconds = 900;

/// Repositorio de fotos de un reporte de fuga (Sprint 13).
///
/// Llama a la RPC `get_report_photos` (SECURITY DEFINER, autenticados) y
/// convierte la respuesta en [LeakPhoto] con URLs listas para usar.
/// El cliente nunca recibe `storage_path` crudo.
abstract class LeakPhotoRepository {
  /// Fotos del reporte [reportId], ordenadas por `sort_order`.
  /// Lanza [LeakReportNotFoundException] si el reporte no existe.
  /// Lanza [LeakCommunityForbiddenException] si el usuario está bloqueado.
  /// Devuelve lista vacía si el reporte no tiene fotos.
  Future<List<LeakPhoto>> getPhotos(String reportId);
}

class SupabaseLeakPhotoRepository implements LeakPhotoRepository {
  SupabaseLeakPhotoRepository(this._database);

  final GotaCommunityDatabase _database;

  @override
  Future<List<LeakPhoto>> getPhotos(String reportId) async {
    final Map<String, dynamic> data;
    try {
      data = await _database.rpcGetReportPhotos(reportId);
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

    switch (data['status_code']) {
      case 'OK':
        final raw = data['photos'];
        if (raw == null) return const [];
        final list = raw is List ? raw : const <dynamic>[];
        final fetchedAt = DateTime.now().toUtc();
        final expiresAt = fetchedAt.add(
          const Duration(seconds: _kSignedUrlTtlSeconds),
        );
        return list
            .whereType<Map>()
            .map((row) {
              final m = Map<String, dynamic>.from(row);
              return LeakPhoto(
                id: m['id'] as String? ?? '',
                sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
                url: m['url'] as String? ?? '',
                thumbnailUrl: m['thumbnail_url'] as String?,
                width: (m['width'] as num?)?.toInt(),
                height: (m['height'] as num?)?.toInt(),
                expiresAt: expiresAt,
              );
            })
            .where((p) => p.url.isNotEmpty)
            .toList();
      case 'NOT_FOUND':
        throw const LeakReportNotFoundException();
      case 'FORBIDDEN':
        throw const LeakCommunityForbiddenException(
          'Tu acceso está bloqueado.',
        );
      case 'RATE_LIMIT_EXCEEDED':
        throw const QueryException(
          'Demasiadas solicitudes de fotos. Espera un momento.',
        );
      default:
        throw const QueryException();
    }
  }
}

final leakPhotoRepositoryProvider = Provider<LeakPhotoRepository>(
  (ref) => SupabaseLeakPhotoRepository(
    ref.watch(gotaCommunityDatabaseProvider),
  ),
);
