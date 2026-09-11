import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/core/network/gota_database.dart';
import 'package:gota/features/location/data/municipality_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class MockGotaDatabase extends Mock implements GotaDatabase {}

void main() {
  late MockGotaDatabase database;
  late SupabaseMunicipalityRepository repository;

  setUp(() {
    database = MockGotaDatabase();
    repository = SupabaseMunicipalityRepository(database);
  });

  Map<String, dynamic> municipalityRow(String id, String name) => {
        'id': id,
        'name': name,
        'state': 'Nueva Esparta',
        'country': 'Venezuela',
        'is_active': true,
      };

  group('SupabaseMunicipalityRepository.getActive', () {
    test('mapea las filas de Maneiro y Arismendi a municipios', () async {
      when(() => database.fetchActiveMunicipalities()).thenAnswer(
        (_) async => [
          municipalityRow('id-1', 'Maneiro'),
          municipalityRow('id-2', 'Arismendi'),
        ],
      );

      final municipalities = await repository.getActive();

      expect(municipalities, hasLength(2));
      expect(municipalities.map((m) => m.name), ['Maneiro', 'Arismendi']);
      expect(municipalities.first.state, 'Nueva Esparta');
      expect(municipalities.first.isActive, isTrue);
    });

    test('PostgrestException se mapea a QueryException', () async {
      when(() => database.fetchActiveMunicipalities()).thenThrow(
        const supabase.PostgrestException(message: 'tabla inexistente'),
      );

      expect(
        () => repository.getActive(),
        throwsA(isA<QueryException>()),
      );
    });

    test('SocketException se mapea a NetworkException', () async {
      when(() => database.fetchActiveMunicipalities())
          .thenThrow(const SocketException('sin red'));

      expect(
        () => repository.getActive(),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
