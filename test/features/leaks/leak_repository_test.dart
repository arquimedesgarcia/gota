import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:gota/features/leaks/domain/create_leak_report_outcome.dart';
import 'package:gota/features/leaks/domain/leak_errors.dart';
import 'package:gota/features/leaks/domain/leak_report_draft.dart';
import 'package:gota/features/leaks/domain/location_source.dart';

class _MockClient extends Mock implements supabase.SupabaseClient {}

void main() {
  group('LeakReportRepository contrato', () {
    test('un draft sin ubicación no debe construirse como envíable', () {
      const draft = LeakReportDraft();
      expect(draft.location, isNull);
      expect(draft.photos, isEmpty);
      // canSubmit equivalente: ubicación + fotos + municipio + sector.
      final canSubmit = draft.location != null &&
          draft.photos.isNotEmpty &&
          draft.municipalityId != null &&
          draft.sectorId != null;
      expect(canSubmit, isFalse);
    });

    test('draft con cámara lista arma fuente y referencias', () {
      final draft = const LeakReportDraft(
        location: SelectedLocation(
          latitude: 10.99,
          longitude: -63.87,
          source: LocationSource.gps,
        ),
      ).copyWith(municipalityId: 'm1', sectorId: 's1');

      expect(draft.location!.source.wireName, 'GPS');
      expect(draft.location!.latitude, 10.99);
      final canSubmit =
          draft.photos.isNotEmpty; // aún sin fotos
      expect(canSubmit, isFalse);
    });

    test(
      'PhotoValidationException y PhotoUploadException tienen mensaje '
      'para el usuario',
      () {
        const validation =
            PhotoValidationException('Formato no admitido.');
        const upload = PhotoUploadException();
        expect(validation.userMessage, isNotEmpty);
        expect(upload.userMessage, contains('fotos'));
      },
    );
  });

  group('CreateLeakReportOutcome', () {
    test('ReportCreated lleva el id del reporte', () {
      const outcome = ReportCreated(reportId: 'r1');
      expect(outcome.reportId, 'r1');
    });

    test('PossibleDuplicateFound guarda candidatos con distancia', () {
      final candidate = PossibleDuplicateCandidate.fromJson(const {
        'id': 'r1',
        'sector_id': 's1',
        'distance_meters': 18,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      final outcome = PossibleDuplicateFound(candidates: [candidate]);
      expect(outcome.candidates.first.distanceMeters, 18);
      expect(outcome.candidates.first.id, 'r1');
    });

    test('LeakReportUnauthorized es un caso de sesión expirada', () {
      const outcome = LeakReportUnauthorized();
      expect(outcome, isA<CreateLeakReportOutcome>());
    });
  });

  // Verificación de tipos del mocktail contra la costura de Supabase.
  test('SupabaseClient puede simularse con mocktail', () {
    final client = _MockClient();
    expect(client, isA<supabase.SupabaseClient>());
  });
}
