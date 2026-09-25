import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/water_event_type.dart';
import 'water_copy.dart';
import 'water_register_controller.dart';
import 'water_register_step_type.dart';
import 'water_register_step_municipality.dart';
import 'water_register_step_sector.dart';

/// Pantalla del flujo completo de registro de evento de agua
/// (municipio → sector → hora → comentario → revisar).
///
/// El tipo se puede elegir arriba (initialType) o en el primer paso.
/// El flujo devuelve `true` al cerrar si el evento se creó exitosamente.
class WaterRegisterScreen extends ConsumerStatefulWidget {
  const WaterRegisterScreen({super.key, this.initialType});

  final WaterEventType? initialType;

  @override
  ConsumerState<WaterRegisterScreen> createState() =>
      _WaterRegisterScreenState();
}

class _WaterRegisterScreenState extends ConsumerState<WaterRegisterScreen> {
  late WaterEventType _currentType;

  @override
  void initState() {
    super.initState();
    _currentType = widget.initialType ?? WaterEventType.arrived;
    // Siempre limpia el formulario al entrar, incluso si hay estado previo.
    ref.invalidate(waterRegisterControllerProvider);
  }

  Future<void> _submit() async {
    final success = await ref
        .read(waterRegisterControllerProvider.notifier)
        .submit(_currentType);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(WaterCopy.registeredSnack),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(waterRegisterControllerProvider);

    return PopScope(
      canPop: state.submitStatus != WaterRegisterSubmitStatus.submitting,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(WaterCopy.screenTitle),
          leading: state.submitStatus == WaterRegisterSubmitStatus.submitting
              ? null
              : const BackButton(),
        ),
        body: SafeArea(
          child: state.submitStatus == WaterRegisterSubmitStatus.submitting
              ? const LoadingView(message: 'Registrando evento…')
              : Stepper(
                currentStep: state.currentStep,
                onStepContinue: state.currentStep < 3
                    ? () => ref
                          .read(waterRegisterControllerProvider.notifier)
                          .nextStep()
                    : null,
                onStepCancel: state.currentStep > 0
                    ? () => ref
                          .read(waterRegisterControllerProvider.notifier)
                          .previousStep()
                    : null,
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Row(
                      children: [
                        if (details.currentStep < 3)
                          FilledButton.tonal(
                            onPressed: details.onStepContinue,
                            child: const Text('Continuar'),
                          ),
                        if (details.currentStep > 0) ...[
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: details.onStepCancel,
                            child: const Text('Atrás'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                steps: [
                    Step(
                      title: const Text(WaterCopy.stepType),
                      content: WaterRegisterStepType(
                        currentType: _currentType,
                        onTypeSelected: (type) {
                          setState(() => _currentType = type);
                        },
                      ),
                      isActive: state.currentStep >= 0,
                    ),
                    Step(
                      title: const Text(WaterCopy.stepMunicipality),
                      content: const WaterRegisterStepMunicipality(),
                      isActive: state.currentStep >= 1,
                    ),
                    Step(
                      title: const Text(WaterCopy.stepSector),
                      content: const WaterRegisterStepSector(),
                      isActive: state.currentStep >= 2,
                    ),
                    Step(
                      title: const Text('Resumen'),
                      content: Column(
                        children: [
                          if (state.errorMessage != null) ...[
                            _RegisterErrorBanner(
                              message: state.errorMessage!,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _WaterRegisterReview(),
                        ],
                      ),
                      isActive: state.currentStep >= 3,
                    ),
                  ],
                ),
        ),
        floatingActionButton:
            state.submitStatus != WaterRegisterSubmitStatus.submitting &&
                state.currentStep == 3
            ? FloatingActionButton.extended(
                onPressed: _submit,
                icon: const Icon(Icons.check),
                label: const Text(WaterCopy.confirm),
              )
            : null,
      ),
    );
  }
}

/// Resumen del evento con opción de editar la hora.
class _WaterRegisterReview extends ConsumerWidget {
  const _WaterRegisterReview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(waterRegisterControllerProvider);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen del evento',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        _ReviewField(
          label: 'Municipio',
          value: state.municipalityName ?? '—',
        ),
        const SizedBox(height: 12),
        _ReviewField(
          label: 'Sector',
          value: state.sectorName ?? '—',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hora del evento',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    if (state.eventTime != null)
                      Text(
                        _formatEventTime(state.eventTime!, now: now),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openTimePicker(context, ref),
                child: const Text('Editar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (state.comment.isNotEmpty) ...[
          _ReviewField(
            label: 'Comentario',
            value: state.comment,
          ),
        ],
      ],
    );
  }

  Future<void> _openTimePicker(BuildContext context, WidgetRef ref) async {
    final state = ref.read(waterRegisterControllerProvider);
    final initial = state.eventTime ?? DateTime.now();

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (!context.mounted || selectedDate == null) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (!context.mounted || selectedTime == null) return;

    final combined = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    ref
        .read(waterRegisterControllerProvider.notifier)
        .selectEventTime(combined);
  }

  String _formatEventTime(DateTime eventTime, {required DateTime now}) {
    final diff = now.difference(eventTime);
    if (diff.inMinutes < 1) return 'Hace unos segundos';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';

    final daysDiff = diff.inDays;
    if (daysDiff == 1) return 'Ayer';
    if (daysDiff < 7) return 'Hace $daysDiff días';

    return '${eventTime.day}/${eventTime.month}/${eventTime.year} ${eventTime.hour.toString().padLeft(2, '0')}:${eventTime.minute.toString().padLeft(2, '0')}';
  }
}

class _ReviewField extends StatelessWidget {
  const _ReviewField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// Banner de error inline del registro (mismo estilo que StatusBanner del
/// flujo de fugas): el controller limpia `errorMessage` al reintentar.
class _RegisterErrorBanner extends StatelessWidget {
  const _RegisterErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
