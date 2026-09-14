import '../../water/domain/water_event_type.dart';

/// Notificación de la bandeja del usuario (Sprint 06). `type` reutiliza el
/// enum del ciclo de agua: es el mismo dominio (`WATER_ARRIVED` /
/// `WATER_LEFT`).
class WaterNotification {
  const WaterNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    required this.eventTime,
    this.eventId,
    this.sectorName,
    this.municipalityName,
  });

  final String id;
  final WaterEventType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime eventTime;
  final String? eventId;
  final String? sectorName;
  final String? municipalityName;

  bool get isUnread => readAt == null;

  WaterNotification copyWith({DateTime? readAt}) => WaterNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
    eventTime: eventTime,
    eventId: eventId,
    sectorName: sectorName,
    municipalityName: municipalityName,
  );

  factory WaterNotification.fromJson(Map<String, dynamic> json) {
    // supabase_flutter devuelve el embed `water_events` como lista o como
    // mapa según la relación; se aceptan ambas formas.
    final event = _firstAsMap(json['water_events']);
    final sector = _firstAsMap(event?['sectors']);
    final municipality = _firstAsMap(event?['municipalities']);

    return WaterNotification(
      id: json['id'] as String,
      type: WaterEventType.fromWire(json['type'] as String),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      readAt: _parseDate(json['read_at']),
      eventTime: _parseDate(event?['event_time']) ?? DateTime.now(),
      eventId: event?['id'] as String?,
      sectorName: sector?['name'] as String?,
      municipalityName: municipality?['name'] as String?,
    );
  }
}

Map<String, dynamic>? _firstAsMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return null;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
