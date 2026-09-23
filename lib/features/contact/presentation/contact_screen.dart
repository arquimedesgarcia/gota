import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/network/network_providers.dart';
import '../../../shared/widgets/app_components.dart';

/// Pantalla de contacto (BLOQUE I).
/// Almacena el mensaje en `contact_messages` vía insert directo con RLS insert-only.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _mensajeCtrl = TextEditingController();

  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _mensajeCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await ref.read(supabaseClientProvider).from('contact_messages').insert({
        'nombre': _nombreCtrl.text.trim(),
        if (_correoCtrl.text.trim().isNotEmpty)
          'correo': _correoCtrl.text.trim(),
        'mensaje': _mensajeCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'No pudimos enviar el mensaje. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacto')),
      body: SafeArea(
        child: _sent ? _buildSuccess(context) : _buildForm(context),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 64, color: AppColors.success),
            const SizedBox(height: 16),
            Text(
              '¡Mensaje enviado!',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Gracias por escribirnos. Te responderemos pronto.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: AppComponents.secondaryButtonStyle(),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Volver'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Tienes alguna pregunta o comentario? Escríbenos.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nombreCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Tu nombre',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
              enabled: !_sending,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _correoCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico (opcional)',
                hintText: 'tu@correo.com',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());
                return ok ? null : 'Ingresa un correo válido';
              },
              enabled: !_sending,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mensajeCtrl,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Mensaje *',
                hintText: '¿En qué podemos ayudarte?',
                alignLabelWithHint: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El mensaje es obligatorio' : null,
              enabled: !_sending,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            _sending
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(
                    style: AppComponents.primaryButtonStyle(),
                    onPressed: _send,
                    child: const Text('Enviar mensaje'),
                  ),
          ],
        ),
      ),
    );
  }
}
