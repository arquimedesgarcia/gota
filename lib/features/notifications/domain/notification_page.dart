import 'water_notification.dart';

/// Página de la bandeja de notificaciones: items y cursor para la siguiente
/// página. Es un detalle de la paginación keyset que el dominio solo pasa de
/// vuelta tal cual.
class NotificationInboxPage {
  const NotificationInboxPage({required this.items, this.nextBeforeIso});

  final List<WaterNotification> items;

  /// `created_at` ISO (UTC) del último item de la página, para pedir la
  /// siguiente con `.lt()`. Nulo cuando la página vino incompleta (no hay
  /// más).
  final String? nextBeforeIso;
}
