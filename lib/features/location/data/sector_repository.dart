import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/errors/app_exception.dart';
import '../../../core/network/gota_database.dart';
import '../../../core/network/network_providers.dart';
import '../../../shared/models/sector.dart';

abstract class SectorRepository {
  Future<List<Sector>> getByMunicipality(String municipalityId);
}

class SupabaseSectorRepository implements SectorRepository {
  SupabaseSectorRepository(this._database);

  final GotaDatabase _database;

  @override
  Future<List<Sector>> getByMunicipality(String municipalityId) async {
    try {
      final rows = await _database.fetchSectorsForMunicipality(municipalityId);
      return rows.map(Sector.fromJson).toList();
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

final sectorRepositoryProvider = Provider<SectorRepository>(
  (ref) => SupabaseSectorRepository(ref.watch(gotaDatabaseProvider)),
);
