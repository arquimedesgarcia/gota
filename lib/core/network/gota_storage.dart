import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Abstracción sobre Supabase Storage.
///
/// Es la costura de testeo de la subida/limpieza de fotografías: los
/// repositorios dependen de esta interfaz, nunca del cliente directamente
/// (docs/ARCHITECTURE.md §4). El cliente solo usa su clave pública y su
/// propia sesión; nunca `service_role`.
abstract class GotaStorage {
  /// Sube [bytes] a [path] dentro de [bucket] con el [contentType] dado.
  Future<void> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  });

  /// Elimina los [paths] indicados del [bucket].
  ///
  /// Solo puede eliminar archivos cuya ruta pertenezca a la carpeta del
  /// usuario autenticado (política RLS del bucket).
  Future<void> remove({required String bucket, required List<String> paths});

  /// Lista los nombres de archivo bajo [prefix] dentro de [bucket].
  Future<List<String>> list({required String bucket, required String prefix});
}

class SupabaseGotaStorage implements GotaStorage {
  SupabaseGotaStorage(this._client);

  final supabase.SupabaseClient _client;

  @override
  Future<void> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: supabase.FileOptions(
            contentType: contentType,
            upsert: false,
          ),
        );
  }

  @override
  Future<void> remove({
    required String bucket,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) return;
    await _client.storage.from(bucket).remove(paths);
  }

  @override
  Future<List<String>> list({
    required String bucket,
    required String prefix,
  }) async {
    final files = await _client.storage.from(bucket).list(path: prefix);
    return files.map((f) => f.name).toList();
  }
}
