import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/map/domain/map_filter.dart';
import 'package:gota/features/map/presentation/map_screen.dart';
import 'package:gota/features/map/presentation/map_providers.dart';
import 'package:gota/features/map/presentation/widgets/gota_map_view.dart'
    show
        gotaMapContainerKey,
        LatLngBounds,
        mapMarkerKey,
        mapWidgetBuilderProvider;

class _MockLeakCommunityRepository extends Mock
    implements LeakCommunityRepository {}

class _MockNavigatorObserver extends Mock implements NavigatorObserver {}

class _FakeRoute extends Fake implements Route<dynamic> {}

/// Test widget builder that returns a simple widget instead of MapLibre.
Widget _testMapBuilder(
  BuildContext context, {
  required List<LeakSummary> leaks,
  required LeakSummary? selectedLeak,
  required ValueChanged<LeakSummary> onMarkerTapped,
  required double initialLat,
  required double initialLng,
  required ValueChanged<LatLngBounds?>? onBoundsChanged,
}) {
  return Stack(
    key: const Key('test-map-container'),
    children: [
      Container(
        color: Colors.grey.shade200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map, size: 48, color: Colors.black38),
              const SizedBox(height: 8),
              Text(
                'Mapa de prueba (${leaks.length} fugas)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (selectedLeak != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Seleccionado: ${selectedLeak.id}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.primary),
                ),
              ],
            ],
          ),
        ),
      ),
      for (final leak in leaks)
        if (leak.hasCoordinates)
          Positioned(
            key: mapMarkerKey(leak.id),
            left: (leak.longitude! + 64) * 10,
            top: (11 - leak.latitude!) * 10,
            child: GestureDetector(
              onTap: () => onMarkerTapped(leak),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: leak.isResolved ? AppColors.success : AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: selectedLeak?.id == leak.id ? 3 : 1.5,
                  ),
                ),
              ),
            ),
          ),
    ],
  );
}

LeakSummary _summary({
  required String id,
  String status = 'ACTIVE',
  int validations = 1,
  int confirmations = 0,
  String? sector = 'La Caranta',
  String? municipality = 'Maneiro',
  double? lat = 10.99,
  double? lng = -63.87,
}) => LeakSummary(
  id: id,
  status: status,
  validationCount: validations,
  resolutionConfirmationCount: confirmations,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  sectorName: sector,
  municipalityName: municipality,
  latitude: lat,
  longitude: lng,
);

Future<void> _pumpMapScreen(
  WidgetTester tester,
  _MockLeakCommunityRepository repository, {
  List<LeakSummary> reports = const [],
  Object? error,
}) async {
  when(
    () => repository.mapReports(
      status: any(named: 'status'),
      sectorId: any(named: 'sectorId'),
      minLat: any(named: 'minLat'),
      minLng: any(named: 'minLng'),
      maxLat: any(named: 'maxLat'),
      maxLng: any(named: 'maxLng'),
      orderBy: any(named: 'orderBy'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async {
    if (error != null) throw error;
    return reports;
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        leakCommunityRepositoryProvider.overrideWithValue(repository),
        mapWidgetBuilderProvider.overrideWithValue(_testMapBuilder),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const MapScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pump helper con NavigatorObserver para tests de navegación.
Future<void> _pumpMapScreenWithObserver(
  WidgetTester tester,
  _MockLeakCommunityRepository repository,
  NavigatorObserver observer, {
  List<LeakSummary> reports = const [],
}) async {
  when(
    () => repository.mapReports(
      status: any(named: 'status'),
      sectorId: any(named: 'sectorId'),
      minLat: any(named: 'minLat'),
      minLng: any(named: 'minLng'),
      maxLat: any(named: 'maxLat'),
      maxLng: any(named: 'maxLng'),
      orderBy: any(named: 'orderBy'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async => reports);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        leakCommunityRepositoryProvider.overrideWithValue(repository),
        mapWidgetBuilderProvider.overrideWithValue(_testMapBuilder),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const MapScreen(),
        navigatorObservers: [observer],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeRoute());
  });

  group('MapScreen', () {
    late _MockLeakCommunityRepository repository;

    setUp(() {
      repository = _MockLeakCommunityRepository();
    });

    testWidgets('muestra estado de carga inicial', (tester) async {
      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) => Future.delayed(const Duration(seconds: 1), () => []));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leakCommunityRepositoryProvider.overrideWithValue(repository),
            mapWidgetBuilderProvider.overrideWithValue(_testMapBuilder),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const MapScreen()),
        ),
      );

      // B1: el mapa queda montado también durante la carga inicial (el estado
      // de carga es un overlay, no un reemplazo).
      expect(find.byKey(gotaMapContainerKey), findsOneWidget);
      expect(find.byKey(mapLoadingStateKey), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('muestra estado vacío cuando no hay fugas', (tester) async {
      await _pumpMapScreen(tester, repository, reports: []);

      // El mapa sigue montado — no se muestra overlay de área vacía.
      expect(find.byKey(gotaMapContainerKey), findsOneWidget);
      expect(find.text('Sin fugas para mostrar'), findsNothing);
    });

    testWidgets('muestra error de red con botón de reintento', (tester) async {
      await _pumpMapScreen(tester, repository, error: const NetworkException());

      expect(find.byKey(mapErrorStateKey), findsOneWidget);
      expect(
        find.text('Sin conexión. Verifica tu red e intenta de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('muestra lista de fugas en modo mapa', (tester) async {
      await _pumpMapScreen(
        tester,
        repository,
        reports: [
          _summary(id: 'r1', validations: 3),
          _summary(id: 'r2', status: 'RESOLVED', confirmations: 3),
        ],
      );

      expect(find.byKey(gotaMapContainerKey), findsOneWidget);
    });

    testWidgets('cambia a vista de lista al tocar toggle', (tester) async {
      await _pumpMapScreen(
        tester,
        repository,
        reports: [
          _summary(id: 'r1'),
          _summary(id: 'r2', status: 'RESOLVED'),
        ],
      );

      // Initially in map mode
      expect(find.byKey(gotaMapContainerKey), findsOneWidget);

      // Tap the view mode toggle
      await tester.tap(find.byKey(mapViewToggleKey));
      await tester.pumpAndSettle();

      // Should be in list mode
      expect(find.byKey(mapListViewKey), findsOneWidget);
    });

    testWidgets('abre filtro y cambia a Activas', (tester) async {
      await _pumpMapScreen(
        tester,
        repository,
        reports: [
          _summary(id: 'r1'),
          _summary(id: 'r2', status: 'RESOLVED'),
        ],
      );

      // El filtro por defecto ("Todas") ya usa status=ACTIVE; limpiamos las
      // interacciones previas para aislar la llamada del tap en "Activas".
      clearInteractions(repository);
      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => [_summary(id: 'r1')]);

      // H: "Activas" ahora es un chip directo, no un ítem de popup.
      await tester.tap(find.text('Activas'));
      await tester.pumpAndSettle();

      // Verify the filter was applied by checking repository was called with status=ACTIVE
      verify(
        () => repository.mapReports(
          status: 'ACTIVE',
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: 'recent',
          limit: 100,
        ),
      ).called(1);
    });

    testWidgets(
      'filtro Mi sector sin sector ni ubicación retorna vacío con mensaje específico',
      (tester) async {
        await _pumpMapScreen(tester, repository, reports: [_summary(id: 'r1')]);

        // H: "Mi sector" es ahora un chip directo en la barra superior.
        await tester.tap(find.text('Mi sector'));
        await tester.pumpAndSettle();

        expect(find.byKey(mapEmptyStateKey), findsOneWidget);
        expect(
          find.text('Configura tu sector'),
          findsOneWidget,
          reason: 'debe mostrar título específico para Mi sector',
        );
        expect(
          find.text(
            'Para usar el filtro "Mi sector", establece tu sector desde tu perfil.',
          ),
          findsOneWidget,
          reason: 'debe mostrar descripción específica para Mi sector',
        );
      },
    );

    testWidgets('filtro Más validadas usa orderBy validated', (tester) async {
      await _pumpMapScreen(
        tester,
        repository,
        reports: [_summary(id: 'r1', validations: 10)],
      );

      await tester.tap(find.byKey(mapFilterMenuKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Más validadas'));
      await tester.pumpAndSettle();

      verify(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: 'validated',
          limit: any(named: 'limit'),
        ),
      ).called(1);
    });

    testWidgets('filtro Recientes usa orderBy recent sin filtro de estado', (
      tester,
    ) async {
      await _pumpMapScreen(tester, repository, reports: [_summary(id: 'r1')]);

      // Cambia a Resueltas para que el estado del provider sea distinto.
      await tester.tap(find.byKey(mapFilterMenuKey));
      await tester.pumpAndSettle();
      // Sprint 09-UI: los chips de la superficie y los ítems del popup
      // comparten texto; el tap se limita al ítem del popup para desambiguar.
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<MapFilterType>),
          matching: find.text('Resueltas'),
        ),
      );
      await tester.pumpAndSettle();

      // Resetea el contador de invocaciones del mock para aislar la siguiente llamada.
      clearInteractions(repository);
      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => [_summary(id: 'r1')]);

      // H: "Recientes" es ahora un chip directo en la barra superior.
      await tester.tap(find.text('Recientes'));
      await tester.pumpAndSettle();

      verify(
        () => repository.mapReports(
          status: null,
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: 'recent',
          limit: any(named: 'limit'),
        ),
      ).called(1);
    });

    testWidgets(
      'filtro Mi sector con sector preseleccionado filtra por sectorId',
      (tester) async {
        await _pumpMapScreen(tester, repository, reports: [_summary(id: 'r1')]);

        // Establece el sector vía el notifier (equivale a que el usuario lo haya
        // seleccionado en un paso previo de la UI).
        final element = tester.element(find.byType(MapScreen));
        ProviderScope.containerOf(element)
            .read(mapFilterProvider.notifier)
            .setSectorId('sector-abc');
        await tester.pumpAndSettle();

        verify(
          () => repository.mapReports(
            status: any(named: 'status'),
            sectorId: 'sector-abc',
            minLat: any(named: 'minLat'),
            minLng: any(named: 'minLng'),
            maxLat: any(named: 'maxLat'),
            maxLng: any(named: 'maxLng'),
            orderBy: any(named: 'orderBy'),
            limit: any(named: 'limit'),
          ),
        ).called(greaterThanOrEqualTo(1));
      },
    );

    // --- Tests nuevos PROMPT 2 ---

    testWidgets('estado vacío en modo mapa no desmonta el mapa', (
      tester,
    ) async {
      await _pumpMapScreen(tester, repository, reports: []);

      // El mapa siempre debe estar montado; sin overlay flotante de área vacía.
      expect(find.byKey(gotaMapContainerKey), findsOneWidget);
      expect(find.byKey(mapEmptyStateKey), findsNothing);
    });

    testWidgets('el mapa sigue montado durante y después de una recarga vacía', (
      tester,
    ) async {
      // Carga inicial vacía.
      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leakCommunityRepositoryProvider.overrideWithValue(repository),
            mapWidgetBuilderProvider.overrideWithValue(_testMapBuilder),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const MapScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(gotaMapContainerKey), findsOneWidget);
      expect(find.byKey(mapEmptyStateKey), findsNothing);

      // Re-fetch con respuesta lenta (consulta en vuelo).
      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) => Future.delayed(const Duration(milliseconds: 500), () => []),
      );

      final element = tester.element(find.byType(MapScreen));
      ProviderScope.containerOf(element).invalidate(mapReportsProvider);
      await tester.pump(); // inicia la recarga

      // Durante la recarga: mapa montado, sin overlay (C1/C6).
      expect(find.byKey(gotaMapContainerKey), findsOneWidget);
      expect(find.byKey(mapEmptyStateKey), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'Mi sector sin selección muestra la guía y no el overlay vacío',
      (tester) async {
        await _pumpMapScreen(tester, repository, reports: [_summary(id: 'r1')]);

        // H: "Mi sector" es ahora un chip directo en la barra superior.
        await tester.tap(find.text('Mi sector'));
        await tester.pumpAndSettle();

        // Vista de guía completa (C2): mapEmptyStateKey con "Configura tu sector".
        expect(find.byKey(mapEmptyStateKey), findsOneWidget);
        expect(find.text('Configura tu sector'), findsOneWidget);
        // El mapa no debe estar montado: esta vista reemplaza al mapa (C2).
        expect(find.byKey(gotaMapContainerKey), findsNothing);
      },
    );

    testWidgets('el estado vacío no limpia los bounds', (tester) async {
      await _pumpMapScreen(tester, repository, reports: []);

      final element = tester.element(find.byType(MapScreen));
      final container = ProviderScope.containerOf(element);

      // Simula que el viewport ya tenía bounds establecidos.
      container
          .read(mapFilterProvider.notifier)
          .setBounds(10.5, -64.0, 11.0, -63.5);
      await tester.pumpAndSettle();

      // Los bounds deben conservarse: ningún render llama a clearBounds() (C4).
      final state = container.read(mapFilterProvider);
      expect(state.hasBounds, isTrue);
      expect(state.minLat, equals(10.5));
      expect(state.minLng, equals(-64.0));
      expect(state.maxLat, equals(11.0));
      expect(state.maxLng, equals(-63.5));
    });

    // --- Mutation control tests B2-B5 ---

    testWidgets('B2: cámara estable en Mi sector tras refetch', (tester) async {
      await _pumpMapScreen(tester, repository, reports: [_summary(id: 'r1')]);

      final element = tester.element(find.byType(MapScreen));
      final container = ProviderScope.containerOf(element);
      final notifier = container.read(mapFilterProvider.notifier);
      notifier.setSectorId('sector-123');
      await tester.pumpAndSettle();

      final centerBefore = container.read(mapFilterProvider).sectorCenterLat;

      // Refetch con datos distintos
      final newReports = [_summary(id: 'r2', lat: 11.5, lng: -64.5)];
      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => newReports);

      container.invalidate(mapReportsProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final centerAfter = container.read(mapFilterProvider).sectorCenterLat;
      expect(centerAfter, equals(centerBefore));
    });
    // MUTATION: revertir setSectorCenter → B2 → ROJO / restaurado → VERDE

    testWidgets('B3: markers previos preservados durante refetch', (
      tester,
    ) async {
      await _pumpMapScreen(tester, repository, reports: [_summary(id: 'r1')]);
      expect(find.byKey(mapMarkerKey('r1')), findsOneWidget);

      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) => Future.delayed(
          const Duration(milliseconds: 500),
          () => [_summary(id: 'r2')],
        ),
      );

      final element = tester.element(find.byType(MapScreen));
      ProviderScope.containerOf(element).invalidate(mapReportsProvider);
      await tester.pump();

      expect(find.byKey(mapMarkerKey('r1')), findsOneWidget);
      expect(find.byKey(mapEmptyStateKey), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byKey(mapMarkerKey('r2')), findsOneWidget);
    });
    // MUTATION: quitar skipLoadingOnReload → B3 → ROJO / restaurado → VERDE

    testWidgets('B4: respuesta fuera de orden usa la última', (tester) async {
      // La primera consulta queda en vuelo (lenta); la segunda llega antes.
      // La respuesta obsoleta NO debe pisar a la nueva.
      final slow = Completer<List<LeakSummary>>();
      final fast = Completer<List<LeakSummary>>();
      var calls = 0;
      when(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) {
        calls++;
        return calls == 1 ? slow.future : fast.future;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leakCommunityRepositoryProvider.overrideWithValue(repository),
            mapWidgetBuilderProvider.overrideWithValue(_testMapBuilder),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const MapScreen()),
        ),
      );
      await tester.pump();

      final element = tester.element(find.byType(MapScreen));
      ProviderScope.containerOf(element).invalidate(mapReportsProvider);
      await tester.pump();
      expect(calls, greaterThanOrEqualTo(2));

      // Llega la consulta nueva (la segunda).
      fast.complete([_summary(id: 'nueva')]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(mapMarkerKey('nueva')), findsOneWidget);

      // Llega la vieja, ya obsoleta: no debe reemplazar a la nueva.
      slow.complete([_summary(id: 'obsoleta')]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(mapMarkerKey('obsoleta')), findsNothing);
      expect(find.byKey(mapMarkerKey('nueva')), findsOneWidget);
    });
    // MUTATION: si el provider dejara ganar a la respuesta obsoleta → B4 → ROJO.
    // Leído: riverpod-3.4.3/lib/src/core/element.dart (handleFuture → running flag
    // descarta el future anterior cuando la consulta se reemplaza).

    testWidgets('B5: setBounds con temblor mínimo no dispara consulta', (
      tester,
    ) async {
      await _pumpMapScreen(tester, repository, reports: [_summary(id: 'r1')]);

      final element = tester.element(find.byType(MapScreen));
      final container = ProviderScope.containerOf(element);
      final notifier = container.read(mapFilterProvider.notifier);

      notifier.setBounds(10.5, -64.0, 11.0, -63.5);
      // Dejar que la reacción dispare y complete la consulta del primer bounds
      // ANTES de limpiar el registro de llamadas.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      clearInteractions(repository);

      notifier.setBounds(10.5 + 1e-6, -64.0 + 1e-6, 11.0 + 1e-6, -63.5 + 1e-6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      verifyNever(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      );

      notifier.setBounds(10.6, -64.1, 11.1, -63.6);
      await tester.pump();
      verify(
        () => repository.mapReports(
          status: any(named: 'status'),
          sectorId: any(named: 'sectorId'),
          minLat: any(named: 'minLat'),
          minLng: any(named: 'minLng'),
          maxLat: any(named: 'maxLat'),
          maxLng: any(named: 'maxLng'),
          orderBy: any(named: 'orderBy'),
          limit: any(named: 'limit'),
        ),
      ).called(1);
    });
    // MUTATION: quitar _boundsTolerance → B5 → ROJO / restaurado → VERDE

    // --- Fin tests nuevos PROMPT 2 ---

    testWidgets('tocar marker muestra tarjeta y permite ver detalle', (
      tester,
    ) async {
      final observer = _MockNavigatorObserver();
      await _pumpMapScreenWithObserver(
        tester,
        repository,
        observer,
        reports: [_summary(id: 'r1')],
      );
      clearInteractions(observer);

      await tester.tap(find.byKey(mapMarkerKey('r1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('map-selection-card')), findsOneWidget);
      expect(find.text('Ver detalle'), findsOneWidget);
      verifyNever(() => observer.didPush(any(), any()));

      await tester.tap(find.byKey(const Key('map-view-detail-button')));
      await tester.pump();
      verify(() => observer.didPush(any(), any())).called(1);
    });

    testWidgets('tocar card en vista lista desencadena navegación al detalle', (
      tester,
    ) async {
      final observer = _MockNavigatorObserver();
      await _pumpMapScreenWithObserver(
        tester,
        repository,
        observer,
        reports: [_summary(id: 'r1')],
      );

      await tester.tap(find.byKey(mapViewToggleKey));
      await tester.pumpAndSettle();

      // Reset después de pumpAndSettle para aislar el tap de la card.
      clearInteractions(observer);

      await tester.tap(find.byKey(mapLeakCardKey('r1')));
      await tester.pump();

      verify(() => observer.didPush(any(), any())).called(1);
    });
  });

  group('MapFilterNotifier', () {
    test('estado inicial es all + map', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(mapFilterProvider.notifier);
      final state = notifier.build();

      expect(state.filterType, equals(MapFilterType.all));
      expect(state.viewMode, equals(MapViewMode.map));
      expect(state.selectedSectorId, isNull);
      expect(state.hasUserLocation, isFalse);
    });

    test('setFilter cambia el tipo de filtro', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(mapFilterProvider.notifier);
      notifier.setFilter(MapFilterType.active);

      expect(notifier.state.filterType, equals(MapFilterType.active));
    });

    test('setViewMode alterna entre mapa y lista', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(mapFilterProvider.notifier);
      notifier.setViewMode(MapViewMode.list);

      expect(notifier.state.viewMode, equals(MapViewMode.list));
    });

    test('setSectorId establece sector y cambia filtro a mySector', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(mapFilterProvider.notifier);
      notifier.setSectorId('sector-123');

      expect(notifier.state.selectedSectorId, equals('sector-123'));
      expect(notifier.state.filterType, equals(MapFilterType.mySector));
    });

    test('setUserLocation guarda coordenadas', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(mapFilterProvider.notifier);
      notifier.setUserLocation(10.5, -64.0);

      expect(notifier.state.userLatitude, equals(10.5));
      expect(notifier.state.userLongitude, equals(-64.0));
      expect(notifier.state.hasUserLocation, isTrue);
    });

    test('clearSector limpia el sector seleccionado', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(mapFilterProvider.notifier);
      notifier.setSectorId('sector-123');
      notifier.clearSector();

      expect(notifier.state.selectedSectorId, isNull);
    });

    test('copyWith preserva valores no modificados', () {
      const state = MapFilterState(
        filterType: MapFilterType.active,
        viewMode: MapViewMode.list,
        selectedSectorId: 'sector-1',
        userLatitude: 10.0,
        userLongitude: -63.0,
      );

      final copy = state.copyWith(filterType: MapFilterType.resolved);

      expect(copy.filterType, equals(MapFilterType.resolved));
      expect(copy.viewMode, equals(MapViewMode.list));
      expect(copy.selectedSectorId, equals('sector-1'));
      expect(copy.userLatitude, equals(10.0));
    });

    test('setBounds guarda el bounding box del viewport', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(mapFilterProvider.notifier);
      notifier.setBounds(10.5, -64.0, 11.0, -63.5);

      expect(notifier.state.minLat, equals(10.5));
      expect(notifier.state.minLng, equals(-64.0));
      expect(notifier.state.maxLat, equals(11.0));
      expect(notifier.state.maxLng, equals(-63.5));
      expect(notifier.state.hasBounds, isTrue);
    });
  });
}
