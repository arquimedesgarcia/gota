import 'package:path/path.dart' as p;

import '../domain/leak_errors.dart';

/// Límites de fotografías del lado cliente.
///
/// Deben coincidir con `system_config.photo_limits` (migración 00009); la
/// RPC `create_leak_report` vuelve a validarlos server-side contra el
/// binario real en Storage. Ambas capas existen a propósito: el cliente
/// da respuesta inmediata, el servidor es la autoridad.
const kReportPhotoMaxCount = 3;
const kReportPhotoMaxBytes = 10 * 1024 * 1024; // 10 MB
const kReportPhotoAllowedExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
const kReportPhotoContentType = 'image/jpeg';

/// Valida el archivo elegido por el usuario antes de comprimirlo.
void validatePickedPhoto({required String path, required int sizeBytes}) {
  final extension = p.extension(path).toLowerCase();
  if (!kReportPhotoAllowedExtensions.contains(extension)) {
    throw const PhotoValidationException(
      'Formato no admitido. Usa JPG, PNG o WebP.',
    );
  }
  if (sizeBytes <= 0) {
    throw const PhotoValidationException(
      'La foto está vacía o dañada. Elige otra.',
    );
  }
  if (sizeBytes > kReportPhotoMaxBytes) {
    throw const PhotoValidationException(
      'La foto es demasiado grande (máximo 10 MB). Elige otra.',
    );
  }
}

/// Valida el resultado ya comprimido (siempre JPEG).
void validateCompressedPhoto({required int sizeBytes}) {
  if (sizeBytes <= 0) {
    throw const PhotoValidationException(
      'No pudimos procesar esa foto. Elige otra.',
    );
  }
  if (sizeBytes > kReportPhotoMaxBytes) {
    throw const PhotoValidationException(
      'La foto sigue siendo demasiado grande tras comprimir. Elige otra.',
    );
  }
}
