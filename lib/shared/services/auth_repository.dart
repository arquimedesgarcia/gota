import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../core/errors/app_exception.dart';
import '../../core/network/gota_auth.dart';
import '../../core/network/gota_database.dart';
import '../../core/network/network_providers.dart';
import '../models/app_user.dart';

/// Garantiza que existe una sesión anónima válida y un perfil `app_users`.
abstract class AuthRepository {
  Future<AppUser> ensureSessionAndProfile();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth, this._database);

  final GotaAuth _auth;
  final GotaDatabase _database;

  @override
  Future<AppUser> ensureSessionAndProfile() async {
    try {
      if (_auth.currentSession() == null) {
        await _auth.signInAnonymously();
      }
    } on AppException {
      rethrow;
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on supabase.AuthException {
      throw const AuthException();
    }

    try {
      final row = await _database.ensureAppUser();
      return AppUser.fromJson(row);
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

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(
    ref.watch(gotaAuthProvider),
    ref.watch(gotaDatabaseProvider),
  ),
);
