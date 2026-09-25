import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/core/network/gota_water_database.dart';
import 'package:gota/features/water/data/water_event_repository.dart';
import 'package:gota/features/water/domain/water_event.dart';
import 'package:gota/features/water/domain/water_event_detail.dart';
import 'package:gota/features/water/domain/water_event_type.dart';
import 'package:gota/features/water/presentation/water_copy.dart';
import 'package:gota/features/water/presentation/water_screen.dart';

class _FakeWaterRepository implements WaterEventRepository {
  _FakeWaterRepository(this.events);

  final List<WaterEventSummary> events;
  final List<String> validatedIds = [];

  @override
  Future<WaterEventDetail> detail(String eventId) => throw UnimplementedError();

  @override
  Future<(WaterEventSummary, bool isConfirmation)> register({
    required String municipalityId,
    required String sectorId,
    required WaterEventType type,
    required DateTime eventTime,
    String? comment,
  }) => throw UnimplementedError();
  @override
  Future<int> validate(String eventId) async {
    validatedIds.add(eventId);
    return 1;
  }

  @override
  Future<WaterEventSummary?> latestEvent({String? sectorId}) async => null;

  @override
  Future<WaterEventsPage> recentEvents({
    int limit = 20,
    WaterEventCursor? cursor,
  }) async => WaterEventsPage(events: events.take(limit).toList());
}

WaterEventSummary _event(String id, WaterEventType type) => WaterEventSummary(
  id: id,
  type: type,
  eventTime: DateTime(2026, 9, 12, 8, 30),
  validationCount: 3,
  createdAt: DateTime(2026, 9, 12, 8, 35),
  sectorName: 'Centro',
  municipalityName: 'Maneiro',
);

Future<void> _pump(WidgetTester tester, WaterEventRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [waterEventRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light, home: const WaterScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('WaterScreen (S09-UI-B, visual sin cambiar contratos)', () {
    testWidgets('muestra acciones Llegó/Se fue, resumen e historial', (
      tester,
    ) async {
      final repo = _FakeWaterRepository([
        _event('e1', WaterEventType.arrived),
        _event('e2', WaterEventType.left),
      ]);

      await _pump(tester, repo);

      // Acciones rápidas conservan sus claves funcionales y etiqueta de copy
      // centralizado.
      expect(find.byKey(waterArrivedButtonKey), findsOneWidget);
      expect(find.byKey(waterLeftButtonKey), findsOneWidget);
      expect(find.text(WaterEventType.arrived.label), findsWidgets);
      expect(find.text('Resumen'), findsNothing);
      expect(find.text(WaterCopy.historyTitle), findsOneWidget);

      // Historial: tile con icono en caja (GotaIconTile) por evento.
      expect(find.byKey(waterTileKey('e1')), findsOneWidget);
      expect(find.byKey(waterTileKey('e2')), findsOneWidget);
      expect(find.byType(WaterEventCard), findsNWidgets(2));
    });

    testWidgets('tap en acción abre el flujo de registro con tipo inicial', (
      tester,
    ) async {
      final repo = _FakeWaterRepository(const []);

      await _pump(tester, repo);
      await tester.tap(find.byKey(waterArrivedButtonKey));
      await tester.pumpAndSettle();

      // El flujo de registro existente conserva su primer paso (§stepType).
      // (Dos widgets comparten el copy en el paso de tipo; basta con
      // verificar presencia.)
      expect(find.text(WaterCopy.stepType), findsWidgets);
    });

    testWidgets(
      'historial vacío muestra el estado vacío con copy centralizado',
      (tester) async {
        await _pump(tester, _FakeWaterRepository(const []));

        expect(find.text(WaterCopy.emptyList), findsOneWidget);
      },
    );
  });
}
