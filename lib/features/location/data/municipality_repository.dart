import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_database.dart';
import '../../../core/network/network_providers.dart';
import '../../../shared/models/municipality.dart';

abstract class MunicipalityRepository {
  Future<List<Municipality>> getActive();
}

class SupabaseMunicipalityRepository implements MunicipalityRepository {
  SupabaseMunicipalityRepository(this._database);

  final GotaDatabase _database;

  @override
  Future<List<Municipality>> getActive() async {
    try {
      final rows = await _database.fetchActiveMunicipalities();
      return rows.map(Municipality.fromJson).toList();
    } on AppException {
      rethrow;
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on supabase.PostgrestException {
      throw const QueryException();
    }
  }
}

final municipalityRepositoryProvider = Provider<MunicipalityRepository>(
  (ref) => SupabaseMunicipalityRepository(ref.watch(gotaDatabaseProvider)),
);
