/// Foto de un reporte de fuga, tal como la entrega la RPC `get_report_photos`.
///
/// El cliente NUNCA recibe `storage_path` crudo: solo signed URLs temporales
/// (TTL 900 s). El campo [expiresAt] permite saber cuándo renovar.
class LeakPhoto {
  const LeakPhoto({
    required this.id,
    required this.sortOrder,
    required this.url,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.expiresAt,
  });

  final String id;
  final int sortOrder;

  /// Signed URL de la foto a resolución completa (~1280 px).
  final String url;

  /// Signed URL de la miniatura (128 px). Null para fotos antiguas sin thumb.
  final String? thumbnailUrl;

  final int? width;
  final int? height;

  /// Momento en que las URLs expiran. Calculado por el repositorio al recibir
  /// las fotos (now + TTL 900 s).
  final DateTime? expiresAt;

  /// Verdadero si la URL expira en menos de [margin].
  bool isExpiringSoon({Duration margin = const Duration(minutes: 2)}) {
    if (expiresAt == null) return false;
    return expiresAt!.difference(DateTime.now().toUtc()) < margin;
  }

  /// URL a usar para la miniatura: preferencia por [thumbnailUrl]; si es null,
  /// usa [url] (foto completa, redimensionada por el widget).
  String get displayThumbnailUrl => thumbnailUrl ?? url;
}
