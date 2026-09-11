/// Antigüedad de un reporte en texto corto (docs/UX_SPEC.md §1: poco texto).
///
/// Función pura y con `now` inyectable para poder probarla.
String describeLeakAge(DateTime createdAt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(createdAt);

  if (diff.isNegative || diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 30) return 'hace ${diff.inDays} d';
  final months = (diff.inDays / 30).floor();
  if (months < 12) return 'hace $months mes${months == 1 ? '' : 'es'}';
  final years = (diff.inDays / 365).floor();
  return 'hace $years año${years == 1 ? '' : 's'}';
}
