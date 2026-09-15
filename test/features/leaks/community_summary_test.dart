import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/core/network/gota_community_database.dart';
import 'package:gota/features/leaks/data/community_summary_repository.dart';
import 'package:gota/features/leaks/domain/community_summary.dart';

class _FakeCommunityDatabase implements GotaCommunityDatabase {
  int createdCount = 0;
  int resolvedCount = 0;
  Object? error;

  String? lastCreatedStart;
  String? lastCreatedEnd;
  String? lastCreatedSector;
  String? lastResolvedStart;
  String? lastResolvedEnd;
  String? lastResolvedSector;

  @override
  Future<int> countReportsCreatedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) async {
    if (error != null) throw error!;
    lastCreatedStart = startIso;
    lastCreatedEnd = endIso;
    lastCreatedSector = sectorId;
    return createdCount;
  }

  @override
  Future<int> countReportsResolvedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) async {
    if (error != null) throw error!;
    lastResolvedStart = startIso;
    lastResolvedEnd = endIso;
    lastResolvedSector = sectorId;
    return resolvedCount;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRecentLeakReports({int limit = 20}) =>
      throw UnimplementedError();

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
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> rpcLeakReportDetail(String reportId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> rpcValidateLeak(String reportId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> rpcConfirmLeakResolution(String reportId) =>
      throw UnimplementedError();
}

void main() {
  group('caracasDayBounds (America/Caracas = UTC-4 fijo)', () {
    test('mediodía UTC cae en el día caraqueño anterior antes de las 04:00Z', () {
      // 2026-09-15T03:59Z = 2026-09-14 23:59 en Caracas.
      final bounds = caracasDayBounds(DateTime.utc(2026, 9, 15, 3, 59));
      expect(bounds.startUtc, DateTime.utc(2026, 9, 14, 4));
      expect(bounds.endUtc, DateTime.utc(2026, 9, 15, 4));
    });

    test('las 04:00Z abren el nuevo día caraqueño', () {
      final bounds = caracasDayBounds(DateTime.utc(2026, 9, 15, 4));
      expect(bounds.startUtc, DateTime.utc(2026, 9, 15, 4));
      expect(bounds.endUtc, DateTime.utc(2026, 9, 16, 4));
    });

    test('ventana semiabierta de exactamente 24h', () {
      final bounds = caracasDayBounds(DateTime.utc(2026, 9, 15, 12, 30));
      expect(
        bounds.endUtc.difference(bounds.startUtc),
        const Duration(hours: 24),
      );
      expect(bounds.startUtc.hour, 4);
      expect(bounds.startUtc.minute, 0);
    });
  });

  group('CommunitySummaryRepository', () {
    test('Caso 1/3: mapea conteos del backend al resumen', () async {
      final db = _FakeCommunityDatabase()
        ..createdCount = 2
        ..resolvedCount = 1;
      final repo = SupabaseCommunitySummaryRepository(db);

      final summary = await repo.todaySummary(
        nowUtc: DateTime.utc(2026, 9, 15, 12),
      );

      expect(summary.reportedToday, 2);
      expect(summary.resolvedToday, 1);
    });

    test('Caso 2/4: la ventana enviada es el día Caracas en UTC', () async {
      final db = _FakeCommunityDatabase();
      final repo = SupabaseCommunitySummaryRepository(db);

      await repo.todaySummary(nowUtc: DateTime.utc(2026, 9, 15, 12));

      expect(db.lastCreatedStart, '2026-09-15T04:00:00.000Z');
      expect(db.lastCreatedEnd, '2026-09-16T04:00:00.000Z');
      expect(db.lastResolvedStart, '2026-09-15T04:00:00.000Z');
      expect(db.lastResolvedEnd, '2026-09-16T04:00:00.000Z');
    });

    test('Caso 5: el sector de interés se propaga a ambas consultas', () async {
      final db = _FakeCommunityDatabase();
      final repo = SupabaseCommunitySummaryRepository(db);

      await repo.todaySummary(
        sectorId: 's1',
        nowUtc: DateTime.utc(2026, 9, 15, 12),
      );

      expect(db.lastCreatedSector, 's1');
      expect(db.lastResolvedSector, 's1');
    });

    test('Caso 6: sin sector el alcance es global (sector null)', () async {
      final db = _FakeCommunityDatabase();
      final repo = SupabaseCommunitySummaryRepository(db);

      await repo.todaySummary(nowUtc: DateTime.utc(2026, 9, 15, 12));

      expect(db.lastCreatedSector, isNull);
      expect(db.lastResolvedSector, isNull);
    });

    test('Caso 8: error de red/postgrest no se convierte en ceros', () async {
      final db = _FakeCommunityDatabase()
        ..error = const SocketException('sin red');
      final repo = SupabaseCommunitySummaryRepository(db);

      expect(
        () => repo.todaySummary(nowUtc: DateTime.utc(2026, 9, 15, 12)),
        throwsA(isA<NetworkException>()),
      );

      db.error = supabase.PostgrestException(message: 'boom');
      expect(
        () => repo.todaySummary(nowUtc: DateTime.utc(2026, 9, 15, 12)),
        throwsA(isA<QueryException>()),
      );
    });
  });
}
