import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_auth.dart';
import '../../../core/network/gota_database.dart';
import '../../../core/network/gota_storage.dart';
import '../../../core/network/network_providers.dart';
import '../domain/create_leak_report_outcome.dart';
import '../domain/leak_errors.dart';
import '../domain/leak_report_draft.dart';
import '../domain/location_source.dart';

/// Repositorio de reportes de fuga: sube las fotos a la carpeta del propio
/// usuario en el bucket privado y llama a la RPC protegida
/// `create_leak_report`.
///
/// La UI nunca consulta Supabase directamente (docs/ARCHITECTURE.md §4).
abstract class LeakReportRepository {
  /// Sube las fotos (1..3) y crea el reporte.
  ///
  /// [ignoreDuplicate] es la confirmación explícita del usuario tras
  /// revisar un candidato ("es otra fuga", docs/REQUIREMENTS.md REQ-025).
  ///
  /// Devuelve [ReportCreated] o [PossibleDuplicateFound]; lanza
  /// [LeakFlowException]/[AppException] con mensaje visible.
  Future<CreateLeakReportOutcome> createReport(
    LeakReportDraft draft, {
    bool ignoreDuplicate = false,
  });
}

class SupabaseLeakReportRepository implements LeakReportRepository {
  SupabaseLeakReportRepository(this._database, this._storage, this._auth);

  final GotaDatabase _database;
  final GotaStorage _storage;
  final GotaAuth _auth;

  static const bucket = 'report-photos';

  /// Carpeta raíz de las fotos dentro del bucket.
  static const _folder = 'report_photos';

  @override
  Future<CreateLeakReportOutcome> createReport(
    LeakReportDraft draft, {
    bool ignoreDuplicate = false,
  }) async {
    final location = draft.location;
    if (location == null) {
      throw const LeakFlowException('Falta la ubicación del reporte.');
    }

    final userId = _auth.currentSession()?.user.id;
    if (userId == null) {
      throw const LeakFlowException(
        'Tu sesión no está activa. Cierra y abre la app de nuevo.',
      );
    }

    // Ruta propia del usuario: es lo que exige la política RLS del bucket
    // (report_photos/{auth.uid()}/...) y lo que valida la RPC.
    final uploadKey = 'u-${DateTime.now().millisecondsSinceEpoch}';
    final uploadedPaths = <String>[];
    final photoPayload = <Map<String, dynamic>>[];

    // ---------- 1. Subida de fotos ----------
    try {
      for (final (index, photo) in draft.photos.indexed) {
        final path = '$_folder/$userId/$uploadKey/${photo.id}.jpg';
        final bytes = await File(photo.compressedPath).readAsBytes();
        await _storage.upload(
          bucket: bucket,
          path: path,
          bytes: bytes,
          contentType: photo.mimeType,
        );
        uploadedPaths.add(path);
        photoPayload.add({
          'storage_path': path,
          'mime_type': photo.mimeType,
          'size_bytes': photo.sizeBytes,
          'width': photo.width,
          'height': photo.height,
          'sort_order': index + 1,
        });
      }
    } on AppException catch (error) {
      await _failAndCleanup(uploadedPaths, error);
    } on LeakFlowException catch (error) {
      await _failAndCleanup(uploadedPaths, error);
    } on supabase.StorageException {
      await _failAndCleanup(uploadedPaths, const PhotoUploadException());
    } on FileSystemException {
      await _failAndCleanup(
        uploadedPaths,
        const PhotoUploadException(
          'No pudimos leer una de tus fotos. Vuelve a agregarla.',
        ),
      );
    } on TimeoutException {
      await _failAndCleanup(uploadedPaths, const NetworkException());
    } on SocketException {
      await _failAndCleanup(uploadedPaths, const NetworkException());
    } on http.ClientException {
      await _failAndCleanup(uploadedPaths, const NetworkException());
    }

    // ---------- 2. RPC protegida ----------
    Map<String, dynamic> data;
    try {
      data = await _database.rpcCreateLeakReport({
        'p_municipality_id': draft.municipalityId,
        'p_sector_id': draft.sectorId,
        'p_latitude': location.latitude,
        'p_longitude': location.longitude,
        'p_location_source': location.source.wireName,
        'p_description': draft.description,
        'p_photos': photoPayload,
        'p_ignore_duplicate': ignoreDuplicate,
      });
    } on TimeoutException {
      await _failAndCleanup(uploadedPaths, const NetworkException());
    } on SocketException {
      await _failAndCleanup(uploadedPaths, const NetworkException());
    } on http.ClientException {
      await _failAndCleanup(uploadedPaths, const NetworkException());
    } on supabase.PostgrestException {
      await _failAndCleanup(
        uploadedPaths,
        const QueryException(
          'No pudimos registrar tu reporte. Verifica tus datos e intenta '
          'de nuevo.',
        ),
      );
    }

    // ---------- 3. Interpretación de la respuesta ----------
    final CreateLeakReportOutcome outcome;
    try {
      outcome = _parseOutcome(data);
    } on LeakFlowException catch (error) {
      // Rechazo del backend (VALIDATION_ERROR, STORAGE_ERROR, FORBIDDEN…):
      // ninguna foto quedó referenciada, así que se limpian.
      await _failAndCleanup(uploadedPaths, error);
    }

    // El backend no persistió ninguna referencia a estas fotos: se
    // eliminan para no dejar binarios huérfanos en Storage.
    if (outcome is PossibleDuplicateFound) {
      await _cleanupUploaded(uploadedPaths);
    }

    return outcome;
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
      case 'FORBIDDEN':
        throw ReportCreationException(
          data['message'] as String? ??
              'Tu cuenta no puede publicar reportes ahora mismo.',
        );
      case 'RATE_LIMIT_EXCEEDED':
        throw ReportRateLimitException(_rateLimitMessage(data));
      default:
        // VALIDATION_ERROR / INVALID_LOCATION / INVALID_SECTOR /
        // STORAGE_ERROR: el mensaje del backend ya viene en español y es
        // apto para mostrar (migración 00010).
        throw ReportCreationException(
          data['message'] as String? ??
              'El backend rechazó el reporte. Revisa tus datos e intenta '
                  'de nuevo.',
        );
    }
  }

  /// Limpia los binarios temporales y relanza el error original.
  ///
  /// Reintenta el borrado una vez y **nunca** lo oculta: si no puede
  /// limpiar, el error de limpieza se añade al mensaje para que el usuario
  /// sepa que quedaron archivos temporales.
  Future<Never> _failAndCleanup(List<String> paths, Object primary) async {
    try {
      await _cleanupUploaded(paths);
    } on PhotoCleanupException {
      throw PhotoCleanupException(
        '${_userMessageOf(primary)} Además, quedaron fotos temporales sin '
        'borrar; se limpiarán en el próximo intento.',
      );
    }
    throw primary;
  }

  /// Limpia los binarios temporales ya subidos.
  Future<void> _cleanupUploaded(List<String> paths) async {
    if (paths.isEmpty) return;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _storage.remove(bucket: bucket, paths: paths);
        return;
      } on Exception {
        // Se reintenta una vez; si vuelve a fallar, se reporta abajo.
      }
    }
    throw PhotoCleanupException(
      'No pudimos borrar las fotos temporales de este intento. '
      'Intenta de nuevo.',
    );
  }

  /// Mensaje de límite de frecuencia (`RATE_LIMIT_EXCEEDED`): usa el mensaje
  /// del backend y, si viene `reset_at`, añade la hora local de reintento.
  String _rateLimitMessage(Map<String, dynamic> data) {
    final base =
        data['message'] as String? ??
        'Has alcanzado el límite de reportes por hora.';
    final rawResetAt = data['reset_at'];
    final resetAt = rawResetAt is String ? DateTime.tryParse(rawResetAt) : null;
    if (resetAt == null) return base;
    final local = resetAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$base Intenta de nuevo después de las $hh:$mm.';
  }

  String _userMessageOf(Object error) {
    if (error is LeakFlowException) return error.userMessage;
    if (error is AppException) return error.userMessage;
    return 'No pudimos completar la operación.';
  }
}

final leakReportRepositoryProvider = Provider<LeakReportRepository>(
  (ref) => SupabaseLeakReportRepository(
    ref.watch(gotaDatabaseProvider),
    ref.watch(gotaStorageProvider),
    ref.watch(gotaAuthProvider),
  ),
);
