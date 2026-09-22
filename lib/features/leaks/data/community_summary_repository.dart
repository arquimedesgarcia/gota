import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_community_database.dart';
import '../../../core/network/network_providers.dart';
import '../domain/community_summary.dart';

/// Repositorio del resumen diario "Hoy en tu comunidad" (S10-C).
///
/// No decide reglas: calcula la ventana de hoy en Caracas, pide los dos
/// conteos al backend y los mapea a [CommunitySummary]. Solo agregados,
/// sin identidades ni `created_by` (privacidad REQ-100).
abstract class CommunitySummaryRepository {
  /// Resumen de hoy en el ámbito dado (`sectorId == null` = cobertura
  /// global del piloto). [nowUtc] permite fijar el reloj en pruebas.
  /// [validatedThreshold] es el umbral comunitario de "validada".
  Future<CommunitySummary> todaySummary({
    String? sectorId,
    DateTime? nowUtc,
    int validatedThreshold = 3,
  });
}

class SupabaseCommunitySummaryRepository
    implements CommunitySummaryRepository {
  SupabaseCommunitySummaryRepository(this._database);

  final GotaCommunityDatabase _database;

  @override
  Future<CommunitySummary> todaySummary({
    String? sectorId,
    DateTime? nowUtc,
    int validatedThreshold = 3,
  }) async {
    final bounds = caracasDayBounds(nowUtc ?? DateTime.now().toUtc());
    final startIso = bounds.startUtc.toIso8601String();
    final endIso = bounds.endUtc.toIso8601String();
    try {
      final results = await Future.wait<Object>([
        _database.countReportsCreatedBetween(
          startIso: startIso,
          endIso: endIso,
          sectorId: sectorId,
        ),
        _database.countReportsResolvedBetween(
          startIso: startIso,
          endIso: endIso,
          sectorId: sectorId,
        ),
        _database.countActiveReports(
          sectorId: sectorId,
          validatedThreshold: validatedThreshold,
        ),
      ]);
      final active = results[2] as ({int reported, int validated});
      return CommunitySummary(
        reportedToday: results[0] as int,
        resolvedToday: results[1] as int,
        activeReported: active.reported,
        activeValidated: active.validated,
      );
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

final communitySummaryRepositoryProvider =
    Provider<CommunitySummaryRepository>(
      (ref) => SupabaseCommunitySummaryRepository(
        ref.watch(gotaCommunityDatabaseProvider),
      ),
    );
