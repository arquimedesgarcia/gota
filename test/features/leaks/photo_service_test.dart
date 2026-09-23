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
      late ({
        int minWidth,
        int minHeight,
        int quality,
        String srcPath,
        String dstPath,
      })
      captured;
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
              captured = (
                minWidth: minWidth,
                minHeight: minHeight,
                quality: quality,
                srcPath: srcPath,
                dstPath: dstPath,
              );
              await File(dstPath).writeAsBytes(List.filled(64, 0x7f));
              return dstPath;
            },
      );

      final result = await svc.prepareFromFile(tempFile.path);

      expect(
        captured.minWidth,
        lessThanOrEqualTo(kReportPhotoCompressMaxDimension),
      );
      expect(
        captured.minHeight,
        lessThanOrEqualTo(kReportPhotoCompressMaxDimension),
      );
      expect(captured.quality, kReportPhotoCompressQuality);
      // El presupuesto en sí, no sólo su uso: si alguien lo sube, este test cae.
      expect(kReportPhotoCompressMaxDimension, lessThanOrEqualTo(1280));
      expect(kReportPhotoCompressQuality, lessThanOrEqualTo(80));
      expect(captured.srcPath, tempFile.path);
      expect(captured.dstPath, endsWith('_gota.jpg'));
      expect(result.compressedPath, captured.dstPath);
      expect(result.sizeBytes, greaterThan(0));
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
