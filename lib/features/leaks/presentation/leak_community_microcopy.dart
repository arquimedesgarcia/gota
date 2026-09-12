/// Microcopy del ciclo comunitario centralizado (docs/UX_SPEC.md §9:
/// el copy no se inventa pantalla por pantalla).
abstract final class LeakCommunityCopy {
  static const screenTitle = 'Fuga';
  static const activeStatus = 'Fuga activa';
  static const resolvedStatus = 'Fuga resuelta';
  static const beFirstValidator = 'Sé la primera persona en validar esta fuga';
  static const validating = 'La comunidad lo está validando';
  static const alreadyValidated = 'Ya validaste este reporte';
  static const cannotValidateOwn = 'No puedes validar tu propio reporte';
  static const resolveQuestion = '¿La fuga fue resuelta?';
  static const validateButton = 'Validar fuga';
  static const confirmButton = 'Sí, fue resuelta';
  static const alreadyConfirmed = 'Ya confirmaste la resolución';
  static const blocked = 'Tu acceso está bloqueado';
  static const loadError = 'No pudimos cargar esta fuga. Intenta de nuevo.';
  static const actionError =
      'No pudimos completar la acción. Intenta de nuevo.';
  static const listError = 'No pudimos cargar las fugas cercanas.';
  static const emptyList = 'Sin datos todavía';
  static const retry = 'Reintentar';

  static String validationCount(int count) =>
      count == 1 ? '1 validación' : '$count validaciones';

  /// Progreso comunitario de resolución (docs/UX_SPEC.md §6).
  static String confirmationProgress(int confirmed, int threshold) =>
      '$confirmed de $threshold personas han confirmado que la fuga fue '
      'resuelta.';

  static String photoCount(int count) => count == 1 ? '1 foto' : '$count fotos';

  static String resolvedAt(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return 'Resuelta el $day/$month/${local.year}';
  }

  /// Mensaje tras una validación confirmada por el backend.
  static String validatedMessage(int validationCount) =>
      'Fuga validada. ${LeakCommunityCopy.validationCount(validationCount)}.';

  /// Mensaje tras confirmar resolución. Solo anuncia la resolución si el
  /// backend respondió RESOLVED (docs/FUNCTIONAL_SPEC.md §12).
  static String confirmedMessage({
    required bool resolved,
    required int missing,
  }) {
    if (resolved) return 'La comunidad confirmó que la fuga fue resuelta.';
    if (missing == 1) {
      return 'Gracias. Falta 1 confirmación para marcarla como resuelta.';
    }
    return 'Gracias. Faltan $missing confirmaciones para marcarla como '
        'resuelta.';
  }
}
