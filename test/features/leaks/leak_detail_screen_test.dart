import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gota/app/theme/app_theme.dart';
import 'package:gota/core/errors/app_exception.dart';
import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/leaks/domain/leak_community_errors.dart';
import 'package:gota/features/leaks/presentation/leak_detail_screen.dart';

const _reportId = 'r1';

LeakDetail _detail({
  String status = 'ACTIVE',
  int validations = 2,
  int confirmations = 1,
  int threshold = 3,
  bool isCreator = false,
  bool isBlocked = false,
  bool alreadyValidated = false,
  bool alreadyConfirmed = false,
  DateTime? resolvedAt,
  int photoCount = 2,
}) => LeakDetail(
  id: _reportId,
  status: status,
  validationCount: validations,
  resolutionConfirmationCount: confirmations,
  threshold: threshold,
  createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  resolvedAt: resolvedAt,
  description: 'Tubería rota en la esquina',
  locationSource: 'GPS',
  municipalityName: 'Maneiro',
  sectorName: 'La Caranta',
  latitude: 10.99,
  longitude: -63.87,
  photoCount: photoCount,
  isCreator: isCreator,
  isBlocked: isBlocked,
  alreadyValidated: alreadyValidated,
  alreadyConfirmed: alreadyConfirmed,
);

class _FakeLeakCommunityRepository implements LeakCommunityRepository {
  _FakeLeakCommunityRepository({required this.detail});

  LeakDetail detail;
  final List<LeakSummary> list = const [];

  Object? detailError;
  Object? actionError;
  CommunityActionResult? validateResult;
  CommunityActionResult? confirmResult;

  /// Permite mantener una acción "en vuelo" para probar loading y doble tap.
  Completer<void>? actionGate;
  Completer<void>? detailGate;

  int validateCalls = 0;
  int confirmCalls = 0;

  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async => list;

  @override
  Future<List<LeakSummary>> mapReports({
    String? status,
    String? sectorId,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    String orderBy = 'recent',
    int limit = 100,
  }) async => list;

  @override
  Future<LeakDetail> reportDetail(String reportId) async {
    if (detailGate != null) await detailGate!.future;
    if (detailError != null) throw detailError!;
    return detail;
  }

  @override
  Future<CommunityActionResult> validateLeak(String reportId) async {
    validateCalls++;
    if (actionGate != null) await actionGate!.future;
    if (actionError != null) throw actionError!;
    return validateResult ??
        CommunityActionResult(
          status: detail.status,
          validationCount: detail.validationCount,
          resolutionConfirmationCount: detail.resolutionConfirmationCount,
          threshold: detail.threshold,
        );
  }

  @override
  Future<CommunityActionResult> confirmResolution(String reportId) async {
    confirmCalls++;
    if (actionGate != null) await actionGate!.future;
    if (actionError != null) throw actionError!;
    return confirmResult ??
        CommunityActionResult(
          status: detail.status,
          validationCount: detail.validationCount,
          resolutionConfirmationCount: detail.resolutionConfirmationCount,
          threshold: detail.threshold,
        );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeLeakCommunityRepository repository, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        leakCommunityRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const LeakDetailScreen(reportId: _reportId),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra estado, contadores y progreso comunitario', (
    tester,
  ) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(validations: 2, confirmations: 1),
    );

    await _pump(tester, repository);

    expect(find.text('Fuga activa'), findsOneWidget);
    expect(find.text('2 validaciones'), findsOneWidget);
    expect(
      find.text('1 de 3 personas han confirmado que la fuga fue resuelta.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(leakValidateButtonKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('validar: solo anuncia el resultado que confirma el backend', (
    tester,
  ) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(validations: 2, confirmations: 1),
    );
    repository.validateResult = const CommunityActionResult(
      status: 'ACTIVE',
      validationCount: 3,
      resolutionConfirmationCount: 1,
      threshold: 3,
    );

    await _pump(tester, repository);

    await tester.tap(find.byKey(leakValidateButtonKey));
    // El estado real ya cambió en el backend: la siguiente lectura lo refleja.
    repository.detail = _detail(
      validations: 3,
      confirmations: 1,
      alreadyValidated: true,
    );
    await tester.pumpAndSettle();

    expect(repository.validateCalls, 1);
    expect(find.text('Fuga validada. 3 validaciones.'), findsOneWidget);
    expect(find.text('3 validaciones'), findsOneWidget);
    // Tras validar, la acción queda deshabilitada y con mensaje claro.
    expect(
      tester.widget<FilledButton>(find.byKey(leakValidateButtonKey)).onPressed,
      isNull,
    );
    expect(find.text('Ya validaste este reporte'), findsWidgets);
  });

  testWidgets('el creador no puede validar su propia fuga', (tester) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(isCreator: true, validations: 0),
    );

    await _pump(tester, repository);

    expect(
      tester.widget<FilledButton>(find.byKey(leakValidateButtonKey)).onPressed,
      isNull,
    );
    expect(find.text('No puedes validar tu propio reporte'), findsOneWidget);
    // El creador sí puede confirmar la resolución.
    expect(
      tester.widget<OutlinedButton>(find.byKey(leakConfirmButtonKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('usuario bloqueado: ninguna acción disponible', (tester) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(isBlocked: true),
    );

    await _pump(tester, repository);

    expect(
      tester.widget<FilledButton>(find.byKey(leakValidateButtonKey)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(leakConfirmButtonKey)).onPressed,
      isNull,
    );
    expect(find.text('Tu acceso está bloqueado'), findsOneWidget);
  });

  testWidgets('confirmar resolución: umbral no alcanzado no anuncia resuelta', (
    tester,
  ) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(confirmations: 1),
    );
    repository.confirmResult = const CommunityActionResult(
      status: 'ACTIVE',
      validationCount: 2,
      resolutionConfirmationCount: 2,
      threshold: 3,
    );

    await _pump(tester, repository);

    await tester.tap(find.byKey(leakConfirmButtonKey));
    repository.detail = _detail(confirmations: 2, alreadyConfirmed: true);
    await tester.pumpAndSettle();

    expect(repository.confirmCalls, 1);
    expect(
      find.text('Gracias. Falta 1 confirmación para marcarla como resuelta.'),
      findsOneWidget,
    );
    expect(find.text('Fuga resuelta'), findsNothing);
    expect(
      find.text('2 de 3 personas han confirmado que la fuga fue resuelta.'),
      findsOneWidget,
    );
  });

  testWidgets('confirmar resolución: el umbral alcanzado viene del backend', (
    tester,
  ) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(confirmations: 2),
    );
    repository.confirmResult = CommunityActionResult(
      status: 'RESOLVED',
      validationCount: 2,
      resolutionConfirmationCount: 3,
      threshold: 3,
      resolvedAt: DateTime.now(),
    );

    await _pump(tester, repository);

    await tester.tap(find.byKey(leakConfirmButtonKey));
    repository.detail = _detail(
      status: 'RESOLVED',
      confirmations: 3,
      alreadyConfirmed: true,
      alreadyValidated: true,
      resolvedAt: DateTime.now(),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('La comunidad confirmó que la fuga fue resuelta.'),
      findsOneWidget,
    );
    expect(find.text('Fuga resuelta'), findsOneWidget);
    expect(
      find.text('3 de 3 personas han confirmado que la fuga fue resuelta.'),
      findsOneWidget,
    );
  });

  testWidgets('fuga resuelta: no muestra acciones incompatibles', (
    tester,
  ) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(
        status: 'RESOLVED',
        confirmations: 3,
        alreadyConfirmed: true,
        alreadyValidated: true,
        resolvedAt: DateTime(2026, 1, 2, 10),
      ),
    );

    await _pump(tester, repository);

    expect(find.text('Fuga resuelta'), findsOneWidget);
    expect(find.byKey(leakValidateButtonKey), findsNothing);
    expect(find.byKey(leakConfirmButtonKey), findsNothing);
    expect(find.textContaining('Resuelta el'), findsOneWidget);
  });

  testWidgets('error del backend: no se anuncia éxito', (tester) async {
    final repository = _FakeLeakCommunityRepository(
      detail: _detail(isBlocked: false),
    );
    repository.actionError = const DuplicateCommunityActionException(
      'Ya validaste este reporte.',
    );

    await _pump(tester, repository);

    await tester.tap(find.byKey(leakValidateButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Ya validaste este reporte.'), findsOneWidget);
    expect(find.textContaining('Fuga validada'), findsNothing);
  });

  testWidgets('error de red: mensaje claro y sin éxito', (tester) async {
    final repository = _FakeLeakCommunityRepository(detail: _detail());
    repository.actionError = const NetworkException();

    await _pump(tester, repository);

    await tester.tap(find.byKey(leakValidateButtonKey));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No pudimos conectar. Revisa tu conexión a internet e '
        'intenta de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Fuga validada'), findsNothing);
  });

  testWidgets('doble tap: la acción se ejecuta una sola vez', (tester) async {
    final repository = _FakeLeakCommunityRepository(detail: _detail());
    repository.actionGate = Completer<void>();

    await _pump(tester, repository);

    await tester.scrollUntilVisible(
      find.byKey(leakValidateButtonKey),
      200,
    );
    await tester.tap(find.byKey(leakValidateButtonKey));
    await tester.pump();

    // Mientras la acción está en vuelo el botón queda deshabilitado.
    expect(
      tester.widget<FilledButton>(find.byKey(leakValidateButtonKey)).onPressed,
      isNull,
    );
    expect(find.byKey(leakActionProgressKey), findsOneWidget);

    await tester.tap(find.byKey(leakValidateButtonKey), warnIfMissed: false);
    await tester.pump();

    repository.actionGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.validateCalls, 1);
  });

  testWidgets('estado de carga mientras se obtiene el detalle', (tester) async {
    final repository = _FakeLeakCommunityRepository(detail: _detail());
    repository.detailGate = Completer<void>();

    await _pump(tester, repository, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.detailGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Fuga activa'), findsOneWidget);
  });

  testWidgets('error al cargar el detalle ofrece reintentar', (tester) async {
    final repository = _FakeLeakCommunityRepository(detail: _detail());
    repository.detailError = const NetworkException();

    await _pump(tester, repository);

    expect(find.textContaining('No pudimos conectar'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    repository.detailError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Fuga activa'), findsOneWidget);
  });
}
