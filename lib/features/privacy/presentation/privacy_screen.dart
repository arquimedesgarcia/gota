import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Best-effort: si no se puede abrir, no crashear
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad y Términos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Privacidad ────────────────────────────────────────────────────
          Text('Privacidad', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Gota recolecta tu ubicación GPS solo cuando inicias un reporte, '
            'las fotos que eliges adjuntar y un identificador anónimo único. '
            'No pedimos nombre, correo ni teléfono. Los reportes son visibles '
            'para otros usuarios, pero tu identidad no. Nunca rastreamos tu '
            'posición en segundo plano ni compartimos tus datos con terceros.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ver política completa'),
            onPressed: () => _launch(AppConfig.privacyUrl),
          ),
          const SizedBox(height: 24),
          // ── Términos y Condiciones ─────────────────────────────────────────
          Text(
            'Términos y Condiciones',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Gota es una herramienta informativa comunitaria. Los reportes son '
            'generados por usuarios y no son verificados. Gota no es un '
            'servicio de emergencias ni está afiliada a Hidroven ni a entes '
            'oficiales. Eres responsable del contenido que publicas. La app se '
            'entrega "tal cual", sin garantías de disponibilidad o exactitud.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ver términos completos'),
            onPressed: () => _launch(AppConfig.termsUrl),
          ),
          const SizedBox(height: 24),
          // ── Contacto ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contacto',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                const Text(AppConfig.contactEmail),
                const SizedBox(height: 8),
                const Text(
                  'Denuncia contenido inapropiado: '
                  '${AppConfig.contactEmail}',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
