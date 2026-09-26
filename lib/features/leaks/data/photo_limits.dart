import 'package:path/path.dart' as p;

import '../domain/leak_errors.dart';

/// Límites de fotografías del lado cliente.
///
/// Deben coincidir con `system_config.photo_limits` (migración 00009); la
/// RPC `create_leak_report` vuelve a validarlos server-side contra el
/// binario real en Storage. Ambas capas existen a propósito: el cliente
/// da respuesta inmediata, el servidor es la autoridad.
/// El dueño del producto ajusta `max_count` a 2 en la BD por separado;
/// esta constante no puede quedar por encima del valor del servidor.
const kReportPhotoMaxCount = 2;
const kReportPhotoMaxBytes = 10 * 1024 * 1024; // 10 MB
const kReportPhotoAllowedExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
const kReportPhotoContentType = 'image/jpeg';

/// Presupuesto de resolución de la evidencia: **no** es alta resolución.
/// 1280 px en el lado mayor alcanza para reconocer una fuga y mantiene bajo el
/// pico de memoria del pipeline nativo (decode + reencode, dos pasadas: en
/// `image_picker` y en el pase que borra el EXIF).
const kReportPhotoPickerMaxDimension = 1280;
const kReportPhotoCompressMaxDimension = 1280;
const kReportPhotoCompressQuality = 75;

// Miniaturas (segunda pasada de compresión, cliente genera antes de subir).
const kReportPhotoThumbMaxDimension = 128;
const kReportPhotoThumbQuality = 70;

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
