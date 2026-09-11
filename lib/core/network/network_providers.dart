import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'gota_auth.dart';
import 'gota_community_database.dart';
import 'gota_database.dart';
import 'gota_storage.dart';

/// Cliente de Supabase.
///
/// Solo es seguro observarlo después de un [Supabase.initialize] exitoso,
/// garantizado por el bootstrap de `main.dart`.
final supabaseClientProvider = Provider<supabase.SupabaseClient>(
  (ref) => supabase.Supabase.instance.client,
);

final gotaAuthProvider = Provider<GotaAuth>(
  (ref) => SupabaseGotaAuth(ref.watch(supabaseClientProvider)),
);

final gotaDatabaseProvider = Provider<GotaDatabase>(
  (ref) => SupabaseGotaDatabase(ref.watch(supabaseClientProvider)),
);

final gotaStorageProvider = Provider<GotaStorage>(
  (ref) => SupabaseGotaStorage(ref.watch(supabaseClientProvider)),
);

/// Consultas y RPC del ciclo comunitario (Sprint 03).
final gotaCommunityDatabaseProvider = Provider<GotaCommunityDatabase>(
  (ref) => SupabaseGotaCommunityDatabase(ref.watch(supabaseClientProvider)),
);
