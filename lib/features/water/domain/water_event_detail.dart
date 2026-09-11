import 'water_event_type.dart';

/// Detalle de un evento de agua + estado del usuario actual, tal como lo
/// devuelve la RPC `get_water_event_detail`. No incluye `created_by`
/// (el backend jamás lo expone).
class WaterEventDetail {
  const WaterEventDetail({
    required this.id,
    required this.type,
    required this.eventTime,
    required this.validationCount,
    required this.createdAt,
    required this.isCreator,
    required this.isBlocked,
    required this.alreadyValidated,
    this.comment,
    this.updatedAt,
    this.municipalityId,
    this.municipalityName,
    this.sectorId,
    this.sectorName,
  });

  factory WaterEventDetail.fromJson(Map<String, dynamic> json) =>
      WaterEventDetail(
        id: json['event_id'] as String? ?? json['id'] as String? ?? '',
        type: json['event_type'] == null
            ? WaterEventType.arrived
            : WaterEventType.fromWire(json['event_type'] as String),
        eventTime: _parseDate(json['event_time']) ?? DateTime.now(),
        comment: json['comment'] as String?,
        validationCount: (json['validation_count'] as num?)?.toInt() ?? 0,
        createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(json['updated_at']),
        municipalityId: json['municipality_id'] as String?,
        municipalityName: json['municipality_name'] as String?,
        sectorId: json['sector_id'] as String?,
        sectorName: json['sector_name'] as String?,
        isCreator: json['is_creator'] as bool? ?? false,
        isBlocked: json['is_blocked'] as bool? ?? false,
        alreadyValidated: json['already_validated'] as bool? ?? false,
      );

  final String id;
  final WaterEventType type;
  final DateTime eventTime;
  final String? comment;
  final int validationCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? municipalityId;
  final String? municipalityName;
  final String? sectorId;
  final String? sectorName;

  final bool isCreator;
  final bool isBlocked;
  final bool alreadyValidated;

  /// Acción disponible según el estado devuelto por el servidor.
  bool get canValidate => !isCreator && !alreadyValidated && !isBlocked;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
