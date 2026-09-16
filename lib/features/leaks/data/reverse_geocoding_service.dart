import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/network/network_providers.dart';
import '../domain/leak_errors.dart';
import '../domain/location_suggestion.dart';

abstract class ReverseGeocodingService {
  Future<LocationSuggestion?> reverse({
    required double latitude,
    required double longitude,
  });
}

class SupabaseReverseGeocodingService implements ReverseGeocodingService {
  SupabaseReverseGeocodingService(this._client);

  final supabase.SupabaseClient _client;

  @override
  Future<LocationSuggestion?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _client.functions
          .invoke(
            'reverse-geocode',
            body: {'latitude': latitude, 'longitude': longitude},
          )
          .timeout(const Duration(seconds: 8));
      final data = response.data;
      if (data is! Map) return null;
      final suggestion = LocationSuggestion.fromJson(
        Map<String, dynamic>.from(data),
      );
      return suggestion.incomplete && suggestion.displayText == null
          ? null
          : suggestion;
    } on TimeoutException {
      throw const ReverseGeocodingException();
    } on SocketException {
      throw const ReverseGeocodingException();
    } on supabase.FunctionException {
      throw const ReverseGeocodingException();
    } on Exception {
      throw const ReverseGeocodingException();
    }
  }
}

final reverseGeocodingServiceProvider = Provider<ReverseGeocodingService>(
  (ref) => SupabaseReverseGeocodingService(ref.watch(supabaseClientProvider)),
);
