import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../data/water_event_repository.dart';
import '../domain/water_errors.dart';
import '../domain/water_event_age.dart';
import 'water_copy.dart';
import 'water_providers.dart';

/// Pantalla de detalle de un evento de agua: muestra el evento completo,
/// validaciones y la acción de validación (si aplica).
class WaterEventDetailScreen extends ConsumerStatefulWidget {
  const WaterEventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<WaterEventDetailScreen> createState() =>
      _WaterEventDetailScreenState();
}

class _WaterEventDetailScreenState
    extends ConsumerState<WaterEventDetailScreen> {
  bool _isValidating = false;

  Future<void> _validate() async {
    if (_isValidating) return;

    setState(() => _isValidating = true);
    try {
      final repository = ref.read(waterEventRepositoryProvider);
      await repository.validate(widget.eventId);

      if (!mounted) return;

      // Recarga el detalle para reflejar el nuevo estado.
      ref.invalidate(waterEventDetailProvider(widget.eventId));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(WaterCopy.validatedSnack),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on WaterException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.danger,
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(waterEventDetailProvider(widget.eventId));
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text(WaterCopy.screenTitle)),
      body: detailAsync.when(
        loading: () => const LoadingView(message: 'Cargando evento…'),
        error: (error, _) => ErrorView(
          message: _messageFor(error),
          onRetry: () =>
              ref.invalidate(waterEventDetailProvider(widget.eventId)),
        ),
        data: (detail) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Encabezado: tipo + ubicación
                Row(
                  children: [
                    Icon(
                      detail.type.wireName == 'WATER_ARRIVED'
                          ? Icons.water_drop
                          : Icons.water_drop_outlined,
                      color: detail.type.wireName == 'WATER_ARRIVED'
                          ? AppColors.primary
                          : AppColors.danger,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.type.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (detail.sectorName != null ||
                              detail.municipalityName != null)
                            Text(
                              [
                                if (detail.sectorName != null)
                                  detail.sectorName!,
                                if (detail.municipalityName != null)
                                  detail.municipalityName!,
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Información del evento
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(
                          label: 'Hora del evento',
                          value: describeWaterEventTime(
                            detail.eventTime,
                            now: now,
                          ),
                        ),
                        const Divider(),
                        _DetailRow(
                          label: 'Registrado hace',
                          value: describeWaterEventTime(
                            detail.createdAt,
                            now: now,
                          ),
                        ),
                        if (detail.comment != null &&
                            detail.comment!.isNotEmpty) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Comentario',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(detail.comment!),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Validaciones comunitarias
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          WaterCopy.validationCount(detail.validationCount),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Personas que han confirmado este evento.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Estado y acciones
                if (detail.isBlocked)
                  Card(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.block, color: AppColors.danger),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              WaterCopy.blocked,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (detail.isCreator)
                  Card(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.info, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              WaterCopy.cannotValidateOwn,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (detail.alreadyValidated)
                  Card(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              WaterCopy.alreadyValidated,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isValidating ? null : _validate,
                      child: _isValidating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(WaterCopy.validate),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    if (error is WaterException) return error.userMessage;
    if (error is AppException) return error.userMessage;
    return WaterCopy.loadError;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
