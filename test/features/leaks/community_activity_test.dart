import 'package:flutter_test/flutter_test.dart';
import 'package:gota/features/leaks/domain/community_activity.dart';

void main() {
  group('CommunityActivity.fromJson', () {
    test('mapea un evento RESOLVED con todos los campos', () {
      final activity = CommunityActivity.fromJson(const {
        'activity_type': 'RESOLVED',
        'at': '2026-09-03T12:00:00.000Z',
        'report_id': 'r1',
        'status': 'RESOLVED',
        'validation_count': 4,
        'resolution_confirmation_count': 3,
        'created_at': '2026-09-01T10:00:00.000Z',
        'resolved_at': '2026-09-03T12:00:00.000Z',
        'description': 'Tubería rota',
        'sector_id': 's1',
        'sector_name': 'La Caranta',
        'municipality_id': 'm1',
        'municipality_name': 'Maneiro',
      });

      expect(activity.type, CommunityActivityType.resolved);
      expect(activity.at, DateTime.parse('2026-09-03T12:00:00.000Z'));
      expect(activity.reportId, 'r1');
      expect(activity.isResolved, isTrue);
      expect(activity.resolvedAt, isNotNull);
      expect(activity.placeLabel, 'La Caranta · Maneiro');
    });

    test('REPORTED de una falla que sigue ACTIVE no es "resuelta"', () {
      final activity = CommunityActivity.fromJson(const {
        'activity_type': 'REPORTED',
        'at': '2026-09-01T10:00:00.000Z',
        'report_id': 'r2',
        'status': 'ACTIVE',
        'validation_count': 0,
        'resolution_confirmation_count': 0,
        'created_at': '2026-09-01T10:00:00.000Z',
      });

      expect(activity.type, CommunityActivityType.reported);
      expect(activity.isResolved, isFalse);
    });

    test('placeLabel tolera sector o municipio ausentes', () {
      final onlySector = CommunityActivity.fromJson(const {
        'activity_type': 'VALIDATED',
        'at': '2026-09-02T10:00:00.000Z',
        'report_id': 'r3',
        'status': 'ACTIVE',
        'created_at': '2026-09-01T10:00:00.000Z',
        'sector_name': 'La Caranta',
      });

      expect(onlySector.placeLabel, 'La Caranta');
    });

    test('un activity_type desconocido es un error de formato', () {
      expect(
        () => CommunityActivity.fromJson(const {
          'activity_type': 'PONDERED',
          'at': '2026-09-02T10:00:00.000Z',
          'report_id': 'r4',
          'created_at': '2026-09-01T10:00:00.000Z',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CommunityActivityType.fromText', () {
    test('parsea los tres tipos válidos', () {
      expect(
        CommunityActivityType.fromText('REPORTED'),
        CommunityActivityType.reported,
      );
      expect(
        CommunityActivityType.fromText('VALIDATED'),
        CommunityActivityType.validated,
      );
      expect(
        CommunityActivityType.fromText('RESOLVED'),
        CommunityActivityType.resolved,
      );
    });

    test('null o desconocido lanza FormatException', () {
      expect(
        () => CommunityActivityType.fromText(null),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CommunityActivityType.fromText('WHATEVER'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
