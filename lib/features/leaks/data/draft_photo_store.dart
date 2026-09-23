import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Gestiona las fotos durables del borrador: copia desde el cache de la app
/// (que el sistema puede reclamar) a un directorio en ApplicationSupport
/// (que persiste entre sesiones).
abstract class DraftPhotoStore {
  /// Copia [compressedPath] a una ubicación durable identificada por
  /// [photoId]. Idempotente: si el origen ya ES el destino, no hace nada.
  /// Devuelve la ruta durable.
  Future<String> copyToDurable({
    required String compressedPath,
    required String photoId,
  });

  /// Comprueba si [durablePath] existe en el almacenamiento durable.
  Future<bool> exists(String durablePath);

  /// Borra todos los archivos de fotos durables de este borrador.
  Future<void> clearAll();
}

class FileDraftPhotoStore implements DraftPhotoStore {
  static const _dirName = 'report_draft_photos';

  Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(path.join(support.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String> copyToDurable({
    required String compressedPath,
    required String photoId,
  }) async {
    final dir = await _dir();
    final dst = path.join(dir.path, '$photoId.jpg');
    if (compressedPath == dst) return dst;
    await File(compressedPath).copy(dst);
    return dst;
  }

  @override
  Future<bool> exists(String durablePath) => File(durablePath).exists();

  @override
  Future<void> clearAll() async {
    final dir = await _dir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }
}

class InMemoryDraftPhotoStore implements DraftPhotoStore {
  final Map<String, String> _durableByPhotoId = {};

  @override
  Future<String> copyToDurable({
    required String compressedPath,
    required String photoId,
  }) async {
    final durable = '/memory/draft_photos/$photoId.jpg';
    _durableByPhotoId[photoId] = durable;
    return durable;
  }

  @override
  Future<bool> exists(String durablePath) async =>
      _durableByPhotoId.containsValue(durablePath);

  @override
  Future<void> clearAll() async => _durableByPhotoId.clear();
}

final draftPhotoStoreProvider =
    Provider<DraftPhotoStore>((ref) => FileDraftPhotoStore());
