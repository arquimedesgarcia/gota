/// Errores del ciclo de eventos de agua (Sprint 04).
///
/// Mismo contrato que los errores de fugas: cada error lleva un
/// `userMessage` en español listo para mostrar (docs/UX_SPEC.md §8).
class WaterException implements Exception {
  const WaterException(this.userMessage);

  /// Mensaje amigable para el usuario final.
  final String userMessage;

  @override
  String toString() => 'WaterException: $userMessage';
}

/// El backend rechazó los datos (`VALIDATION_ERROR`, `INVALID_SECTOR` o
/// `NOT_FOUND`); el mensaje lo redacta el backend.
class WaterValidationException extends WaterException {
  const WaterValidationException([
    super.userMessage = 'Revisa los datos del evento e intenta de nuevo.',
  ]);
}

/// El usuario ya validó este evento (`DUPLICATE_ACTION`): es un resultado
/// determinista del backend, no un fallo de red.
class DuplicateValidationException extends WaterException {
  const DuplicateValidationException([
    super.userMessage = 'Ya validaste este evento.',
  ]);
}

/// El usuario no puede ejecutar la acción (creador del evento o cuenta
/// bloqueada). El mensaje lo redacta el backend.
class WaterForbiddenException extends WaterException {
  const WaterForbiddenException([
    super.userMessage = 'No puedes realizar esta acción.',
  ]);
}

/// El evento no existe o no es accesible (`NOT_FOUND`).
class WaterNotFoundException extends WaterException {
  const WaterNotFoundException([
    super.userMessage = 'No encontramos este evento.',
  ]);
}
