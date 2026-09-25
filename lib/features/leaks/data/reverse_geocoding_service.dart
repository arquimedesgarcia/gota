import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../domain/leak_errors.dart';
import '../domain/location_suggestion.dart';

abstract class ReverseGeocodingService {
  Future<LocationSuggestion?> reverse({
    required double latitude,
    required double longitude,
  });
}

/// Llama a Nominatim directamente desde el dispositivo del usuario.
///
/// Las IPs de los dispositivos móviles NO están bloqueadas por Nominatim.
/// Las IPs de las infraestructuras cloud (Supabase / Deno Deploy) sí lo
/// estaban, causando que la versión anterior basada en Edge Function fallara.
/// El paquete `http` ya figura en pubspec.yaml — no se añade dependencia nueva.
class NominatimReverseGeocodingService implements ReverseGeocodingService {
  NominatimReverseGeocodingService({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  static const _host = 'nominatim.openstreetmap.org';
  static const _path = '/reverse';

  @override
  Future<LocationSuggestion?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https(_host, _path, {
      'lat': latitude.toStringAsFixed(7),
      'lon': longitude.toStringAsFixed(7),
      'format': 'jsonv2',
      'addressdetails': '1',
      'zoom': '18',
    });

    try {
      final response = await _client
          .get(uri, headers: {
            'Accept': 'application/json',
            'User-Agent': 'Gota/0.2 mobile',
          })
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) throw const ReverseGeocodingException();

      final body = jsonDecode(response.body);
      if (body is! Map) throw const ReverseGeocodingException();

      final suggestion = _parse(
        Map<String, dynamic>.from(body),
        latitude,
        longitude,
      );

      // Una respuesta sin ningún texto útil se trata igual que "sin sugerencia":
      // el caller no muestra tarjeta ni pre-popula municipio/sector.
      return (suggestion.incomplete && suggestion.displayText == null)
          ? null
          : suggestion;
    } on ReverseGeocodingException {
      rethrow;
    } on TimeoutException {
      throw const ReverseGeocodingException();
    } on SocketException {
      throw const ReverseGeocodingException();
    } on Exception {
      throw const ReverseGeocodingException();
    }
  }

  static LocationSuggestion _parse(
    Map<String, dynamic> raw,
    double latitude,
    double longitude,
  ) {
    final addr = raw['address'] is Map
        ? Map<String, dynamic>.from(raw['address'] as Map)
        : <String, dynamic>{};

    String? t(dynamic v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;

    final locality = t(addr['neighbourhood']) ?? t(addr['quarter']);
    final city = t(addr['city']) ?? t(addr['town']) ?? t(addr['village']);
    final municipality = t(addr['county']) ?? t(addr['municipality']);
    final state = t(addr['state']);
    final display = t(raw['display_name']);

    return LocationSuggestion(
      latitude: latitude,
      longitude: longitude,
      provider: 'nominatim',
      displayText: display,
      locality: locality,
      neighborhood: t(addr['neighbourhood']),
      city: city,
      municipality: municipality,
      state: state,
      incomplete: display == null &&
          locality == null &&
          city == null &&
          municipality == null,
    );
  }
}

final reverseGeocodingServiceProvider = Provider<ReverseGeocodingService>(
  (_) => NominatimReverseGeocodingService(),
);
