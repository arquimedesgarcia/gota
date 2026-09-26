/// Microcopy de la pantalla de inicio centralizado (docs/UX_SPEC.md §9).
abstract final class HomeCopy {
  // Tarjeta de resumen comunitario.
  static const communitySummaryTitle = 'Cobertura del piloto';
  static const communitySummaryLoading = 'Cargando actividad…';
  static const communitySummaryError = 'No pudimos cargar la actividad de hoy.';
  static const communitySummaryRetry = 'Reintentar';

  // Tarjeta de estado del agua.
  static const waterMetricLabel = 'Agua en tu sector';
  static const waterNoInfo = 'Sin información del agua';
  static const waterNoSectorCta =
      'Selecciona tu sector para ver el estado del agua en tu zona';
}
