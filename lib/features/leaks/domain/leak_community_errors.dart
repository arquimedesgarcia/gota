/// Errores del ciclo comunitario (validación y resolución, Sprint 03).
///
/// Mismo contrato que [LeakFlowException] de Sprint 02: cada error lleva
/// un `userMessage` en español listo para mostrar (docs/UX_SPEC.md §8).
class LeakCommunityException implements Exception {
  const LeakCommunityException(this.userMessage);

  /// Mensaje amigable para el usuario final.
  final String userMessage;

  @override
  String toString() => 'LeakCommunityException: $userMessage';
}

/// El backend confirmó que este usuario ya ejecutó la acción
/// (`DUPLICATE_ACTION`): no es un fallo de red, sino un resultado de
/// dominio determinista y sin efectos sobre los contadores (REQ-042 /
/// REQ-052).
class DuplicateCommunityActionException extends LeakCommunityException {
  const DuplicateCommunityActionException([
    super.userMessage = 'Ya realizaste esta acción.',
  ]);
}

/// El reporte no existe o no es accesible (`NOT_FOUND`).
class LeakReportNotFoundException extends LeakCommunityException {
  const LeakReportNotFoundException([
    super.userMessage = 'No encontramos esta fuga. Puede haber sido eliminada.',
  ]);
}

/// El reporte ya está RESOLVED y no acepta nuevas acciones (`REPORT_ALREADY_RESOLVED`).
class LeakReportResolvedException extends LeakCommunityException {
  const LeakReportResolvedException([
    super.userMessage =
        'Esta fuga ya fue marcada como resuelta por la comunidad.',
  ]);
}

/// El usuario no puede ejecutar la acción (creador de la fuga o cuenta
/// bloqueada). El mensaje lo redacta el backend.
class LeakCommunityForbiddenException extends LeakCommunityException {
  const LeakCommunityForbiddenException([
    super.userMessage = 'No puedes realizar esta acción.',
  ]);
}

/// La sesión no está activa (`UNAUTHORIZED`).
class LeakCommunityUnauthorizedException extends LeakCommunityException {
  const LeakCommunityUnauthorizedException([
    super.userMessage =
        'Tu sesión no está activa. Cierra y abre la app de nuevo.',
  ]);
}

/// El backend limitó la acción por frecuencia (`RATE_LIMIT_EXCEEDED`):
/// el mensaje (con la hora de reintento) ya viene redactado para el
/// usuario final.
class LeakCommunityRateLimitException extends LeakCommunityException {
  const LeakCommunityRateLimitException(super.userMessage);
}
