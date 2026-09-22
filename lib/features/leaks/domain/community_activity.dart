/// Modelo de la tarjeta "Actividad reciente" del Home (docs/FUNCTIONAL_SPEC.md
/// §2): el último evento comunitario a nivel global sobre fallas.
///
/// La autoridad vive en el backend (RPC `get_latest_community_activity`); este
/// modelo solo representa la única fila (o ninguna) que el servidor devuelve.
library;

/// Tipo de evento de actividad comunitaria sobre una falla.
enum CommunityActivityType {
  reported,
  validated,
  resolved;

  /// Parseo tolerante desde el texto del backend. Un valor desconocido es un
  /// error de formato (no un evento silencioso): lanza [FormatException] para
  /// que el repositorio lo traduzca a un error de dominio.
  static CommunityActivityType fromText(String? value) {
    switch (value) {
      case 'REPORTED':
        return CommunityActivityType.reported;
      case 'VALIDATED':
        return CommunityActivityType.validated;
      case 'RESOLVED':
        return CommunityActivityType.resolved;
    }
    throw FormatException('activity_type desconocido: $value');
  }
}

/// Último evento comunitario global (REPORTED / VALIDATED / RESOLVED) sobre
/// una falla, con el estado actual de esa falla para pintar la fila.
class CommunityActivity {
  const CommunityActivity({
    required this.type,
    required this.at,
    required this.reportId,
    required this.status,
    required this.validationCount,
    required this.resolutionConfirmationCount,
    required this.createdAt,
    this.resolvedAt,
    this.description,
    this.sectorId,
    this.sectorName,
    this.municipalityId,
    this.municipalityName,
  });

  factory CommunityActivity.fromJson(Map<String, dynamic> json) =>
      CommunityActivity(
        type: CommunityActivityType.fromText(json['activity_type'] as String?),
        at: _parseDate(json['at']) ?? DateTime.now(),
        reportId: json['report_id'] as String,
        status: json['status'] as String? ?? 'ACTIVE',
        validationCount: (json['validation_count'] as num?)?.toInt() ?? 0,
        resolutionConfirmationCount:
            (json['resolution_confirmation_count'] as num?)?.toInt() ?? 0,
        createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
        resolvedAt: _parseDate(json['resolved_at']),
        description: json['description'] as String?,
        sectorId: json['sector_id'] as String?,
        sectorName: json['sector_name'] as String?,
        municipalityId: json['municipality_id'] as String?,
        municipalityName: json['municipality_name'] as String?,
      );

  final CommunityActivityType type;

  /// Momento del evento: `created_at` (REPORTED), `created_at` de la N-ésima
  /// validación (VALIDATED) o `resolved_at` (RESOLVED).
  final DateTime at;
  final String reportId;

  /// Estado ACTUAL de la falla ('ACTIVE' | 'RESOLVED'), no el tipo de evento.
  final String status;
  final int validationCount;
  final int resolutionConfirmationCount;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? description;
  final String? sectorId;
  final String? sectorName;
  final String? municipalityId;
  final String? municipalityName;

  bool get isResolved => status == 'RESOLVED';

  /// Mismo formato `sector · municipio` que la fila del listado de fallas.
  String get placeLabel =>
      [sectorName, municipalityName].whereType<String>().join(' · ');
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
