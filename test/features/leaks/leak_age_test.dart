import 'package:flutter_test/flutter_test.dart';
import 'package:gota/features/leaks/domain/leak_age.dart';

void main() {
  final now = DateTime(2026, 1, 2, 12);

  test('describe la antigüedad en texto corto', () {
    expect(
      describeLeakAge(now.subtract(const Duration(seconds: 30)), now: now),
      'hace un momento',
    );
    expect(
      describeLeakAge(now.subtract(const Duration(minutes: 5)), now: now),
      'hace 5 min',
    );
    expect(
      describeLeakAge(now.subtract(const Duration(hours: 3)), now: now),
      'hace 3 h',
    );
    expect(
      describeLeakAge(now.subtract(const Duration(days: 2)), now: now),
      'hace 2 d',
    );
    expect(
      describeLeakAge(now.subtract(const Duration(days: 60)), now: now),
      'hace 2 meses',
    );
    expect(
      describeLeakAge(now.subtract(const Duration(days: 400)), now: now),
      'hace 1 año',
    );
  });

  test('una fecha futura no produce texto negativo', () {
    expect(
      describeLeakAge(now.add(const Duration(hours: 1)), now: now),
      'hace un momento',
    );
  });
}
