import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/leak_errors.dart';
import '../domain/leak_report_draft.dart';
import 'photo_limits.dart';

/// Prepara fotos: compresión, validación de formato/tamaño y metadatos.
///
/// NO sube nada a Storage: solo produce un [PreparedPhoto] local. La
/// conversión a JPEG elimina el EXIF (privacidad: la foto no arrastra la
/// ubicación exacta del vecino) y garantiza un MIME aceptado por el
/// servidor.
abstract class PhotoService {
  /// Abre la cámara o la galería, comprime y valida la foto.
  /// Lanza [PhotoValidationException] si el resultado no cumple.
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera});

  /// Comprime y valida un archivo que ya está en disco.
  Future<PreparedPhoto> prepareFromFile(String path);
}

class ImagePickerPhotoService implements PhotoService {
  ImagePickerPhotoService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
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

    // 1. Validación cliente (formato y tamaño antes de comprimir).
    validatePickedPhoto(
      path: path,
      sizeBytes: await original.length(),
    );

    // 2. Compresión a JPEG ≤ 10 MB.
    final compressedPath = '${path}_gota.jpg';
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

    // 3. Validación cliente del resultado.
    final sizeBytes = await File(compressed.path).length();
    validateCompressedPhoto(sizeBytes: sizeBytes);

    return PreparedPhoto(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      originalPath: path,
      compressedPath: compressed.path,
      mimeType: kReportPhotoContentType,
      sizeBytes: sizeBytes,
      // Las dimensiones exactas las determina el servidor a partir del
      // binario; aquí se dejan en 0 (sin metadatos inventados).
      width: 0,
      height: 0,
    );
  }
}
