import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gota/features/leaks/data/photo_limits.dart';
import 'package:gota/features/leaks/data/photo_service.dart';
import 'package:gota/features/leaks/domain/leak_errors.dart';

void main() {
  late ImagePickerPhotoService service;

  setUp(() {
    service = ImagePickerPhotoService();
  });

  group('prepareFromFile — ramas que no invocan el compresor nativo', () {
    test('path inexistente lanza PhotoValidationException', () async {
      await expectLater(
        () => service.prepareFromFile('/no/existe/foto.jpg'),
        throwsA(
          isA<PhotoValidationException>().having(
            (e) => e.userMessage,
            'userMessage',
            contains('no está disponible'),
          ),
        ),
      );
    });

    test('extensión no permitida lanza PhotoValidationException', () async {
      final tmp = await File(
        '${Directory.systemTemp.path}/test_photo_service_ext.gif',
      ).create();
      await tmp.writeAsBytes([0xFF, 0xD8]); // datos irrelevantes
      addTearDown(tmp.delete);

      await expectLater(
        () => service.prepareFromFile(tmp.path),
        throwsA(
          isA<PhotoValidationException>().having(
            (e) => e.userMessage,
            'userMessage',
            contains('JPG, PNG o WebP'),
          ),
        ),
      );
    });

    test('archivo de 0 bytes lanza PhotoValidationException', () async {
      final tmp = await File(
        '${Directory.systemTemp.path}/test_photo_service_empty.jpg',
      ).create();
      await tmp.writeAsBytes([]); // 0 bytes
      addTearDown(tmp.delete);

      await expectLater(
        () => service.prepareFromFile(tmp.path),
        throwsA(
          isA<PhotoValidationException>().having(
            (e) => e.userMessage,
            'userMessage',
            contains('vacía o dañada'),
          ),
        ),
      );
    });
  });

  group('prepareFromFile — presupuesto de resolución (seam compress)', () {
    test('el pase de compresión se pide acotado (≤ kReportPhotoCompressMaxDimension, calidad acotada)', () async {
      final calls = <({
        int minWidth,
        int minHeight,
        int quality,
        String srcPath,
        String dstPath,
      })>[];
      final tempFile = await File(
        '${Directory.systemTemp.path}/test_photo_service.jpg',
      ).create();
      await tempFile.writeAsBytes(List.filled(64, 0x7f));
      addTearDown(tempFile.delete);

      final svc = ImagePickerPhotoService(
        compress:
            ({
              required String srcPath,
              required String dstPath,
              required int minWidth,
              required int minHeight,
              required int quality,
            }) async {
              calls.add((
                minWidth: minWidth,
                minHeight: minHeight,
                quality: quality,
                srcPath: srcPath,
                dstPath: dstPath,
              ));
              await File(dstPath).writeAsBytes(List.filled(64, 0x7f));
              return dstPath;
            },
      );

      final result = await svc.prepareFromFile(tempFile.path);

      // Primer pase: compresión principal.
      final main = calls.first;
      expect(
        main.minWidth,
        lessThanOrEqualTo(kReportPhotoCompressMaxDimension),
      );
      expect(
        main.minHeight,
        lessThanOrEqualTo(kReportPhotoCompressMaxDimension),
      );
      expect(main.quality, kReportPhotoCompressQuality);
      // El presupuesto en sí, no sólo su uso: si alguien lo sube, este test cae.
      expect(kReportPhotoCompressMaxDimension, lessThanOrEqualTo(1280));
      expect(kReportPhotoCompressQuality, lessThanOrEqualTo(80));
      expect(main.srcPath, tempFile.path);
      expect(main.dstPath, endsWith('_gota.jpg'));
      expect(result.compressedPath, main.dstPath);
      expect(result.sizeBytes, greaterThan(0));
    });

    test('segunda pasada de miniatura se pide acotada (≤ kReportPhotoThumbMaxDimension, calidad acotada)', () async {
      final calls = <({int minWidth, int minHeight, int quality})>[];
      final tempFile = await File(
        '${Directory.systemTemp.path}/test_photo_service_thumb.jpg',
      ).create();
      await tempFile.writeAsBytes(List.filled(64, 0x7f));
      addTearDown(tempFile.delete);

      final svc = ImagePickerPhotoService(
        compress:
            ({
              required String srcPath,
              required String dstPath,
              required int minWidth,
              required int minHeight,
              required int quality,
            }) async {
              calls.add((minWidth: minWidth, minHeight: minHeight, quality: quality));
              await File(dstPath).writeAsBytes(List.filled(32, 0x7f));
              return dstPath;
            },
      );

      final result = await svc.prepareFromFile(tempFile.path);

      // Se espera exactamente dos llamadas al compresor (principal + thumb).
      expect(calls.length, 2);

      final thumb = calls[1];
      expect(thumb.minWidth, lessThanOrEqualTo(kReportPhotoThumbMaxDimension));
      expect(thumb.minHeight, lessThanOrEqualTo(kReportPhotoThumbMaxDimension));
      expect(thumb.quality, kReportPhotoThumbQuality);
      // Presupuesto explícito: si alguien sube estos valores, el test cae.
      expect(kReportPhotoThumbMaxDimension, lessThanOrEqualTo(128));
      expect(kReportPhotoThumbQuality, lessThanOrEqualTo(70));

      expect(result.thumbnailPath, isNotNull);
      expect(result.thumbnailPath, endsWith('_gota_thumb.jpg'));
    });

    test('thumbnailPath queda null y no se lanza excepción si el thumb falla', () async {
      int callCount = 0;
      final tempFile = await File(
        '${Directory.systemTemp.path}/test_photo_service_thumb_fail.jpg',
      ).create();
      await tempFile.writeAsBytes(List.filled(64, 0x7f));
      addTearDown(tempFile.delete);

      final svc = ImagePickerPhotoService(
        compress:
            ({
              required String srcPath,
              required String dstPath,
              required int minWidth,
              required int minHeight,
              required int quality,
            }) async {
              callCount++;
              if (callCount == 1) {
                // Primera llamada (principal): éxito.
                await File(dstPath).writeAsBytes(List.filled(64, 0x7f));
                return dstPath;
              }
              // Segunda llamada (thumb): falla.
              throw StateError('compresión de thumb fallida');
            },
      );

      final result = await svc.prepareFromFile(tempFile.path);

      expect(result.thumbnailPath, isNull);
      expect(result.compressedPath, isNotNull);
    });

    test('thumbnailPath queda null si el thumb compress devuelve null', () async {
      int callCount = 0;
      final tempFile = await File(
        '${Directory.systemTemp.path}/test_photo_service_thumb_null.jpg',
      ).create();
      await tempFile.writeAsBytes(List.filled(64, 0x7f));
      addTearDown(tempFile.delete);

      final svc = ImagePickerPhotoService(
        compress:
            ({
              required String srcPath,
              required String dstPath,
              required int minWidth,
              required int minHeight,
              required int quality,
            }) async {
              callCount++;
              if (callCount == 1) {
                await File(dstPath).writeAsBytes(List.filled(64, 0x7f));
                return dstPath;
              }
              return null; // Thumb no generado.
            },
      );

      final result = await svc.prepareFromFile(tempFile.path);

      expect(result.thumbnailPath, isNull);
    });

    test('compresión que devuelve null → PhotoValidationException', () async {
      final tempFile = await File(
        '${Directory.systemTemp.path}/test_photo_service_null.jpg',
      ).create();
      await tempFile.writeAsBytes(List.filled(64, 0x7f));
      addTearDown(tempFile.delete);

      final svc = ImagePickerPhotoService(
        compress:
            ({
              required String srcPath,
              required String dstPath,
              required int minWidth,
              required int minHeight,
              required int quality,
            }) async {
              return null;
            },
      );

      await expectLater(
        () => svc.prepareFromFile(tempFile.path),
        throwsA(
          isA<PhotoValidationException>().having(
            (e) => e.userMessage,
            'userMessage',
            contains('No pudimos procesar'),
          ),
        ),
      );
    });

    test(
      'compresión que lanza un Error → PhotoValidationException, no se propaga',
      () async {
        final tempFile = await File(
          '${Directory.systemTemp.path}/test_photo_service_error.jpg',
        ).create();
        await tempFile.writeAsBytes(List.filled(64, 0x7f));
        addTearDown(tempFile.delete);

        final svc = ImagePickerPhotoService(
          compress:
              ({
                required String srcPath,
                required String dstPath,
                required int minWidth,
                required int minHeight,
                required int quality,
              }) async {
                throw StateError('fallo nativo simulado');
              },
        );

        await expectLater(
          () => svc.prepareFromFile(tempFile.path),
          throwsA(
            isA<PhotoValidationException>().having(
              (e) => e.userMessage,
              'userMessage',
              contains('No pudimos procesar'),
            ),
          ),
        );
      },
    );
  });
}
