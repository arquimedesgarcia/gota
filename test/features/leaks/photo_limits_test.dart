import 'package:flutter_test/flutter_test.dart';
import 'package:gota/features/leaks/data/photo_limits.dart';
import 'package:gota/features/leaks/domain/leak_errors.dart';

void main() {
  group('formato permitido (capa cliente)', () {
    test('acepta JPG, JPEG, PNG y WebP (y mayúsculas)', () {
      for (final name in const [
        'foto.jpg',
        'foto.jpeg',
        'foto.png',
        'foto.webp',
        'FOTO.JPG',
        'IMG_1234.PNG',
      ]) {
        expect(
          () => validatePickedPhoto(path: '/tmp/$name', sizeBytes: 1024),
          returnsNormally,
          reason: '$name debería ser aceptado',
        );
      }
    });

    test('rechaza formatos no permitidos con mensaje claro', () {
      for (final name in const ['foto.gif', 'foto.heic', 'foto.txt', 'foto']) {
        expect(
          () => validatePickedPhoto(path: '/tmp/$name', sizeBytes: 1024),
          throwsA(
            isA<PhotoValidationException>().having(
              (e) => e.userMessage,
              'userMessage',
              contains('JPG, PNG o WebP'),
            ),
          ),
          reason: '$name debería ser rechazado',
        );
      }
    });
  });

  group('tamaño (capa cliente)', () {
    test('acepta justo el máximo (10 MB)', () {
      expect(
        () => validatePickedPhoto(
          path: '/tmp/foto.jpg',
          sizeBytes: kReportPhotoMaxBytes,
        ),
        returnsNormally,
      );
    });

    test('rechaza por encima del máximo', () {
      expect(
        () => validatePickedPhoto(
          path: '/tmp/foto.jpg',
          sizeBytes: kReportPhotoMaxBytes + 1,
        ),
        throwsA(isA<PhotoValidationException>()),
      );
    });

    test('rechaza archivos vacíos', () {
      expect(
        () => validatePickedPhoto(path: '/tmp/foto.jpg', sizeBytes: 0),
        throwsA(isA<PhotoValidationException>()),
      );
    });

    test('el resultado comprimido también se valida', () {
      expect(() => validateCompressedPhoto(sizeBytes: 2048), returnsNormally);
      expect(
        () => validateCompressedPhoto(sizeBytes: kReportPhotoMaxBytes + 1),
        throwsA(isA<PhotoValidationException>()),
      );
      expect(
        () => validateCompressedPhoto(sizeBytes: 0),
        throwsA(isA<PhotoValidationException>()),
      );
    });
  });

  group('cantidad (capa cliente)', () {
    test('el límite cliente coincide con el del servidor', () {
      // Debe coincidir con system_config.photo_limits (migración 00009).
      expect(kReportPhotoMaxCount, 3);
      expect(kReportPhotoMaxBytes, 10 * 1024 * 1024);
    });
  });
}
