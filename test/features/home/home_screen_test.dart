import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/features/home/presentation/home_screen.dart';
import 'package:gota/features/map/presentation/map_screen.dart';
import 'package:gota/features/water/presentation/water_register_screen.dart';

class _MockNavigatorObserver extends Mock implements NavigatorObserver {}

class _FakeRoute extends Fake implements Route<dynamic> {}

Future<void> _pumpHomeScreenWithObserver(
  WidgetTester tester,
  NavigatorObserver observer,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: const HomeScreen(),
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

  group('HomeScreen', () {
    late _MockNavigatorObserver observer;

    setUp(() {
      observer = _MockNavigatorObserver();
    });

    testWidgets('tap en "Mapa de fugas" navega a MapScreen', (tester) async {
      await _pumpHomeScreenWithObserver(tester, observer);
      clearInteractions(observer);

      // Encuentra y toca el botón "Mapa de fugas"
      await tester.tap(find.text('Mapa de\nfugas'));
      await tester.pump();

      // Verifica que se hizo push a la navegación
      verify(() => observer.didPush(any(), any())).called(1);

      // Verifica que MapScreen está ahora en la pantalla
      await tester.pumpAndSettle();
      expect(find.byType(MapScreen), findsOneWidget);
    });

    testWidgets(
      'tap en "Llegó / Se fue el agua" navega a WaterRegisterScreen',
      (tester) async {
        await _pumpHomeScreenWithObserver(tester, observer);
        clearInteractions(observer);

        // Encuentra y toca el botón "Llegó / Se fue el agua"
        await tester.tap(find.text('Llegó / Se fue el agua'));
        await tester.pump();

        // Verifica que se hizo push a la navegación
        verify(() => observer.didPush(any(), any())).called(1);

        // Verifica que WaterRegisterScreen está ahora en la pantalla
        await tester.pumpAndSettle();
        expect(find.byType(WaterRegisterScreen), findsOneWidget);
      },
    );

    testWidgets('HomeScreen muestra todas las acciones principales', (
      tester,
    ) async {
      await _pumpHomeScreenWithObserver(tester, observer);

      // Verifica que los textos esperados están presentes
      expect(find.text('GOTA'), findsOneWidget);
      expect(find.text('Reportar fuga'), findsOneWidget);
      expect(find.text('Llegó / Se fue el agua'), findsOneWidget);
      expect(find.text('Mapa de\nfugas'), findsOneWidget);
      expect(find.text('Toma menos de un minuto'), findsOneWidget);
    });
  });
}
