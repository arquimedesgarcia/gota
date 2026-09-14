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
import 'water_register_step_time.dart';
import 'water_register_step_comment.dart';

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
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _currentType = widget.initialType ?? WaterEventType.arrived;
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
                  currentStep: _currentStep,
                  onStepContinue: _currentStep < 4
                      ? () => setState(() => _currentStep++)
                      : null,
                  onStepCancel: _currentStep > 0
                      ? () => setState(() => _currentStep--)
                      : null,
                  steps: [
                    Step(
                      title: const Text(WaterCopy.stepType),
                      content: WaterRegisterStepType(
                        currentType: _currentType,
                        onTypeSelected: (type) {
                          setState(() => _currentType = type);
                        },
                      ),
                      isActive: _currentStep >= 0,
                    ),
                    Step(
                      title: const Text(WaterCopy.stepMunicipality),
                      content: const WaterRegisterStepMunicipality(),
                      isActive: _currentStep >= 1,
                    ),
                    Step(
                      title: const Text(WaterCopy.stepSector),
                      content: const WaterRegisterStepSector(),
                      isActive: _currentStep >= 2,
                    ),
                    Step(
                      title: const Text(WaterCopy.stepTime),
                      content: const WaterRegisterStepTime(),
                      isActive: _currentStep >= 3,
                    ),
                    Step(
                      title: const Text(WaterCopy.stepComment),
                      content: Column(
                        children: [
                          if (state.errorMessage != null) ...[
                            _RegisterErrorBanner(
                              message: state.errorMessage!,
                            ),
                            const SizedBox(height: 12),
                          ],
                          const WaterRegisterStepComment(),
                        ],
                      ),
                      isActive: _currentStep >= 4,
                    ),
                  ],
                ),
        ),
        floatingActionButton:
            state.submitStatus != WaterRegisterSubmitStatus.submitting &&
                _currentStep == 4
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
