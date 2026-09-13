/// Errores del ciclo de notificaciones (Sprint 06).
///
/// Mismo contrato que los errores de agua: cada error lleva un
/// `userMessage` en español listo para mostrar.
class NotificationException implements Exception {
  const NotificationException(this.userMessage);

  /// Mensaje amigable para el usuario final.
  final String userMessage;

  @override
  String toString() => 'NotificationException: $userMessage';
}

/// El backend rechazó los datos (`VALIDATION_ERROR` o `NOT_FOUND`); el
/// mensaje lo redacta el backend.
class NotificationValidationException extends NotificationException {
  const NotificationValidationException([
    super.userMessage = 'Revisa los datos e intenta de nuevo.',
  ]);
}

/// El usuario no puede ejecutar la acción (cuenta bloqueada). El mensaje lo
/// redacta el backend.
class NotificationForbiddenException extends NotificationException {
  const NotificationForbiddenException([
    super.userMessage = 'No puedes realizar esta acción.',
  ]);
}
