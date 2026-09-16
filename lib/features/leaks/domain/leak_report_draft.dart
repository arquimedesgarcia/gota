import 'location_source.dart';

/// Coordenadas y fuente de la ubicación de un reporte.
class SelectedLocation {
  const SelectedLocation({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final LocationSource source;
  final double? accuracyMeters;

  bool get isGps => source == LocationSource.gps;
}

/// Foto lista para revisión/subida.
class PreparedPhoto {
  const PreparedPhoto({
    required this.id,
    required this.originalPath,
    required this.compressedPath,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
  });

  /// Identificador local (uuid v4 simple) para reordenar/eliminar.
  final String id;
  final String originalPath;
  final String compressedPath;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
}

/// Estado completo del borrador antes de enviar.
class LeakReportDraft {
  const LeakReportDraft({
    this.location,
    this.photos = const [],
    this.municipalityId,
    this.sectorId,
    this.description,
  });

  final SelectedLocation? location;
  final List<PreparedPhoto> photos;
  final String? municipalityId;
  final String? sectorId;
  final String? description;

  LeakReportDraft copyWith({
    SelectedLocation? location,
    List<PreparedPhoto>? photos,
    String? municipalityId,
    String? sectorId,
    String? description,
  }) => LeakReportDraft(
    location: location ?? this.location,
    photos: photos ?? this.photos,
    municipalityId: municipalityId ?? this.municipalityId,
    sectorId: sectorId ?? this.sectorId,
    description: description ?? this.description,
  );

  bool get hasPhotos => photos.isNotEmpty;
}
