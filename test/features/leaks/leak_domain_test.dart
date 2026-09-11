import 'package:flutter_test/flutter_test.dart';
import 'package:gota/features/leaks/data/location_service.dart';
import 'package:gota/features/leaks/domain/create_leak_report_outcome.dart';
import 'package:gota/features/leaks/domain/leak_errors.dart';
import 'package:gota/features/leaks/domain/leak_report_draft.dart';
import 'package:gota/features/leaks/domain/location_source.dart';

LocationService fakeLocationService({
  Object? throw_,
  double lat = 10.99,
  double lng = -63.87,
}) =>
    _FakeLocationService(throw_: throw_, lat: lat, lng: lng);

class _FakeLocationService implements LocationService {
  _FakeLocationService({this.throw_, this.lat = 10.99, this.lng = -63.87});

  final Object? throw_;
  final double lat;
  final double lng;

  @override
  Future<({double latitude, double longitude})> getCurrentPosition() async {
    if (throw_ != null) throw throw_!;
    return (latitude: lat, longitude: lng);
  }
}

void main() {
  group('LocationSource', () {
    test('wireName mapea GPS/MANUAL según el modelo', () {
      expect(LocationSource.gps.wireName, 'GPS');
      expect(LocationSource.manual.wireName, 'MANUAL');
    });

    test('label muestra al usuario si es GPS o manual', () {
      expect(LocationSource.gps.label, 'Ubicación por GPS');
      expect(LocationSource.manual.label, 'Ubicación manual');
    });
  });

  group('SelectedLocation', () {
    test('isGps distingue la fuente', () {
      const gps = SelectedLocation(
        latitude: 10.99,
        longitude: -63.87,
        source: LocationSource.gps,
      );
      const manual = SelectedLocation(
        latitude: 10.99,
        longitude: -63.87,
        source: LocationSource.manual,
      );
      expect(gps.isGps, isTrue);
      expect(manual.isGps, isFalse);
    });
  });

  group('LeakReportDraft', () {
    test('sin fotos hasPhotos es false y canSubmit-like checks fallan', () {
      const draft = LeakReportDraft();
      expect(draft.hasPhotos, isFalse);
      expect(draft.location, isNull);
    });

    test('copyWith preserva y reemplaza campos', () {
      final draft = const LeakReportDraft().copyWith(
        municipalityId: 'm1',
      );
      expect(draft.municipalityId, 'm1');
      expect(draft.sectorId, isNull);
    });
  });

  group('PossibleDuplicateCandidate', () {
    test('fromJson mapea id, distancia y createdAt', () {
      final candidate = PossibleDuplicateCandidate.fromJson(const {
        'id': 'r1',
        'sector_id': 's1',
        'distance_meters': 12,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(candidate.id, 'r1');
      expect(candidate.distanceMeters, 12);
      expect(candidate.createdAt.year, 2026);
    });
  });

  group('LeakFlowException', () {
    test('mensajes de GPS denegado/apagado son accionables', () {
      const denied = LocationPermissionDeniedException();
      const off = LocationServiceOffException();
      expect(denied.userMessage, contains('manual'));
      expect(off.userMessage, contains('manual'));
    });
  });
}
