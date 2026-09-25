import 'package:flutter_test/flutter_test.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/map/domain/leak_map_status.dart';

LeakSummary _leak({
  String status = 'ACTIVE',
  int validationCount = 0,
}) {
  return LeakSummary(
    id: 'r1',
    status: status,
    validationCount: validationCount,
    resolutionConfirmationCount: 0,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('leakMapStatusOf', () {
    test('ACTIVE sin validaciones → reportada', () {
      expect(leakMapStatusOf(_leak()), LeakMapStatus.reported);
    });

    test('ACTIVE bajo el umbral → reportada', () {
      expect(
        leakMapStatusOf(_leak(validationCount: kValidatedCountThreshold - 1)),
        LeakMapStatus.reported,
      );
    });

    test('ACTIVE alcanzando el umbral → validada', () {
      expect(
        leakMapStatusOf(_leak(validationCount: kValidatedCountThreshold)),
        LeakMapStatus.validated,
      );
    });

    test('ACTIVE por encima del umbral → validada', () {
      expect(
        leakMapStatusOf(_leak(validationCount: kValidatedCountThreshold + 5)),
        LeakMapStatus.validated,
      );
    });

    test('RESOLVED siempre → resuelta, aunque tenga validaciones', () {
      expect(
        leakMapStatusOf(_leak(status: 'RESOLVED', validationCount: 10)),
        LeakMapStatus.resolved,
      );
    });
  });

  group('leyenda', () {
    test('exactamente tres estados', () {
      expect(LeakMapStatus.values.length, 3);
    });

    test('reportada y validada comparten el rojo; resuelta es verde', () {
      expect(
        leakMapStatusColor(LeakMapStatus.reported),
        leakMapStatusColor(LeakMapStatus.validated),
        reason: 'activas usan el mismo rojo',
      );
      expect(
        leakMapStatusColor(LeakMapStatus.resolved),
        isNot(leakMapStatusColor(LeakMapStatus.reported)),
        reason: 'resuelta usa verde distinto',
      );
    });

    test('solo las validadas tienen halo', () {
      expect(leakMapHasHalo(LeakMapStatus.reported), isFalse);
      expect(leakMapHasHalo(LeakMapStatus.validated), isTrue);
      expect(leakMapHasHalo(LeakMapStatus.resolved), isFalse);
    });
  });
}
