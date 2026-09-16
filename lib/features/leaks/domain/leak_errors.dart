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
    super.userMessage =
        'El GPS parece estar apagado. Actívalo o usa '
        'ubicación manual.',
  ]);
}

class LocationUnavailableException extends LeakFlowException {
  const LocationUnavailableException([
    super.userMessage =
        'No pudimos obtener tu ubicación. Intenta de nuevo '
        'o usa ubicación manual.',
  ]);
}

class ReverseGeocodingException extends LeakFlowException {
  const ReverseGeocodingException([
    super.userMessage =
        'No pudimos obtener una sugerencia de ubicación. Puedes continuar.',
  ]);
}

class PhotoValidationException extends LeakFlowException {
  const PhotoValidationException(super.userMessage);
}

/// Cancelación explícita del selector (AUD-S2-14): no es un error visible.
class PhotoPickCanceledException extends LeakFlowException {
  const PhotoPickCanceledException([
    super.userMessage = 'No se seleccionó ninguna foto.',
  ]);
}

class PhotoUploadException extends LeakFlowException {
  const PhotoUploadException([
    super.userMessage = 'No pudimos subir tus fotos. Intenta de nuevo.',
  ]);
}

/// La limpieza de binarios temporales falló: nunca se oculta, para no
/// dejar archivos huérfanos en silencio.
class PhotoCleanupException extends LeakFlowException {
  const PhotoCleanupException([
    super.userMessage =
        'No pudimos limpiar las fotos temporales de este '
        'intento. Vuelve a intentarlo.',
  ]);
}

/// El backend (RPC `create_leak_report`) rechazó la creación del reporte.
/// El mensaje ya viene redactado para el usuario final.
class ReportCreationException extends LeakFlowException {
  const ReportCreationException(super.userMessage);
}

/// El backend limitó la acción por frecuencia (`RATE_LIMIT_EXCEEDED`):
/// el mensaje (con la hora de reintento) ya viene redactado para el
/// usuario final.
class ReportRateLimitException extends LeakFlowException {
  const ReportRateLimitException(super.userMessage);
}
