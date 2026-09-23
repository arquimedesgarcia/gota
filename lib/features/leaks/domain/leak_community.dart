/// Modelos del ciclo comunitario definido en Sprint 03:
/// validación de una fuga y confirmación comunitaria de resolución.
///
/// La autoridad de las reglas vive en el backend (RPC `validate_leak`,
/// `confirm_leak_resolution` y `get_leak_report_detail`); estos modelos solo
/// representan lo que el servidor devuelve.
library;

/// Resumen de un reporte para la lista de fugas (Inicio).
class LeakSummary {
  const LeakSummary({
    required this.id,
    required this.status,
    required this.validationCount,
    required this.resolutionConfirmationCount,
    required this.createdAt,
    this.resolvedAt,
    this.sectorName,
    this.municipalityName,
    this.description,
    this.latitude,
    this.longitude,
    this.sectorId,
    this.municipalityId,
  });

  factory LeakSummary.fromJson(Map<String, dynamic> json) => LeakSummary(
    id: (json['report_id'] as String?) ?? (json['id'] as String),
    status: json['status'] as String? ?? 'ACTIVE',
    validationCount: (json['validation_count'] as num?)?.toInt() ?? 0,
    resolutionConfirmationCount:
        (json['resolution_confirmation_count'] as num?)?.toInt() ?? 0,
    createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
    resolvedAt: _parseDate(json['resolved_at']),
    sectorName: _parseName(json, 'sector_name', 'sectors'),
    municipalityName: _parseName(json, 'municipality_name', 'municipalities'),
    description: json['description'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    sectorId: json['sector_id'] as String?,
    municipalityId: json['municipality_id'] as String?,
  );

  final String id;
  final String status;
  final int validationCount;
  final int resolutionConfirmationCount;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? sectorName;
  final String? municipalityName;
  final String? description;
  final double? latitude;
  final double? longitude;
  final String? sectorId;
  final String? municipalityId;

  bool get isResolved => status == 'RESOLVED';
  bool get hasCoordinates => latitude != null && longitude != null;
}

/// Detalle de un reporte + estado del usuario actual, tal como lo devuelve
/// la RPC `get_leak_report_detail`.
class LeakDetail {
  const LeakDetail({
    required this.id,
    required this.status,
    required this.validationCount,
    required this.resolutionConfirmationCount,
    required this.threshold,
    required this.createdAt,
    required this.latitude,
    required this.longitude,
    required this.isCreator,
    required this.isBlocked,
    required this.alreadyValidated,
    required this.alreadyConfirmed,
    this.resolvedAt,
    this.description,
    this.locationSource,
    this.municipalityName,
    this.sectorName,
    this.photoCount = 0,
  });

  factory LeakDetail.fromJson(Map<String, dynamic> json) => LeakDetail(
    id: json['report_id'] as String? ?? json['id'] as String? ?? '',
    status: json['status'] as String? ?? 'ACTIVE',
    validationCount: (json['validation_count'] as num?)?.toInt() ?? 0,
    resolutionConfirmationCount:
        (json['resolution_confirmation_count'] as num?)?.toInt() ?? 0,
    threshold: (json['threshold'] as num?)?.toInt() ?? 3,
    createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
    resolvedAt: _parseDate(json['resolved_at']),
    description: json['description'] as String?,
    locationSource: json['location_source'] as String?,
    municipalityName: json['municipality_name'] as String?,
    sectorName: json['sector_name'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
    isCreator: json['is_creator'] as bool? ?? false,
    isBlocked: json['is_blocked'] as bool? ?? false,
    alreadyValidated: json['already_validated'] as bool? ?? false,
    alreadyConfirmed: json['already_confirmed'] as bool? ?? false,
  );

  final String id;
  final String status;
  final int validationCount;
  final int resolutionConfirmationCount;

  /// Umbral de resolución vigente en el backend (`system_config.resolution`).
  final int threshold;

  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? description;
  final String? locationSource;
  final String? municipalityName;
  final String? sectorName;
  final double latitude;
  final double longitude;
  final int photoCount;

  final bool isCreator;
  final bool isBlocked;
  final bool alreadyValidated;
  final bool alreadyConfirmed;

  bool get isResolved => status == 'RESOLVED';

  /// B3: la fuga está validada cuando al menos 1 persona la confirmó.
  bool get isValidated => validationCount >= 1;

  /// Acciones disponibles según el estado devuelto por el servidor.
  bool get canValidate =>
      !isResolved && !isCreator && !alreadyValidated && !isBlocked;

  /// B3: confirmar resolución requiere que la fuga esté validada primero.
  bool get canConfirmResolution =>
      !isResolved && !alreadyConfirmed && !isBlocked && isValidated;
}

/// Resultado real de `validate_leak` / `confirm_leak_resolution`.
///
/// Solo se construye con una respuesta exitosa del backend: la UI no debe
/// anunciar nada antes (docs/FUNCTIONAL_SPEC.md §12).
class CommunityActionResult {
  const CommunityActionResult({
    required this.status,
    required this.validationCount,
    required this.resolutionConfirmationCount,
    required this.threshold,
    this.resolvedAt,
  });

  factory CommunityActionResult.fromJson(Map<String, dynamic> json) =>
      CommunityActionResult(
        status: json['status'] as String? ?? 'ACTIVE',
        validationCount: (json['validation_count'] as num?)?.toInt() ?? 0,
        resolutionConfirmationCount:
            (json['resolution_confirmation_count'] as num?)?.toInt() ?? 0,
        threshold: (json['threshold'] as num?)?.toInt() ?? 3,
        resolvedAt: _parseDate(json['resolved_at']),
      );

  final String status;
  final int validationCount;
  final int resolutionConfirmationCount;
  final int threshold;
  final DateTime? resolvedAt;

  bool get isResolved => status == 'RESOLVED';
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Extrae el nombre de un recurso embebido de PostgREST (`sectors(name)`),
/// que puede llegar como objeto, lista o null según la RLS del recurso.
String? _embeddedName(Object? value) {
  if (value is Map) return value['name'] as String?;
  if (value is List && value.isNotEmpty && value.first is Map) {
    return (value.first as Map)['name'] as String?;
  }
  return null;
}

String? _parseName(
  Map<String, dynamic> json,
  String directKey,
  String embeddedKey,
) {
  if (json[directKey] is String) return json[directKey] as String;
  return _embeddedName(json[embeddedKey]);
}
