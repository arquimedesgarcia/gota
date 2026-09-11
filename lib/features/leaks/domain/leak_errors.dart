/// Errores específicos del flujo de Reportar fuga (Sprint 02).
///
/// [AppException] es sealed dentro de core; estas clases replican su
/// contrato (`userMessage` en español) para mantener el patrón de UI
/// (`error is AppException ? error.userMessage : ...`). En un sprint
/// posterior se unificarán abriendo el sello o moviéndolas a core.
class LeakFlowException implements Exception {
  const LeakFlowException(this.userMessage);

  /// Mensaje amigable para el usuario final (UX_SPEC §8).
  final String userMessage;

  @override
  String toString() => 'LeakFlowException: $userMessage';
}

class LocationPermissionDeniedException extends LeakFlowException {
  const LocationPermissionDeniedException([
    super.userMessage =
        'No tenemos permiso para usar tu GPS. Puedes continuar con '
        'ubicación manual.',
  ]);
}

class LocationServiceOffException extends LeakFlowException {
  const LocationServiceOffException([
    super.userMessage = 'El GPS parece estar apagado. Actívalo o usa '
        'ubicación manual.',
  ]);
}

class LocationUnavailableException extends LeakFlowException {
  const LocationUnavailableException([
    super.userMessage = 'No pudimos obtener tu ubicación. Intenta de nuevo '
        'o usa ubicación manual.',
  ]);
}

class PhotoValidationException extends LeakFlowException {
  const PhotoValidationException(super.userMessage);
}

class PhotoUploadException extends LeakFlowException {
  const PhotoUploadException([
    super.userMessage = 'No pudimos subir tus fotos. Intenta de nuevo.',
  ]);
}
