import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Snapshot persistible de un borrador de reporte. Versionado para
/// detectar cambios de esquema y purgar snapshots incompatibles.
class PhotoSnapshot {
  const PhotoSnapshot({
    required this.id,
    required this.compressedPath,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.originalPath,
  });

  final String id;

  /// Ruta durable (en report_draft_photos/), no la ruta de cache original.
  final String compressedPath;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
  final String originalPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'compressedPath': compressedPath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'width': width,
        'height': height,
        'originalPath': originalPath,
      };

  static PhotoSnapshot fromJson(Map<String, dynamic> json) => PhotoSnapshot(
        id: json['id'] as String,
        compressedPath: json['compressedPath'] as String,
        mimeType: json['mimeType'] as String,
        sizeBytes: json['sizeBytes'] as int,
        width: json['width'] as int,
        height: json['height'] as int,
        originalPath: json['originalPath'] as String,
      );
}

class LeakDraftSnapshot {
  static const currentSchemaVersion = 1;

  const LeakDraftSnapshot({
    required this.schemaVersion,
    required this.savedAt,
    required this.stepIndex,
    this.latitude,
    this.longitude,
    this.locationSource,
    this.accuracyMeters,
    this.municipalityId,
    this.sectorId,
    this.description,
    this.photos = const [],
  });

  final int schemaVersion;
  final DateTime savedAt;

  /// Índice en `ReportStep.values`.
  final int stepIndex;
  final double? latitude;
  final double? longitude;

  /// `LocationSource.name` ('gps' o 'manual').
  final String? locationSource;
  final double? accuracyMeters;
  final String? municipalityId;
  final String? sectorId;
  final String? description;
  final List<PhotoSnapshot> photos;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'savedAt': savedAt.toIso8601String(),
        'stepIndex': stepIndex,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (locationSource != null) 'locationSource': locationSource,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (municipalityId != null) 'municipalityId': municipalityId,
        if (sectorId != null) 'sectorId': sectorId,
        if (description != null) 'description': description,
        'photos': photos.map((p) => p.toJson()).toList(),
      };

  static LeakDraftSnapshot fromJson(Map<String, dynamic> json) =>
      LeakDraftSnapshot(
        schemaVersion: json['schemaVersion'] as int,
        savedAt: DateTime.parse(json['savedAt'] as String),
        stepIndex: json['stepIndex'] as int,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        locationSource: json['locationSource'] as String?,
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        municipalityId: json['municipalityId'] as String?,
        sectorId: json['sectorId'] as String?,
        description: json['description'] as String?,
        photos: (json['photos'] as List<dynamic>? ?? [])
            .map((e) => PhotoSnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

abstract class DraftStore {
  /// Lee el snapshot persistido. Devuelve `null` si no hay nada.
  /// Devuelve `null` (no lanza) si el archivo existe pero está corrompido.
  Future<LeakDraftSnapshot?> read();

  /// Escritura atómica: `.tmp` + rename.
  Future<void> write(LeakDraftSnapshot snapshot);

  Future<void> clear();
}

class FileDraftStore implements DraftStore {
  static const _fileName = 'report_draft.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(path.join(dir.path, _fileName));
  }

  @override
  Future<LeakDraftSnapshot?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) return null;
    return LeakDraftSnapshot.fromJson(decoded);
  }

  @override
  Future<void> write(LeakDraftSnapshot snapshot) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(snapshot.toJson()));
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final tmp = File('${file.path}.tmp');
    if (await tmp.exists()) await tmp.delete();
  }
}

class InMemoryDraftStore implements DraftStore {
  LeakDraftSnapshot? _snapshot;

  @override
  Future<LeakDraftSnapshot?> read() async => _snapshot;

  @override
  Future<void> write(LeakDraftSnapshot snapshot) async => _snapshot = snapshot;

  @override
  Future<void> clear() async => _snapshot = null;
}

final draftStoreProvider = Provider<DraftStore>((ref) => FileDraftStore());
