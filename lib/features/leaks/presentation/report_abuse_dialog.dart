import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../data/report_abuse_repository.dart';

const _reasons = [
  ('false_info', 'Información falsa'),
  ('offensive', 'Contenido ofensivo'),
  ('inappropriate_photos', 'Fotos inapropiadas'),
  ('other', 'Otro'),
];

Future<void> showReportAbuseDialog(
  BuildContext context,
  WidgetRef ref,
  String reportId,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReportAbuseDialog(reportId: reportId, ref: ref),
  );
}

class _ReportAbuseDialog extends StatefulWidget {
  const _ReportAbuseDialog({required this.reportId, required this.ref});
  final String reportId;
  final WidgetRef ref;

  @override
  State<_ReportAbuseDialog> createState() => _ReportAbuseDialogState();
}

class _ReportAbuseDialogState extends State<_ReportAbuseDialog> {
  String _selectedReason = 'false_info';
  final _noteController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _submitting = false;
          _error = 'Sesión no disponible. Intenta de nuevo.';
        });
        return;
      }
      // Obtener el app_users.id del usuario actual
      final userRow = await Supabase.instance.client
          .from('app_users')
          .select('id')
          .eq('auth_user_id', user.id)
          .single();
      final reporterId = userRow['id'] as String;

      await widget.ref.read(reportAbuseRepositoryProvider).flagReport(
        reportId: widget.reportId,
        reporterId: reporterId,
        reason: _selectedReason,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Denuncia enviada. Gracias por ayudar.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'No pudimos enviar la denuncia. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reportar contenido'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Por qué deseas reportar este reporte?'),
            const SizedBox(height: 12),
            ..._reasons.map(
              (r) => RadioListTile<String>(
                title: Text(r.$2),
                value: r.$1,
                groupValue: _selectedReason,
                onChanged: (v) => setState(() => _selectedReason = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (_selectedReason == 'other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Describe el problema (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar denuncia'),
        ),
      ],
    );
  }
}
