import 'water_event.dart';
import 'water_event_type.dart';

/// Estadísticas DESCRIPTIVAS sobre los eventos de agua observados
/// (REQ-077: sin predicción ni tendencias). Solo se calculan con los pares
/// consecutivos dentro del mismo sector; sin pares completos los promedios
/// son nulos y la UI muestra 'Sin datos suficientes'.
class WaterStatistics {
  const WaterStatistics({
    required this.totalEvents,
    required this.arrivedCount,
    required this.leftCount,
    required this.supplyPairCount,
    required this.outagePairCount,
    this.lastArrival,
    this.lastDeparture,
    this.averageSupplyDuration,
    this.averageOutageDuration,
  });

  final int totalEvents;
  final int arrivedCount;
  final int leftCount;

  /// Mayor `event_time` entre eventos de llegada / salida.
  final DateTime? lastArrival;
  final DateTime? lastDeparture;

  /// Duración promedio de suministro observada: media de los pares
  /// consecutivos ARRIVED → LEFT del mismo sector.
  final Duration? averageSupplyDuration;

  /// Duración promedio de interrupción observada: media de los pares
  /// consecutivos LEFT → ARRIVED del mismo sector.
  final Duration? averageOutageDuration;

  final int supplyPairCount;
  final int outagePairCount;
}

/// Calcula [WaterStatistics] a partir de los eventos cargados.
///
/// Fórmulas:
/// - Los eventos se ordenan por `event_time` ascendente (la entrada puede
///   venir desordenada) y se recorren de a pares consecutivos.
/// - Un par (A, B) con A y B del mismo `sectorId` cuenta como suministro si
///   A es `arrived` y B es `left` (duración B − A), e interrupción si A es
///   `left` y B es `arrived`. Los pares NO cruzan sectores.
/// - `averageSupplyDuration` / `averageOutageDuration` son la media simple
///   de las duraciones de los pares observados; nulos si no hay pares.
///
/// No se fabrica ningún dato predictivo: sin pares completos los promedios
/// quedan nulos (la UI muestra 'Sin datos suficientes').
WaterStatistics computeWaterStatistics(List<WaterEventSummary> events) {
  final ordered = [...events]
    ..sort((a, b) {
      final byTime = a.eventTime.compareTo(b.eventTime);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  var arrived = 0;
  var left = 0;
  DateTime? lastArrival;
  DateTime? lastDeparture;

  var supplyTotal = Duration.zero;
  var outageTotal = Duration.zero;
  var supplyPairs = 0;
  var outagePairs = 0;

  for (var i = 0; i < ordered.length; i++) {
    final current = ordered[i];

    if (current.type == WaterEventType.arrived) {
      arrived++;
      if (lastArrival == null || current.eventTime.isAfter(lastArrival)) {
        lastArrival = current.eventTime;
      }
    } else {
      left++;
      if (lastDeparture == null || current.eventTime.isAfter(lastDeparture)) {
        lastDeparture = current.eventTime;
      }
    }

    if (i + 1 >= ordered.length) break;
    final next = ordered[i + 1];
    if (current.sectorId == null ||
        next.sectorId == null ||
        current.sectorId != next.sectorId) {
      continue;
    }
    final duration = next.eventTime.difference(current.eventTime);
    if (current.type == WaterEventType.arrived &&
        next.type == WaterEventType.left) {
      supplyPairs++;
      supplyTotal += duration;
    } else if (current.type == WaterEventType.left &&
        next.type == WaterEventType.arrived) {
      outagePairs++;
      outageTotal += duration;
    }
  }

  return WaterStatistics(
    totalEvents: ordered.length,
    arrivedCount: arrived,
    leftCount: left,
    lastArrival: lastArrival,
    lastDeparture: lastDeparture,
    averageSupplyDuration: supplyPairs == 0
        ? null
        : supplyTotal ~/ supplyPairs,
    averageOutageDuration: outagePairs == 0
        ? null
        : outageTotal ~/ outagePairs,
    supplyPairCount: supplyPairs,
    outagePairCount: outagePairs,
  );
}
