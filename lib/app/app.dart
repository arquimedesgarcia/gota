import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_exception.dart';
import '../shared/widgets/error_view.dart';
import '../shared/widgets/loading_view.dart';
import 'providers.dart';
import 'router/app_shell.dart';
import 'theme/app_theme.dart';

/// Raíz de la aplicación: decide entre configuración faltante,
/// carga de sesión, error con reintento y el shell principal.
class GotaApp extends ConsumerWidget {
  const GotaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    return MaterialApp(
      title: 'Gota',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: config == null ? const ConfigMissingView() : const _SessionGate(),
    );
  }
}

class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionBootstrapProvider);
    return session.when(
      loading: () => const Scaffold(
        body: SafeArea(child: LoadingView(message: 'Preparando la aplicación…')),
      ),
      error: (error, _) => Scaffold(
        body: SafeArea(
          child: ErrorView(
            message: error is AppException
                ? error.userMessage
                : 'No pudimos cargar la información. Intenta de nuevo.',
            onRetry: () => ref.invalidate(sessionBootstrapProvider),
          ),
        ),
      ),
      data: (_) => const AppShell(),
    );
  }
}
