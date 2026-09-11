/// Tipo de evento de agua (docs/FUNCTIONAL_SPEC.md §10). El `wireName` es el
/// valor que el backend almacena en `water_events.event_type`.
enum WaterEventType {
  arrived('WATER_ARRIVED', 'Llegó'),
  left('WATER_LEFT', 'Se fue');

  const WaterEventType(this.wireName, this.label);

  /// Valor en cable (`WATER_ARRIVED` / `WATER_LEFT`).
  final String wireName;

  /// Etiqueta corta para la UI.
  final String label;

  /// Traduce el valor del backend al enum; lanza [FormatException] si no es
  /// un tipo válido (la RPC ya valida, esto es defensa en profundidad).
  static WaterEventType fromWire(String value) => switch (value) {
        'WATER_ARRIVED' => arrived,
        'WATER_LEFT' => left,
        _ => throw FormatException('Tipo de evento no válido: $value'),
      };
}
