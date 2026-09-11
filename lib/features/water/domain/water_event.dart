import '../../../core/network/gota_water_database.dart';
import 'water_event_type.dart';

/// Resumen de un evento de agua para el historial y las tarjetas de la
/// pestaña Agua. La autoridad de las reglas vive en el backend; este modelo
/// solo representa lo que el servidor devuelve.
class WaterEventSummary {
  const WaterEventSummary({
    required this.id,
    required this.type,
    required this.eventTime,
    required this.validationCount,
    required this.createdAt,
    this.comment,
    this.municipalityId,
    this.municipalityName,
    this.sectorId,
    this.sectorName,
  });

  factory WaterEventSummary.fromJson(Map<String, dynamic> json) =>
      WaterEventSummary(
        id: json['id'] as String? ?? json['event_id'] as String? ?? '',
        type: json['event_type'] == null
            ? WaterEventType.arrived
            : WaterEventType.fromWire(json['event_type'] as String),
        eventTime: _parseDate(json['event_time']) ?? DateTime.now(),
        comment: json['comment'] as String?,
        validationCount: (json['validation_count'] as num?)?.toInt() ?? 0,
        createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
        municipalityId: json['municipality_id'] as String?,
        municipalityName: _embeddedName(json['municipalities']),
        sectorId: json['sector_id'] as String?,
        sectorName: _embeddedName(json['sectors']),
      );

  final String id;
  final WaterEventType type;
  final DateTime eventTime;
  final String? comment;
  final int validationCount;
  final DateTime createdAt;
  final String? municipalityId;
  final String? municipalityName;
  final String? sectorId;
  final String? sectorName;
}

/// Página del historial de eventos con paginación keyset: [nextCursor] es el
/// cursor derivado del último evento cuando la página llegó llena; si vino
/// incompleta, no hay más páginas.
class WaterEventsPage {
  const WaterEventsPage({required this.events, this.nextCursor});

  final List<WaterEventSummary> events;
  final WaterEventCursor? nextCursor;

  bool get hasMore => nextCursor != null;
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
