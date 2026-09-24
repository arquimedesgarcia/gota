import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/features/map/presentation/map_providers.dart';

void main() {
  group('MapFilterNotifier.setBounds()', () {
    late ProviderContainer container;
    late MapFilterNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(mapFilterProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('primer setBounds establece los bounds en el estado', () {
      notifier.setBounds(10.0, -64.0, 11.0, -63.0);

      final state = container.read(mapFilterProvider);
      expect(state.minLat, 10.0);
      expect(state.minLng, -64.0);
      expect(state.maxLat, 11.0);
      expect(state.maxLng, -63.0);
    });

    test('setBounds con valores idénticos no cambia el estado (deduplicación)', () {
      notifier.setBounds(10.0, -64.0, 11.0, -63.0);
      final stateAfterFirst = container.read(mapFilterProvider);

      // Llamar de nuevo con los mismos valores
      notifier.setBounds(10.0, -64.0, 11.0, -63.0);
      final stateAfterSecond = container.read(mapFilterProvider);

      // El estado debe ser el mismo objeto (no hubo rebuild)
      expect(identical(stateAfterFirst, stateAfterSecond), isTrue);
    });

    test('setBounds con diferencia menor a 1e-5 no cambia el estado', () {
      notifier.setBounds(10.0, -64.0, 11.0, -63.0);
      final stateAfterFirst = container.read(mapFilterProvider);

      // Diferencia de 1e-6 (menor que la tolerancia 1e-5)
      notifier.setBounds(10.000001, -64.000001, 11.000001, -63.000001);
      final stateAfterSecond = container.read(mapFilterProvider);

      expect(identical(stateAfterFirst, stateAfterSecond), isTrue);
    });

    test('setBounds con diferencia mayor a 1e-5 sí actualiza el estado', () {
      notifier.setBounds(10.0, -64.0, 11.0, -63.0);

      // Diferencia de 1e-4 (mayor que la tolerancia 1e-5)
      notifier.setBounds(10.0001, -64.0, 11.0, -63.0);
      final state = container.read(mapFilterProvider);

      expect(state.minLat, closeTo(10.0001, 1e-10));
    });

    test('setBounds sin bounds previos siempre actualiza el estado', () {
      // Estado inicial sin bounds
      final initialState = container.read(mapFilterProvider);
      expect(initialState.minLat, isNull);

      notifier.setBounds(10.0, -64.0, 11.0, -63.0);
      final state = container.read(mapFilterProvider);

      expect(state.minLat, 10.0);
    });
  });
}
