import 'package:flutter/foundation.dart';

/// Resultado descriptivo del reverse geocoder.
///
/// Nunca contiene IDs de catálogo: una localidad OSM no es un sector Gota.
@immutable
class LocationSuggestion {
  const LocationSuggestion({
    required this.latitude,
    required this.longitude,
    required this.provider,
    this.displayText,
    this.locality,
    this.neighborhood,
    this.city,
    this.municipality,
    this.state,
    this.incomplete = false,
  });

  final double latitude;
  final double longitude;
  final String provider;
  final String? displayText;
  final String? locality;
  final String? neighborhood;
  final String? city;
  final String? municipality;
  final String? state;
  final bool incomplete;

  // Deliberadamente no se derivan desde texto del proveedor.
  String? get municipalityId => null;
  String? get sectorId => null;

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    return LocationSuggestion(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      provider: json['provider'] as String? ?? 'unknown',
      displayText: json['display_text'] as String?,
      locality: json['locality'] as String?,
      neighborhood: json['neighborhood'] as String?,
      city: json['city'] as String?,
      municipality: json['municipality'] as String?,
      state: json['state'] as String?,
      incomplete: json['incomplete'] as bool? ?? true,
    );
  }
}
