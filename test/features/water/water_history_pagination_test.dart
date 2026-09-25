import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:gota/core/network/gota_water_database.dart';
import 'package:gota/features/water/data/water_event_repository.dart';
import 'package:gota/features/water/domain/water_event.dart';
import 'package:gota/features/water/domain/water_event_type.dart';
import 'package:gota/features/water/presentation/water_providers.dart';

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

      // Segunda llamada (con cursor): devuelve la segunda página.
      // Se registra ANTES que el stub exacto `cursor: null` porque `any()`
      // también coincide con null y mocktail usa el último stub que coincide.
      when(() => mockRepo.recentEvents(limit: 20, cursor: any(named: 'cursor')))
          .thenAnswer(
        (_) async => WaterEventsPage(
          events: secondPageEvents,
          nextCursor: null,
        ),
      );

      // Primera llamada (sin cursor): devuelve la primera página
      when(() => mockRepo.recentEvents(limit: 20, cursor: null)).thenAnswer(
        (_) async => WaterEventsPage(
          events: firstPageEvents,
          nextCursor: expectedCursor,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          waterEventRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
      addTearDown(container.dispose);

      // Esperar carga inicial (se programa como microtask en build()).
      WaterHistoryState state = container.read(waterHistoryControllerProvider);
      for (var i = 0;
          i < 50 && state.events.value == null;
          i++) {
        await Future<void>.delayed(Duration.zero);
        state = container.read(waterHistoryControllerProvider);
      }
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
      // No debe haber más páginas. Nota: el copyWith del estado no puede
      // poner nextCursor a null (patrón `nextCursor ?? this.nextCursor`),
      // así que solo se afirma hasMore == false.
      expect(updatedState.hasMore, isFalse);

      // Verificar que la segunda llamada usó el cursor de la primera página
      final captured = verify(
        () => mockRepo.recentEvents(
          limit: 20,
          cursor: captureAny(named: 'cursor'),
        ),
      ).captured;
      expect(captured.isNotEmpty, isTrue);
      final usedCursor = captured.last as WaterEventCursor?;
      expect(usedCursor?.id, expectedCursor.id);
      expect(usedCursor?.eventTime, expectedCursor.eventTime);
    });

    test('loadMore() no llama al repo si hasMore es false', () async {
      when(() => mockRepo.recentEvents(limit: 20, cursor: null)).thenAnswer(
        (_) async => WaterEventsPage(
          events: [],
          nextCursor: null,
        ),
      );

      final container = ProviderContainer(
        overrides: [waterEventRepositoryProvider.overrideWithValue(mockRepo)],
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);
      WaterHistoryState state = container.read(waterHistoryControllerProvider);
      for (var i = 0;
          i < 50 && state.events.value == null;
          i++) {
        await Future<void>.delayed(Duration.zero);
        state = container.read(waterHistoryControllerProvider);
      }

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
