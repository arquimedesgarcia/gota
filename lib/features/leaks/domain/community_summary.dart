/// Resumen diario de actividad comunitaria para la tarjeta
/// "Hoy en tu comunidad" de Home (S10-C).
///
/// Solo dos métricas, ambas diarias (docs: definición funcional S10-C):
/// fugas reportadas hoy y fugas resueltas hoy. Sin acumulados históricos,
/// sin Water Events, sin validaciones.
library;

/// Resumen agregado de un día en un ámbito (sector o cobertura global).
///
/// `activeReported`/`activeValidated` son acumulados vigentes (no diarios):
/// fallas ACTIVE del ámbito divididas por el umbral de validación
/// comunitaria, mismas reglas visuales del mapa (docs/MIGRATION_NOTES.md).
class CommunitySummary {
  const CommunitySummary({
    required this.reportedToday,
    required this.resolvedToday,
    this.activeReported = 0,
    this.activeValidated = 0,
  });

  final int reportedToday;
  final int resolvedToday;
  final int activeReported;
  final int activeValidated;

  /// Total de fallas activas reportadas más validadas.
  int get activeTotal => activeReported + activeValidated;

  bool get isEmpty =>
      reportedToday == 0 &&
      resolvedToday == 0 &&
      activeReported == 0 &&
      activeValidated == 0;
}

/// Desplazamiento fijo de `America/Caracas` respecto a UTC.
///
/// Venezuela no observa horario de verano desde 2016 y usa UTC-4 todo el
/// año, por lo que el desplazamiento es una constante explícita y no un
/// cálculo de zona horaria del dispositivo.
const caracasUtcOffsetHours = -4;

/// Límites UTC de "hoy" en día calendario de Caracas para [nowUtc].
///
/// Ventana semiabierta `[startUtc, endUtc)`: incluye la medianoche de
/// Caracas y excluye la medianoche siguiente. Las consultas a Supabase
/// deben usar estos límites ya convertidos (nunca `DateTime.now()` local
/// contra timestamps UTC).
({DateTime startUtc, DateTime endUtc}) caracasDayBounds(DateTime nowUtc) {
  final caracasNow = nowUtc.add(
    const Duration(hours: caracasUtcOffsetHours),
  );
  final startUtc = DateTime.utc(
    caracasNow.year,
    caracasNow.month,
    caracasNow.day,
    -caracasUtcOffsetHours,
  );
  return (startUtc: startUtc, endUtc: startUtc.add(const Duration(days: 1)));
}
