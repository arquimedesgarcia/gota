import 'package:flutter_test/flutter_test.dart';
import 'package:gota/features/leaks/domain/location_suggestion.dart';

void main() {
  test('normaliza una sugerencia parcial sin convertirla en IDs', () {
    final suggestion = LocationSuggestion.fromJson({
      'latitude': 11.029536,
      'longitude': -63.865676,
      'display_text': 'Cerca de Casco Histórico, La Asunción',
      'locality': 'Casco Histórico',
      'city': 'La Asunción',
      'municipality': 'Municipio Arismendi',
      'state': 'Nueva Esparta',
      'provider': 'nominatim',
      'incomplete': false,
    });

    expect(suggestion.displayText, contains('Casco Histórico'));
    expect(suggestion.municipality, 'Municipio Arismendi');
    expect(suggestion.provider, 'nominatim');
    expect(suggestion.incomplete, isFalse);
    expect(suggestion.municipalityId, isNull);
    expect(suggestion.sectorId, isNull);
  });

  test('un resultado vacío se representa como incompleto', () {
    final suggestion = LocationSuggestion.fromJson({
      'latitude': 11.0,
      'longitude': -63.8,
      'provider': 'nominatim',
      'incomplete': true,
    });

    expect(suggestion.displayText, isNull);
    expect(suggestion.incomplete, isTrue);
    expect(suggestion.locality, isNull);
  });
}
