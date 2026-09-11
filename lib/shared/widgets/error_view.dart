import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';

/// Contenido de error con mensaje amigable y acción opcional de reintento.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.black38,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pantalla completa cuando falta la configuración de Supabase.
class ConfigMissingView extends StatelessWidget {
  const ConfigMissingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ErrorView(
          message:
              '${const ConfigMissingException().userMessage}\n'
              'Reinicia la aplicación. Si el problema continúa, instala la '
              'última versión.',
        ),
      ),
    );
  }
}
