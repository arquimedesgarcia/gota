import 'package:flutter_test/flutter_test.dart';

import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/core/network/gota_community_database.dart';
import 'package:gota/features/leaks/data/leak_photo_repository.dart';
import 'package:gota/features/leaks/domain/leak_community_errors.dart';
import 'package:gota/features/leaks/domain/leak_photo.dart';

class _FakeCommunityDatabase implements GotaCommunityDatabase {
  Map<String, dynamic> photosResponse = {'status_code': 'OK', 'photos': []};

  @override
  Future<Map<String, dynamic>> rpcGetReportPhotos(String reportId) async =>
      photosResponse;

  // Resto de la interfaz: no se usa en estos tests.
  @override
  Future<List<Map<String, dynamic>>> fetchRecentLeakReports({int limit = 20}) =>
      throw UnimplementedError();
  @override
  Future<int> countReportsCreatedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) => throw UnimplementedError();
  @override
  Future<int> countReportsResolvedBetween({
    required String startIso,
    required String endIso,
    String? sectorId,
  }) => throw UnimplementedError();
  @override
  Future<({int reported, int validated})> countActiveReports({
    String? sectorId,
    int validatedThreshold = 3,
  }) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> rpcLeakReportDetail(String reportId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> rpcValidateLeak(String reportId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> rpcConfirmLeakResolution(String reportId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>?> fetchLatestCommunityActivity() =>
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
  }) => throw UnimplementedError();
}

void main() {
  late _FakeCommunityDatabase db;
  late SupabaseLeakPhotoRepository repo;

  setUp(() {
    db = _FakeCommunityDatabase();
    repo = SupabaseLeakPhotoRepository(db);
  });

  group('SupabaseLeakPhotoRepository.getPhotos', () {
    test('OK con fotos devuelve lista de LeakPhoto', () async {
      db.photosResponse = {
        'status_code': 'OK',
        'photos': [
          {
            'id': 'p1',
            'sort_order': 0,
            'url': 'https://cdn.example.com/photo1.jpg',
            'thumbnail_url': 'https://cdn.example.com/photo1_thumb.jpg',
            'width': 1280,
            'height': 960,
          },
          {
            'id': 'p2',
            'sort_order': 1,
            'url': 'https://cdn.example.com/photo2.jpg',
            'thumbnail_url': null,
            'width': null,
            'height': null,
          },
        ],
      };

      final photos = await repo.getPhotos('report-123');

      expect(photos.length, 2);
      final p1 = photos[0];
      expect(p1.id, 'p1');
      expect(p1.sortOrder, 0);
      expect(p1.url, 'https://cdn.example.com/photo1.jpg');
      expect(p1.thumbnailUrl, 'https://cdn.example.com/photo1_thumb.jpg');
      expect(p1.width, 1280);
      expect(p1.height, 960);

      final p2 = photos[1];
      expect(p2.thumbnailUrl, isNull);
    });

    test('OK con lista vacía devuelve []', () async {
      db.photosResponse = {'status_code': 'OK', 'photos': []};

      final photos = await repo.getPhotos('report-empty');

      expect(photos, isEmpty);
    });

    test('OK con photos null devuelve []', () async {
      db.photosResponse = {'status_code': 'OK', 'photos': null};

      final photos = await repo.getPhotos('report-null');

      expect(photos, isEmpty);
    });

    test('fotos con url vacía se filtran', () async {
      db.photosResponse = {
        'status_code': 'OK',
        'photos': [
          {'id': 'p1', 'sort_order': 0, 'url': ''},
          {
            'id': 'p2',
            'sort_order': 1,
            'url': 'https://cdn.example.com/good.jpg',
          },
        ],
      };

      final photos = await repo.getPhotos('report-filter');

      expect(photos.length, 1);
      expect(photos.first.id, 'p2');
    });

    test('expiresAt se establece ≈ ahora + 900 s', () async {
      db.photosResponse = {
        'status_code': 'OK',
        'photos': [
          {'id': 'p1', 'sort_order': 0, 'url': 'https://cdn.example.com/p.jpg'},
        ],
      };

      final before = DateTime.now().toUtc();
      final photos = await repo.getPhotos('report-exp');
      final after = DateTime.now().toUtc();

      expect(photos.length, 1);
      final expires = photos.first.expiresAt!;
      final lowerBound = before.add(const Duration(seconds: 895));
      final upperBound = after.add(const Duration(seconds: 905));
      expect(expires.isAfter(lowerBound), isTrue);
      expect(expires.isBefore(upperBound), isTrue);
    });

    test('isExpiringSoon retorna false para URL recién obtenida', () async {
      db.photosResponse = {
        'status_code': 'OK',
        'photos': [
          {'id': 'p1', 'sort_order': 0, 'url': 'https://cdn.example.com/p.jpg'},
        ],
      };

      final photos = await repo.getPhotos('report-fresh');

      expect(photos.first.isExpiringSoon(), isFalse);
    });

    test('isExpiringSoon retorna true para URL con expiry en el pasado', () {
      final expired = LeakPhoto(
        id: 'x',
        sortOrder: 0,
        url: 'https://cdn.example.com/p.jpg',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );

      expect(expired.isExpiringSoon(), isTrue);
    });

    test('displayThumbnailUrl retorna thumbnailUrl cuando existe', () {
      const photo = LeakPhoto(
        id: 'x',
        sortOrder: 0,
        url: 'https://cdn.example.com/full.jpg',
        thumbnailUrl: 'https://cdn.example.com/thumb.jpg',
      );

      expect(photo.displayThumbnailUrl, 'https://cdn.example.com/thumb.jpg');
    });

    test('displayThumbnailUrl hace fallback a url cuando thumbnailUrl es null', () {
      const photo = LeakPhoto(
        id: 'x',
        sortOrder: 0,
        url: 'https://cdn.example.com/full.jpg',
      );

      expect(photo.displayThumbnailUrl, 'https://cdn.example.com/full.jpg');
    });

    test('NOT_FOUND lanza LeakReportNotFoundException', () async {
      db.photosResponse = {'status_code': 'NOT_FOUND'};

      await expectLater(
        () => repo.getPhotos('report-ghost'),
        throwsA(isA<LeakReportNotFoundException>()),
      );
    });

    test('FORBIDDEN lanza LeakCommunityForbiddenException', () async {
      db.photosResponse = {'status_code': 'FORBIDDEN'};

      await expectLater(
        () => repo.getPhotos('report-blocked'),
        throwsA(isA<LeakCommunityForbiddenException>()),
      );
    });

    test('RATE_LIMIT_EXCEEDED lanza QueryException', () async {
      db.photosResponse = {'status_code': 'RATE_LIMIT_EXCEEDED'};

      await expectLater(
        () => repo.getPhotos('report-rate'),
        throwsA(isA<QueryException>()),
      );
    });

    test('status_code desconocido lanza QueryException', () async {
      db.photosResponse = {'status_code': 'UNKNOWN_CODE'};

      await expectLater(
        () => repo.getPhotos('report-unknown'),
        throwsA(isA<QueryException>()),
      );
    });
  });
}
