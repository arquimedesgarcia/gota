import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/core/network/gota_community_database.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/leaks/domain/leak_community_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _reportId = 'r1';

class _FakeCommunityDatabase implements GotaCommunityDatabase {
  _FakeCommunityDatabase({
    this.rows = const [],
    this.detail,
    this.validateResponse,
    this.confirmResponse,
    this.error,
  });

  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? detail;
  final Map<String, dynamic>? validateResponse;
  final Map<String, dynamic>? confirmResponse;
  final Object? error;

  String? lastRpc;
  String? lastReportId;

  Map<String, dynamic> _respond(
    String rpc,
    String reportId,
    Map<String, dynamic>? response,
  ) {
    lastRpc = rpc;
    lastReportId = reportId;
    if (error != null) throw error!;
    return response ?? const {};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRecentLeakReports({
    int limit = 20,
  }) async {
    if (error != null) throw error!;
    return rows;
  }

  @override
  Future<int> countReportsCreatedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) async {
    if (error != null) throw error!;
    return 0;
  }

  @override
  Future<int> countReportsResolvedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) async {
    if (error != null) throw error!;
    return 0;
  }

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
  }) async {
    if (error != null) throw error!;
    return rows;
  }

  @override
  Future<Map<String, dynamic>> rpcLeakReportDetail(String reportId) async =>
      _respond('get_leak_report_detail', reportId, detail);

  @override
  Future<Map<String, dynamic>> rpcValidateLeak(String reportId) async =>
      _respond('validate_leak', reportId, validateResponse);

  @override
  Future<Map<String, dynamic>> rpcConfirmLeakResolution(
    String reportId,
  ) async => _respond('confirm_leak_resolution', reportId, confirmResponse);
}

LeakCommunityRepository _repo(_FakeCommunityDatabase database) =>
    SupabaseLeakCommunityRepository(database);

void main() {
  group('lista de fugas recientes', () {
    test('mapea los recursos embebidos de PostgREST', () async {
      final database = _FakeCommunityDatabase(
        rows: [
          {
            'id': 'r1',
            'status': 'ACTIVE',
            'validation_count': 2,
            'resolution_confirmation_count': 1,
            'created_at': '2026-01-01T10:00:00.000Z',
            'resolved_at': null,
            'description': 'Tubería rota',
            'sectors': {'name': 'La Caranta'},
            'municipalities': {'name': 'Maneiro'},
          },
          {
            'id': 'r2',
            'status': 'RESOLVED',
            'validation_count': 5,
            'resolution_confirmation_count': 3,
            'created_at': '2026-01-01T09:00:00.000Z',
            'resolved_at': '2026-01-02T09:00:00.000Z',
            'sectors': null,
            'municipalities': null,
          },
        ],
      );

      final leaks = await _repo(database).recentReports();

      expect(leaks, hasLength(2));
      expect(leaks.first.sectorName, 'La Caranta');
      expect(leaks.first.municipalityName, 'Maneiro');
      expect(leaks.first.validationCount, 2);
      expect(leaks.first.isResolved, isFalse);
      expect(leaks.last.isResolved, isTrue);
      expect(leaks.last.resolvedAt, isNotNull);
      expect(leaks.last.sectorName, isNull);
    });

    test('un fallo de red se traduce a NetworkException', () async {
      final database = _FakeCommunityDatabase(
        error: const SocketException('sin red'),
      );

      await expectLater(
        _repo(database).recentReports(),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('detalle de la fuga', () {
    test(
      'devuelve el estado del usuario actual que reporta el backend',
      () async {
        final database = _FakeCommunityDatabase(
          detail: const {
            'status_code': 'OK',
            'report_id': _reportId,
            'status': 'ACTIVE',
            'validation_count': 2,
            'resolution_confirmation_count': 1,
            'threshold': 3,
            'created_at': '2026-01-01T10:00:00.000Z',
            'latitude': 10.99,
            'longitude': -63.87,
            'photo_count': 2,
            'sector_name': 'La Caranta',
            'municipality_name': 'Maneiro',
            'is_creator': false,
            'is_blocked': false,
            'already_validated': false,
            'already_confirmed': false,
          },
        );

        final detail = await _repo(database).reportDetail(_reportId);

        expect(detail.threshold, 3);
        expect(detail.validationCount, 2);
        expect(detail.canValidate, isTrue);
        expect(detail.canConfirmResolution, isTrue);
      },
    );

    test('el creador no puede validar (lo decide el backend)', () async {
      final database = _FakeCommunityDatabase(
        detail: const {
          'status_code': 'OK',
          'report_id': _reportId,
          'status': 'ACTIVE',
          'is_creator': true,
          'already_validated': false,
          'already_confirmed': false,
          'threshold': 3,
          'created_at': '2026-01-01T10:00:00.000Z',
        },
      );

      final detail = await _repo(database).reportDetail(_reportId);

      expect(detail.isCreator, isTrue);
      expect(detail.canValidate, isFalse);
      // El creador sí puede confirmar resolución (decisión REQ-051).
      expect(detail.canConfirmResolution, isTrue);
    });

    test('fuga resuelta: sin acciones disponibles', () async {
      final database = _FakeCommunityDatabase(
        detail: const {
          'status_code': 'OK',
          'report_id': _reportId,
          'status': 'RESOLVED',
          'threshold': 3,
          'created_at': '2026-01-01T10:00:00.000Z',
          'resolved_at': '2026-01-02T10:00:00.000Z',
          'already_validated': true,
          'already_confirmed': true,
        },
      );

      final detail = await _repo(database).reportDetail(_reportId);

      expect(detail.isResolved, isTrue);
      expect(detail.canValidate, isFalse);
      expect(detail.canConfirmResolution, isFalse);
    });

    test('reporte inexistente', () async {
      final database = _FakeCommunityDatabase(
        detail: const {'status_code': 'NOT_FOUND'},
      );

      await expectLater(
        _repo(database).reportDetail(_reportId),
        throwsA(isA<LeakReportNotFoundException>()),
      );
    });

    test('sin sesión activa', () async {
      final database = _FakeCommunityDatabase(
        detail: const {'status_code': 'UNAUTHORIZED'},
      );

      await expectLater(
        _repo(database).reportDetail(_reportId),
        throwsA(isA<LeakCommunityUnauthorizedException>()),
      );
    });
  });

  group('validar fuga', () {
    test('validación exitosa: el contador viene del backend', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {
          'status_code': 'VALIDATED',
          'status': 'ACTIVE',
          'validation_count': 3,
          'resolution_confirmation_count': 1,
          'threshold': 3,
          'already_validated': false,
        },
      );

      final result = await _repo(database).validateLeak(_reportId);

      expect(result.validationCount, 3);
      expect(result.isResolved, isFalse);
      expect(database.lastRpc, 'validate_leak');
      // El cliente solo aporta el identificador del reporte: los contadores
      // y el estado los decide exclusivamente el backend.
      expect(database.lastReportId, _reportId);
    });

    test('segunda validación del mismo usuario → DUPLICATE_ACTION', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {
          'status_code': 'DUPLICATE_ACTION',
          'message': 'Ya validaste este reporte.',
          'already_validated': true,
          'validation_count': 1,
          'threshold': 3,
        },
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(
          isA<DuplicateCommunityActionException>().having(
            (e) => e.userMessage,
            'userMessage',
            'Ya validaste este reporte.',
          ),
        ),
      );
    });

    test('el creador recibe el mensaje del backend', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {
          'status_code': 'FORBIDDEN',
          'message': 'No puedes validar tu propio reporte.',
        },
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(
          isA<LeakCommunityForbiddenException>().having(
            (e) => e.userMessage,
            'userMessage',
            'No puedes validar tu propio reporte.',
          ),
        ),
      );
    });

    test('usuario bloqueado', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {
          'status_code': 'FORBIDDEN',
          'message': 'Tu acceso está bloqueado.',
        },
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(
          isA<LeakCommunityForbiddenException>().having(
            (e) => e.userMessage,
            'userMessage',
            'Tu acceso está bloqueado.',
          ),
        ),
      );
    });

    test('reporte inexistente', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {'status_code': 'NOT_FOUND'},
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(isA<LeakReportNotFoundException>()),
      );
    });

    test('estado incompatible (ya resuelta)', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {
          'status_code': 'REPORT_ALREADY_RESOLVED',
          'status': 'RESOLVED',
        },
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(isA<LeakReportResolvedException>()),
      );
    });

    test('sin sesión', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {'status_code': 'UNAUTHORIZED'},
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(isA<LeakCommunityUnauthorizedException>()),
      );
    });

    test('Códigos desconocidos no se reportan como éxito', () async {
      final database = _FakeCommunityDatabase(
        validateResponse: const {'status_code': 'INTERNAL_ERROR'},
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(isA<QueryException>()),
      );
    });

    test('fallo de red', () async {
      final database = _FakeCommunityDatabase(
        error: const SocketException('sin red'),
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(isA<NetworkException>()),
      );
    });

    test('error de PostgREST se traduce a QueryException', () async {
      final database = _FakeCommunityDatabase(
        error: const supabase.PostgrestException(message: 'boom'),
      );

      await expectLater(
        _repo(database).validateLeak(_reportId),
        throwsA(isA<QueryException>()),
      );
    });
  });

  group('confirmar resolución', () {
    test('confirmación sin umbral alcanzado', () async {
      final database = _FakeCommunityDatabase(
        confirmResponse: const {
          'status_code': 'CONFIRMED',
          'status': 'ACTIVE',
          'validation_count': 4,
          'resolution_confirmation_count': 2,
          'threshold': 3,
        },
      );

      final result = await _repo(database).confirmResolution(_reportId);

      expect(result.isResolved, isFalse);
      expect(result.resolutionConfirmationCount, 2);
      expect(result.threshold, 3);
      expect(database.lastRpc, 'confirm_leak_resolution');
    });

    test('umbral alcanzado: el backend devuelve RESOLVED', () async {
      final database = _FakeCommunityDatabase(
        confirmResponse: const {
          'status_code': 'RESOLVED',
          'status': 'RESOLVED',
          'validation_count': 4,
          'resolution_confirmation_count': 3,
          'threshold': 3,
          'resolved_at': '2026-01-02T10:00:00.000Z',
        },
      );

      final result = await _repo(database).confirmResolution(_reportId);

      expect(result.isResolved, isTrue);
      expect(result.resolvedAt, isNotNull);
      expect(result.resolutionConfirmationCount, 3);
    });

    test('confirmación duplicada → DUPLICATE_ACTION', () async {
      final database = _FakeCommunityDatabase(
        confirmResponse: const {
          'status_code': 'DUPLICATE_ACTION',
          'message': 'Ya confirmaste la resolución de esta fuga.',
          'resolution_confirmation_count': 1,
        },
      );

      await expectLater(
        _repo(database).confirmResolution(_reportId),
        throwsA(
          isA<DuplicateCommunityActionException>().having(
            (e) => e.userMessage,
            'userMessage',
            'Ya confirmaste la resolución de esta fuga.',
          ),
        ),
      );
    });

    test('usuario bloqueado', () async {
      final database = _FakeCommunityDatabase(
        confirmResponse: const {
          'status_code': 'FORBIDDEN',
          'message': 'Tu acceso está bloqueado.',
        },
      );

      await expectLater(
        _repo(database).confirmResolution(_reportId),
        throwsA(isA<LeakCommunityForbiddenException>()),
      );
    });

    test('reporte inexistente', () async {
      final database = _FakeCommunityDatabase(
        confirmResponse: const {'status_code': 'NOT_FOUND'},
      );

      await expectLater(
        _repo(database).confirmResolution(_reportId),
        throwsA(isA<LeakReportNotFoundException>()),
      );
    });

    test('reporte ya resuelto por otras identidades', () async {
      final database = _FakeCommunityDatabase(
        confirmResponse: const {
          'status_code': 'REPORT_ALREADY_RESOLVED',
          'status': 'RESOLVED',
        },
      );

      await expectLater(
        _repo(database).confirmResolution(_reportId),
        throwsA(isA<LeakReportResolvedException>()),
      );
    });

    test('sin sesión', () async {
      final database = _FakeCommunityDatabase(
        confirmResponse: const {'status_code': 'UNAUTHORIZED'},
      );

      await expectLater(
        _repo(database).confirmResolution(_reportId),
        throwsA(isA<LeakCommunityUnauthorizedException>()),
      );
    });
  });

  group('modelo del resultado', () {
    test('CommunityActionResult refleja exactamente la respuesta', () {
      final result = const CommunityActionResult(
        status: 'RESOLVED',
        validationCount: 7,
        resolutionConfirmationCount: 3,
        threshold: 3,
      );

      expect(result.isResolved, isTrue);
      expect(result.validationCount, 7);
    });

    test('LeakSummary tolera campos ausentes sin inventar datos', () {
      final summary = LeakSummary.fromJson(const {
        'id': 'r9',
        'created_at': '2026-01-01T00:00:00.000Z',
      });

      expect(summary.status, 'ACTIVE');
      expect(summary.validationCount, 0);
      expect(summary.isResolved, isFalse);
      expect(summary.sectorName, isNull);
    });
  });
}
