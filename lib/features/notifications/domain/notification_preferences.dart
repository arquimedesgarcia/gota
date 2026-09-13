/// Preferencias de notificación del usuario (docs/DATA_MODEL.md, Sprint 06).
/// Hay como máximo una fila por usuario (`user_id` es la clave primaria).
class NotificationPreferences {
  const NotificationPreferences({
    required this.userId,
    this.preferredSectorId,
    required this.waterNotificationsEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String? preferredSectorId;
  final bool waterNotificationsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      userId: json['user_id'] as String,
      preferredSectorId: json['preferred_sector_id'] as String?,
      waterNotificationsEnabled:
          json['water_notifications_enabled'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
