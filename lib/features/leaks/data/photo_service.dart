import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Firma del pase de compresión (envuelve al plugin nativo). Inyectable para
/// que el contrato de resolución y calidad sea verificable sin device.
typedef PhotoCompressCall =
    Future<String?> Function({
      required String srcPath,
      required String dstPath,
      required int minWidth,
      required int minHeight,
      required int quality,
    });

/// Implementación por defecto: `flutter_image_compress` a JPEG.
///
/// `keepExif` queda en su valor por defecto (`false`): este pase es el que
/// elimina el EXIF GPS que `image_picker` reinyecta
/// (`image_picker_android/.../ExifDataCopier.java`).
Future<String?> compressWithPlugin({
  required String srcPath,
  required String dstPath,
  required int minWidth,
  required int minHeight,
  required int quality,
}) async {
  final compressed = await FlutterImageCompress.compressAndGetFile(
    srcPath,
    dstPath,
    minWidth: minWidth,
    minHeight: minHeight,
    quality: quality,
    format: CompressFormat.jpeg,
  );
  return compressed?.path;
}

class ImagePickerPhotoService implements PhotoService {
  ImagePickerPhotoService({ImagePicker? picker, PhotoCompressCall? compress})
    : _picker = picker ?? ImagePicker(),
      _compress = compress ?? compressWithPlugin;

  final ImagePicker _picker;

  /// Pase de compresión nativo, inyectable para tests (sin él, el contrato de
  /// resolución/calidad solo se podría comprobar en device).
  final PhotoCompressCall _compress;

  @override
  Future<PreparedPhoto> pickAndPrepare({required bool fromCamera}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 80,
      // image_picker acota el lado mayor en el resize nativo (Android:
      // ImageResizer): es el primer recorte de memoria del pipeline.
      maxWidth: kReportPhotoPickerMaxDimension.toDouble(),
      maxHeight: kReportPhotoPickerMaxDimension.toDouble(),
    );
    if (picked == null) {
      // AUD-S2-14: cancelar no es un error visible (el controller lo sabe
      // por la excepción específica y no publica banner).
      throw const PhotoPickCanceledException();
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
    validatePickedPhoto(path: path, sizeBytes: await original.length());

    // 2. Un solo pase de compresión a JPEG, acotado por presupuesto
    // (kReportPhotoCompressMaxDimension / kReportPhotoCompressQuality).
    // `keepExif` es false por defecto: es el pase que borra el EXIF GPS que
    // image_picker reinyecta (ExifDataCopier.java), por eso sigue existiendo.
    // Ojo con los nombres: en flutter_image_compress `minWidth`/`minHeight`
    // **acotan** el tamaño de salida (README §minWidth and minHeight y su FAQ
    // «named that if it acts like a max»), no son mínimos.
    final compressedPath = '${path}_gota.jpg';
    String? compressed;
    try {
      compressed = await _compress(
        srcPath: path,
        dstPath: compressedPath,
        minWidth: kReportPhotoCompressMaxDimension,
        minHeight: kReportPhotoCompressMaxDimension,
        quality: kReportPhotoCompressQuality,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) debugPrint('compressAndGetFile falló: $error | $stackTrace');
      throw const PhotoValidationException(
        'No pudimos procesar esa foto. Elige otra.',
      );
    }
    if (compressed == null) {
      throw const PhotoValidationException(
        'No pudimos procesar esa foto. Elige otra.',
      );
    }

    // 3. Validación cliente del resultado.
    final sizeBytes = await File(compressed).length();
    validateCompressedPhoto(sizeBytes: sizeBytes);

    return PreparedPhoto(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      originalPath: path,
      compressedPath: compressed,
      mimeType: kReportPhotoContentType,
      sizeBytes: sizeBytes,
      // AUD-S2-08: este sprint NO genera miniaturas ni mide dimensiones
      // (exclusión declarada en MIGRATION_NOTES §Sprint 02; width/height
      // quedan en 0 y el servidor los persiste NULL, sin prometer nada).
      width: 0,
      height: 0,
    );
  }
}

/// Punto de inyección para tests: permite sustituir [PhotoService] sin el
/// plugin nativo.
final photoServiceProvider = Provider<PhotoService>(
  (ref) => ImagePickerPhotoService(),
);
