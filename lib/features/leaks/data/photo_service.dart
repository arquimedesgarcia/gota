import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../domain/leak_errors.dart';
import '../domain/leak_report_draft.dart';

/// Tamaño máximo permitido; coincide con `system_config.photo_limits`.
const kMaxPhotoBytes = 10 * 1024 * 1024;

/// Prepara fotos: compresión, validación de tamaño y formato.
/// NO sube nada a Storage; solo produce [PreparedPhoto] local.
abstract class PhotoService {
  /// Abre la cámara o la galería, comprime valida y devuelve la foto
  /// preparada. Lanza [PhotoValidationException] si el resultado no cumple.
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera});

  /// Comprime y valida un archivo que ya está en disco.
  Future<PreparedPhoto> prepareFromFile(String path);
}

class ImagePickerPhotoService implements PhotoService {
  @override
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // Precompresión del picker: límite razonable para cámaras modernas.
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null) {
      // Cancelación del usuario: no es un error visible.
      throw const PhotoValidationException('No se seleccionó ninguna foto.');
    }
    return prepareFromFile(picked.path);
  }

  @override
  Future<PreparedPhoto> prepareFromFile(String path) async {
    final original = File(path);
    if (!await original.exists()) {
      throw const PhotoValidationException(
        'La foto no está disponible. Elige otra.',
      );
    }

    final extension = p.extension(path).toLowerCase();
    final allowed = extension == '.jpg' ||
        extension == '.jpeg' ||
        extension == '.png' ||
        extension == '.webp';
    if (!allowed) {
      throw const PhotoValidationException(
        'Formato no admitido. Usa JPG, PNG o WebP.',
      );
    }

    // Compresión local para asegurar el límite de tamaño y quitar EXIF
    // (privacidad: la foto no arrastra la ubicación exacta del usuario).
    final compressedPath = p.setExtension(
      '${p.withoutExtension(path)}_gota',
      '.jpg',
    );
    final compressed = await FlutterImageCompress.compressAndGetFile(
      path,
      compressedPath,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    if (compressed == null) {
      throw const PhotoValidationException(
        'No pudimos procesar esa foto. Elige otra.',
      );
    }

    final sizeBytes = await File(compressed.path).length();
    if (sizeBytes > kMaxPhotoBytes) {
      throw const PhotoValidationException(
        'La foto es demasiado grande incluso comprimida. Elige otra.',
      );
    }

    // Dimensiones leídas del resultado del compresor (FlutterImageCompress
    // no expone el decodificado directo; image package sería una
    // dependencia extra). Se guardan 0 y la UI usa aspect ratio del file.
    const width = 0;
    const height = 0;

    return PreparedPhoto(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      originalPath: path,
      compressedPath: compressed.path,
      mimeType: 'image/jpeg',
      sizeBytes: sizeBytes,
      width: width,
      height: height,
    );
  }
}
