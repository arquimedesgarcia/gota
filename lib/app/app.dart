import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_exception.dart';
import '../features/notifications/presentation/notification_providers.dart';
import '../features/privacy/data/permission_prefs.dart';
import '../shared/widgets/error_view.dart';
import '../shared/widgets/loading_view.dart';
import 'providers.dart';
import 'router/app_navigator.dart';
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
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: config == null ? const ConfigMissingView() : const _SessionGate(),
    );
  }
}

class _SessionGate extends ConsumerStatefulWidget {
  const _SessionGate();

  @override
  ConsumerState<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<_SessionGate> {
  bool _firstRunDialogShown = false;

  Future<void> _showTermsDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Bienvenido a Gota'),
        content: const Text(
          'Al usar Gota aceptas los Términos y Condiciones y '
          'la Política de Privacidad. Los reportes son visibles '
          'para otros usuarios (sin identificarte). No es un '
          'servicio de emergencias.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse(AppConfig.termsUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('Ver términos'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showNotifRationaleDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notificaciones'),
        content: const Text(
          'Te avisaremos cuando haya reportes cerca mientras '
          'tengas la app abierta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionBootstrapProvider);
    return session.when(
      loading: () => const Scaffold(
        body: SafeArea(
          child: LoadingView(message: 'Preparando la aplicación…'),
        ),
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
      data: (_) {
        if (!_firstRunDialogShown) {
          _firstRunDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final prefs = await PermissionPrefs.load();
            // Inicializar compuerta de notificaciones desde SharedPreferences
            if (prefs.notifRationaleShown && mounted) {
              ref.read(notifRationaleShownProvider.notifier).setShown();
            }
            if (!mounted) return;
            // Términos y condiciones (primer arranque)
            if (!prefs.termsShown) {
              // ignore: use_build_context_synchronously
              await _showTermsDialog(context);
              await prefs.setTermsShown();
            }
            if (!mounted) return;
            // Diálogo de razonamiento de notificaciones
            if (!prefs.notifRationaleShown) {
              // ignore: use_build_context_synchronously
              await _showNotifRationaleDialog(context);
              await prefs.setNotifRationaleShown();
              if (mounted) {
                ref.read(notifRationaleShownProvider.notifier).setShown();
              }
            }
          });
        }
        // Arranque del push (Sprint 06): los errores internos se tragan en
        // el bootstrap; aquí solo importa observarlo tras la sesión.
        ref.watch(pushBootstrapProvider);
        return const AppShell();
      },
    );
  }
}
