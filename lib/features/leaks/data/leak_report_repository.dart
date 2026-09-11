import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/network_providers.dart';
import '../domain/create_leak_report_outcome.dart';
import '../domain/leak_errors.dart';
import '../domain/leak_report_draft.dart';
import '../domain/location_source.dart';

/// Repositorio de reportes de fuga: sube fotos al bucket privado y
/// llama a la RPC protegida `create_leak_report`.
///
/// La UI nunca consulta Supabase directamente (docs/ARCHITECTURE.md §4).
abstract class LeakReportRepository {
  /// Sube las fotos y crea el reporte.
  ///
  /// Devuelve [ReportCreated] o [PossibleDuplicateFound]; lanza
  /// [AppException]/[LeakFlowException] con mensaje visible.
  Future<CreateLeakReportOutcome> createReport(LeakReportDraft draft);
}

class SupabaseLeakReportRepository implements LeakReportRepository {
  SupabaseLeakReportRepository(this._client);

  final supabase.SupabaseClient _client;

  static const _bucket = 'report-photos';

  @override
  Future<CreateLeakReportOutcome> createReport(LeakReportDraft draft) async {
    final location = draft.location;
    if (location == null) {
      throw const LeakFlowException('Falta la ubicación del reporte.');
    }

    // Clave de agrupación para el path de fotos (sin colisiones entre
    // envíos del mismo usuario).
    final reportKey =
        'u-${_client.auth.currentUser?.id ?? 'anon'}-'
        '${DateTime.now().millisecondsSinceEpoch}';

    // 1. Subir fotos (1..3) antes de crear el reporte: el backend solo
    // persiste referencias (docs/API_SPEC.md §6).
    final photoPayload = <Map<String, dynamic>>[];
    try {
      for (final (index, photo) in draft.photos.indexed) {
        final storagePath = await _uploadOne(photo, reportKey);
        photoPayload.add({
          'storage_path': storagePath,
          'mime_type': photo.mimeType,
          'size_bytes': photo.sizeBytes,
          'width': photo.width,
          'height': photo.height,
          'sort_order': index + 1,
        });
      }
    } on AppException {
      await _cleanupUploaded(reportKey);
      rethrow;
    }

    // 2. RPC protegida: valida sector/municipio/ubicación, busca
    // duplicados 50 m/48 h y crea ACTIVE solo si no hay candidatos.
    try {
      final data = await _client.rpc<dynamic>(
        'create_leak_report',
        params: {
          'p_municipality_id': draft.municipalityId,
          'p_sector_id': draft.sectorId,
          'p_latitude': location.latitude,
          'p_longitude': location.longitude,
          'p_location_source': location.source.wireName,
          'p_description': draft.description,
          'p_photos': photoPayload,
        },
      );
      return _parseOutcome(
        data is Map ? Map<String, dynamic>.from(data) : const {},
      );
    } on AppException {
      rethrow;
    } on supabase.PostgrestException {
      await _cleanupUploaded(reportKey);
      throw const QueryException(
        'No pudimos registrar tu reporte. Verifica tus datos e intenta '
        'de nuevo.',
      );
    } on SocketException {
      await _cleanupUploaded(reportKey);
      throw const NetworkException();
    } on http.ClientException {
      await _cleanupUploaded(reportKey);
      throw const NetworkException();
    }
  }

  Future<String> _uploadOne(PreparedPhoto photo, String reportKey) async {
    try {
      final bytes = await File(photo.compressedPath).readAsBytes();
      final path = 'report_photos/$reportKey/${photo.id}.jpg';
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const supabase.FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      return path;
    } on supabase.StorageException {
      throw const PhotoUploadException();
    }
  }

  CreateLeakReportOutcome _parseOutcome(Map<String, dynamic> data) {
    switch (data['status_code']) {
      case 'CREATED':
        return ReportCreated(reportId: data['report_id'] as String? ?? '');
      case 'POSSIBLE_DUPLICATE':
        final raw = data['candidates'];
        final candidates = (raw is List ? raw : const <dynamic>[])
            .map(
              (c) => PossibleDuplicateCandidate.fromJson(
                Map<String, dynamic>.from(c as Map),
              ),
            )
            .toList();
        return PossibleDuplicateFound(candidates: candidates);
      case 'UNAUTHORIZED':
        return const LeakReportUnauthorized();
      default:
        throw const QueryException(
          'El backend rechazó la operación. Verifica tus datos e intenta '
          'de nuevo.',
        );
    }
  }

  /// Limpieza best-effort de binarios ya subidos cuando el reporte no se
  /// crea: evita huérfanos en Storage.
  Future<void> _cleanupUploaded(String reportKey) async {
    try {
      final prefix = 'report_photos/$reportKey';
      final listing =
          await _client.storage.from(_bucket).list(path: prefix);
      if (listing.isEmpty) return;
      await _client.storage
          .from(_bucket)
          .remove(listing.map((f) => '$prefix/${f.name}').toList());
    } on Exception {
      // El huérfano se detecta en auditoría; no bloqueamos al usuario.
    }
  }
}

final leakReportRepositoryProvider = Provider<LeakReportRepository>(
  (ref) => SupabaseLeakReportRepository(ref.watch(supabaseClientProvider)),
);
