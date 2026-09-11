/// Hora efectiva de un evento de agua en texto corto (docs/UX_SPEC.md §1:
/// poco texto). Función pura y con `now` inyectable para poder probarla.
///
/// Compara por fecha local: 'Hoy · 07:30' si es hoy, 'Ayer · 18:45' si es
/// ayer, 'd MMM · HH:mm' si es este año y 'd MMM yyyy · HH:mm' si es un
/// año anterior. Meses abreviados en español sin intl.
String describeWaterEventTime(DateTime eventTime, {required DateTime now}) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  final local = eventTime.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final eventDay = DateTime(local.year, local.month, local.day);
  final dayDiff = today.difference(eventDay).inDays;

  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final time = '$hh:$mm';
  final month = months[local.month - 1];

  if (dayDiff == 0) return 'Hoy · $time';
  if (dayDiff == 1) return 'Ayer · $time';
  if (local.year == now.year) return '${local.day} $month · $time';
  return '${local.day} $month ${local.year} · $time';
}
