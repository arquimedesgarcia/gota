# FASE 4 — Cobertura de Tests

**Prerequisito:** Fases 1, 2 y 3 completadas. `flutter test` en verde.
**Hallazgos cubiertos:** H-16, H-17
**Commit al terminar:** `test(quality): fase 4 — tests de paginación y bounds`

---

## Corrección C4-01 — Test de WaterHistoryController.loadMore() con cursor real

**Hallazgo:** H-16
**Archivo:** `test/features/water/water_screen_test.dart`
**Tipo:** Test de unidad del controller

### Contexto

La corrección C1-02/C1-03 implementó keyset pagination real en `WaterHistoryController`.
Necesitamos un test que verifique que `loadMore()` efectivamente avanza a la segunda
página usando el cursor de la primera.

### Test a añadir

Añadir al archivo `test/features/water/water_screen_test.dart` (o crear un archivo
nuevo `test/features/water/water_history_pagination_test.dart` si el existente
ya está muy largo):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:gota/features/water/data/water_event_repository.dart';
import 'package:gota/features/water/domain/water_event.dart';
import 'package:gota/features/water/presentation/water_providers.dart';
import 'package:gota/core/network/gota_water_database.dart';

// Mock del repositorio
class MockWaterEventRepository extends Mock implements WaterEventRepository {}

// Datos de prueba
WaterEventSummary _fakeEvent(String id, DateTime eventTime) => WaterEventSummary(
  id: id,
  type: WaterEventType.arrived,
  eventTime: eventTime,
  comment: null,
  validationCount: 0,
  createdAt: eventTime,
  municipalityId: 'mun-1',
  sectorId: 'sec-1',
);

void main() {
  group('WaterHistoryController paginación keyset', () {
    late MockWaterEventRepository mockRepo;

    setUp(() {
      mockRepo = MockWaterEventRepository();
    });

    test('loadMore() usa el cursor de la primera página para pedir la segunda', () async {
      final now = DateTime.now();
      // Primera página: 20 eventos (llena → hay más)
      final firstPageEvents = List.generate(
        20,
        (i) => _fakeEvent('event-$i', now.subtract(Duration(hours: i))),
      );
      final expectedCursor = WaterEventCursor(
        eventTime: firstPageEvents.last.eventTime,
        id: firstPageEvents.last.id,
      );

      // Segunda página: 5 eventos (incompleta → no hay más)
      final secondPageEvents = List.generate(
        5,
        (i) => _fakeEvent('event-page2-$i', now.subtract(Duration(hours: 20 + i))),
      );

      // Primera llamada (sin cursor): devuelve la primera página
      when(() => mockRepo.recentEvents(limit: 20, cursor: null)).thenAnswer(
        (_) async => WaterEventsPage(
          events: firstPageEvents,
          nextCursor: expectedCursor,
          hasMore: true,
        ),
      );

      // Segunda llamada (con cursor): devuelve la segunda página
      when(() => mockRepo.recentEvents(limit: 20, cursor: any(named: 'cursor')))
          .thenAnswer(
        (_) async => WaterEventsPage(
          events: secondPageEvents,
          nextCursor: null,
          hasMore: false,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          waterEventRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      // Esperar carga inicial
      await Future<void>.delayed(Duration.zero);
      final state = container.read(waterHistoryControllerProvider);
      expect(state.events.value?.length, 20);
      expect(state.hasMore, isTrue);
      expect(state.nextCursor, isNotNull);

      // Cargar más
      await container
          .read(waterHistoryControllerProvider.notifier)
          .loadMore();

      final updatedState = container.read(waterHistoryControllerProvider);
      // Debe tener 25 eventos en total (20 + 5)
      expect(updatedState.events.value?.length, 25);
      // No debe haber más páginas
      expect(updatedState.hasMore, isFalse);
      expect(updatedState.nextCursor, isNull);

      // Verificar que la segunda llamada usó el cursor
      final captured = verify(
        () => mockRepo.recentEvents(
          limit: 20,
          cursor: captureAny(named: 'cursor'),
        ),
      ).captured;
      expect(captured.isNotEmpty, isTrue);
    });

    test('loadMore() no llama al repo si hasMore es false', () async {
      when(() => mockRepo.recentEvents(limit: 20, cursor: null)).thenAnswer(
        (_) async => WaterEventsPage(
          events: [],
          nextCursor: null,
          hasMore: false,
        ),
      );

      final container = ProviderContainer(
        overrides: [waterEventRepositoryProvider.overrideWithValue(mockRepo)],
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);

      await container
          .read(waterHistoryControllerProvider.notifier)
          .loadMore();

      // Solo debe haberse llamado una vez (la carga inicial)
      verify(() => mockRepo.recentEvents(limit: 20, cursor: null)).called(1);
      verifyNever(() => mockRepo.recentEvents(
            limit: any(named: 'limit'),
            cursor: any(named: 'cursor'),
          ));
    });
  });
}
```

**Nota:** Si `WaterEventsPage` no tiene el campo `hasMore` directamente sino que se
calcula a partir de `nextCursor`, adaptar el test según la estructura real de
`WaterEventsPage` en `lib/features/water/domain/water_event.dart`.

### Validación

- `flutter test` → El nuevo test pasa en verde.

---

## Corrección C4-02 — Test de MapFilterNotifier.setBounds() con tolerancia

**Hallazgo:** H-17
**Archivo nuevo:** `test/features/map/map_filter_notifier_test.dart`

### Contexto

`MapFilterNotifier.setBounds()` tiene lógica de deduplicación: si los nuevos bounds
son iguales a los anteriores (dentro de tolerancia 1e-5), no actualiza el estado.
Esta lógica no está cubierta por ningún test, y una rotura silenciosa podría causar
o demasiados refetches o falta de actualización del mapa.

### Test a añadir

Crear `test/features/map/map_filter_notifier_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/features/map/domain/map_filter.dart';
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
```

### Validación

- `flutter test` → El nuevo test pasa en verde.
- Verificar que los 4 casos pasan: establecer bounds, deduplicación exacta,
  deduplicación por tolerancia, y actualización fuera de tolerancia.

---

## Checklist de finalización de Fase 4

- [ ] C4-01: Test de paginación keyset en `WaterHistoryController.loadMore()`.
- [ ] C4-02: Test de `MapFilterNotifier.setBounds()` con deduplicación.
- [ ] `flutter test` → Todos en verde (incluyendo los nuevos).
- [ ] Commit: `test(quality): fase 4 — tests de paginación y bounds`

---

## PROMPT PARA EL AGENTE DE CODIFICACIÓN

```
Eres un agente de codificación trabajando en Gota v0.2 (Flutter · Riverpod 3 · Supabase).
Rama de trabajo: fix/map-r5-r6. Las Fases 1, 2 y 3 ya fueron aplicadas.

Tu tarea es añadir cobertura de tests para dos áreas críticas. NO modifiques código
de producción, solo añade tests.

Antes de empezar: ejecuta `flutter test` y confirma baseline verde.

TEST 1 (C4-01): Paginación keyset de WaterHistoryController
Añadir tests en test/features/water/ (en el archivo existente o uno nuevo).
Casos a cubrir:
  1. loadMore() con cursor real avanza a la segunda página y concatena los eventos.
  2. loadMore() con hasMore=false no llama al repositorio.
  3. El cursor de la primera página se pasa correctamente a la segunda llamada.
Usar mocktail para mockear WaterEventRepository.
Ver la especificación completa en FASE_4_TESTS_PROMPT.md.

TEST 2 (C4-02): MapFilterNotifier.setBounds() con deduplicación
Crear test/features/map/map_filter_notifier_test.dart (si no existe).
Casos a cubrir:
  1. Primer setBounds establece el estado.
  2. Mismo setBounds no cambia el estado (identical() = true).
  3. Diferencia < 1e-5 no cambia el estado.
  4. Diferencia > 1e-5 sí cambia el estado.
  5. Sin bounds previos siempre actualiza.
Ver la especificación completa en FASE_4_TESTS_PROMPT.md.

Al terminar:
1. `flutter test` → Todos en verde incluyendo los nuevos.
2. Commit: `test(quality): fase 4 — tests de paginación y bounds`
```
