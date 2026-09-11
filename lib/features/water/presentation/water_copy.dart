/// Microcopy del ciclo de eventos de agua centralizado (docs/UX_SPEC.md §9:
/// el copy no se inventa pantalla por pantalla). Tono comunitario, directo,
/// poco texto.
abstract final class WaterCopy {
  static const screenTitle = 'Agua';
  static const summaryTitle = 'Resumen';
  static const historyTitle = 'Historial';
  static const emptyList = 'Sin datos todavía';
  static const retry = 'Reintentar';
  static const loadMore = 'Cargar más';
  static const noData = 'Sin datos suficientes';

  // Registro (pasos).
  static const stepType = '¿Qué pasó con el agua?';
  static const stepMunicipality = 'Municipio';
  static const stepSector = 'Sector';
  static const stepTime = 'Hora del evento';
  static const stepComment = 'Comentario (opcional)';
  static const stepReview = 'Revisar';
  static const commentHelper = 'El comentario es opcional.';
  static const changeTime = 'Cambiar hora';
  static const next = 'Siguiente';
  static const back = 'Atrás';
  static const confirm = 'Confirmar';

  // Resumen (estadísticas).
  static const totalArrivals = 'Llegadas';
  static const totalDepartures = 'Salidas';
  static const lastArrival = 'Última llegada';
  static const lastDeparture = 'Última salida';
  static const averageSupply = 'Suministro promedio';
  static const averageOutage = 'Interrupción promedio';

  // Detalle / validación.
  static const validate = 'Validar';
  static const cannotValidateOwn = 'No puedes validar tu propio evento.';
  static const alreadyValidated = 'Ya validaste este evento.';
  static const blocked = 'Tu acceso está bloqueado.';
  static const validatedSnack = 'Validación registrada.';
  static const registeredSnack = 'Evento registrado.';
  static const registeredSnackBody =
      'Gracias por compartirlo con tu comunidad.';

  // Errores.
  static const loadError = 'No pudimos cargar el historial. Intenta de nuevo.';
  static const actionError = 'No pudimos completar la acción. Intenta de nuevo.';
  static const registerError = 'No pudimos registrar el evento. Intenta de nuevo.';

  static String validationCount(int count) =>
      count == 1 ? '1 validación' : '$count validaciones';

  /// Duración corta: 'Xh Ym', 'Ym' si dura menos de una hora, '—' si nula.
  static String duration(Duration? duration) {
    if (duration == null) return '—';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) return '${duration.inMinutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
}
