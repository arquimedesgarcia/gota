/// Formatea el mensaje de límite de frecuencia (RATE_LIMIT_EXCEEDED).
///
/// Usa el mensaje del backend y, si viene `reset_at`, añade la hora local
/// de reintento en formato HH:mm.
String formatRateLimitMessage(
  Map<String, dynamic> data, {
  String defaultMessage = 'Has alcanzado el límite por hora.',
}) {
  final base = data['message'] as String? ?? defaultMessage;
  final rawResetAt = data['reset_at'];
  final resetAt = rawResetAt is String ? DateTime.tryParse(rawResetAt) : null;
  if (resetAt == null) return base;
  final local = resetAt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$base Intenta de nuevo después de las $hh:$mm.';
}
