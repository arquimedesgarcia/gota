import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/core/network/gota_auth.dart';
import 'package:gota/core/network/gota_database.dart';
import 'package:gota/core/network/gota_storage.dart';
import 'package:gota/features/leaks/data/leak_report_repository.dart';
import 'package:gota/features/leaks/domain/create_leak_report_outcome.dart';
import 'package:gota/features/leaks/domain/leak_errors.dart';
import 'package:gota/features/leaks/domain/leak_report_draft.dart';
import 'package:gota/features/leaks/domain/location_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _uid = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

class _FakeAuth implements GotaAuth {
  _FakeAuth({this.session});

  final supabase.Session? session;

  @override
  supabase.Session? currentSession() => session;

  @override
  Future<supabase.Session> signInAnonymously() async =>
      session ?? (throw UnimplementedError());
}

supabase.Session _session() => supabase.Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: const supabase.User(
        id: _uid,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00.000Z',
      ),
    );

class _FakeStorage implements GotaStorage {
  _FakeStorage({this.failUploadAt = -1, this.failRemove = false});

  final int failUploadAt;
  final bool failRemove;

  final List<String> uploaded = [];
  final List<List<String>> removed = [];
  int uploadCalls = 0;

  @override
  Future<void> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadCalls++;
    if (failUploadAt >= 0 && uploadCalls == failUploadAt) {
      throw const supabase.StorageException('boom');
    }
    uploaded.add(path);
  }

  @override
  Future<void> remove({
    required String bucket,
    required List<String> paths,
  }) async {
    removed.add(paths);
    if (failRemove) {
      throw const supabase.StorageException('remove falló');
    }
  }

  @override
  Future<List<String>> list({
    required String bucket,
    required String prefix,
  }) async =>
      const [];
}

class _FakeDatabase implements GotaDatabase {
  _FakeDatabase({this.response, this.error});

  final Map<String, dynamic>? response;
  final Object? error;

  Map<String, dynamic>? lastParams;

  @override
  Future<Map<String, dynamic>> rpcCreateLeakReport(
    Map<String, dynamic> params,
  ) async {
    lastParams = params;
    if (error != null) throw error!;
    return response ?? const {};
  }

  @override
  Future<Map<String, dynamic>> ensureAppUser() async => const {};

  @override
  Future<List<Map<String, dynamic>>> fetchActiveMunicipalities() async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchSectorsForMunicipality(
    String municipalityId,
  ) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> fetchAppUserByAuthId(
    String authUserId,
  ) async =>
      null;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gota_photos_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String photoFile(String name) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(List<int>.filled(32, 7));
    return file.path;
  }

  LeakReportDraft draftWith(int photoCount) => LeakReportDraft(
        location: const SelectedLocation(
          latitude: 10.99,
          longitude: -63.87,
          source: LocationSource.gps,
        ),
        photos: [
          for (var i = 0; i < photoCount; i++)
            PreparedPhoto(
              id: 'p$i',
              originalPath: photoFile('orig_$i.jpg'),
              compressedPath: photoFile('c_$i.jpg'),
              mimeType: 'image/jpeg',
              sizeBytes: 1024,
              width: 0,
              height: 0,
            ),
        ],
        municipalityId: 'm1',
        sectorId: 's1',
      );

  SupabaseLeakReportRepository repo({
    required _FakeDatabase database,
    required _FakeStorage storage,
    supabase.Session? session,
  }) =>
      SupabaseLeakReportRepository(
        database,
        storage,
        _FakeAuth(session: session ?? _session()),
      );

  group('subida de fotos', () {
    test('usa la carpeta del propio usuario (RLS del bucket)', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        response: const {'status_code': 'CREATED', 'report_id': 'r1'},
      );

      await repo(database: database, storage: storage).createReport(
        draftWith(2),
      );

      expect(storage.uploaded, hasLength(2));
      for (final path in storage.uploaded) {
        expect(path, startsWith('report_photos/$_uid/'));
        expect(path, endsWith('.jpg'));
      }
      final photos =
          (database.lastParams!['p_photos'] as List).cast<Map>();
      expect(photos, hasLength(2));
      expect(photos.first['sort_order'], 1);
      expect(photos.last['sort_order'], 2);
      expect(
        photos.first['storage_path'],
        startsWith('report_photos/$_uid/'),
      );
    });

    test('sin sesión no sube nada y avisa al usuario', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase();

      await expectLater(
        SupabaseLeakReportRepository(
          database,
          storage,
          _FakeAuth(),
        ).createReport(draftWith(1)),
        throwsA(isA<LeakFlowException>()),
      );
      expect(storage.uploaded, isEmpty);
    });
  });

  group('cleanup de fotos temporales', () {
    test('no borra nada cuando el reporte se crea', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        response: const {'status_code': 'CREATED', 'report_id': 'r1'},
      );

      final outcome = await repo(database: database, storage: storage)
          .createReport(draftWith(1));

      expect(outcome, isA<ReportCreated>());
      expect(storage.removed, isEmpty);
    });

    test('borra lo subido cuando la RPC falla', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        error: const supabase.PostgrestException(message: 'boom'),
      );

      await expectLater(
        repo(database: database, storage: storage).createReport(draftWith(2)),
        throwsA(isA<QueryException>()),
      );

      expect(storage.uploaded, hasLength(2));
      expect(storage.removed, hasLength(1));
      expect(storage.removed.first, equals(storage.uploaded));
    });

    test('borra lo subido cuando se detecta POSSIBLE_DUPLICATE', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        response: const {
          'status_code': 'POSSIBLE_DUPLICATE',
          'candidates': [
            {
              'id': 'r1',
              'sector_id': 's1',
              'distance_meters': 22,
              'created_at': '2026-01-01T00:00:00.000Z',
            },
          ],
        },
      );

      final outcome = await repo(database: database, storage: storage)
          .createReport(draftWith(1));

      expect(outcome, isA<PossibleDuplicateFound>());
      expect(
        (outcome as PossibleDuplicateFound).candidates.first.distanceMeters,
        22,
      );
      expect(storage.removed, hasLength(1));
      expect(storage.removed.first, equals(storage.uploaded));
    });

    test('borra lo ya subido si falla la segunda foto', () async {
      final storage = _FakeStorage(failUploadAt: 2);
      final database = _FakeDatabase();

      await expectLater(
        repo(database: database, storage: storage).createReport(draftWith(2)),
        throwsA(isA<PhotoUploadException>()),
      );

      expect(storage.uploaded, hasLength(1));
      expect(storage.removed, hasLength(1));
      expect(storage.removed.first, hasLength(1));
      expect(database.lastParams, isNull);
    });

    test('reintenta el borrado y falla de forma visible, no silenciosa',
        () async {
      final storage = _FakeStorage(failRemove: true);
      final database = _FakeDatabase(
        response: const {
          'status_code': 'POSSIBLE_DUPLICATE',
          'candidates': <dynamic>[],
        },
      );

      await expectLater(
        repo(database: database, storage: storage).createReport(draftWith(1)),
        throwsA(isA<PhotoCleanupException>()),
      );

      // Dos intentos antes de rendirse; nunca se oculta el fallo.
      expect(storage.removed, hasLength(2));
    });
  });

  group('respuestas del backend', () {
    test('VALIDATION_ERROR se convierte en mensaje del servidor', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        response: const {
          'status_code': 'VALIDATION_ERROR',
          'message': 'Cada foto debe pesar como máximo 10 MB.',
        },
      );

      await expectLater(
        repo(database: database, storage: storage).createReport(draftWith(1)),
        throwsA(
          isA<ReportCreationException>().having(
            (e) => e.userMessage,
            'userMessage',
            'Cada foto debe pesar como máximo 10 MB.',
          ),
        ),
      );
      // El reporte no se creó: se limpian los temporales.
      expect(storage.removed, hasLength(1));
    });

    test('UNAUTHORIZED no se reporta como éxito', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        response: const {'status_code': 'UNAUTHORIZED'},
      );

      final outcome = await repo(database: database, storage: storage)
          .createReport(draftWith(1));

      expect(outcome, isA<LeakReportUnauthorized>());
    });

    test('la confirmación "es otra fuga" viaja como p_ignore_duplicate',
        () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        response: const {'status_code': 'CREATED', 'report_id': 'r2'},
      );

      await repo(database: database, storage: storage).createReport(
        draftWith(1),
        ignoreDuplicate: true,
      );

      expect(database.lastParams!['p_ignore_duplicate'], isTrue);
    });

    test('por defecto no se ignora el duplicado', () async {
      final storage = _FakeStorage();
      final database = _FakeDatabase(
        response: const {'status_code': 'CREATED', 'report_id': 'r3'},
      );

      await repo(database: database, storage: storage).createReport(
        draftWith(1),
      );

      expect(database.lastParams!['p_ignore_duplicate'], isFalse);
      expect(database.lastParams!['p_location_source'], 'GPS');
    });
  });
}
