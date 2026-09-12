import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/water_event_age.dart';
import 'water_copy.dart';
import 'water_register_controller.dart';

/// Revisión final antes de enviar (no es un step en el Stepper,
/// se usa directamente al hacer clic en Confirmar).
class WaterRegisterStepReview extends ConsumerWidget {
  const WaterRegisterStepReview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(waterRegisterControllerProvider);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReviewRow(
          label: WaterCopy.stepType,
          value: state.municipalityName ?? '—',
        ),
        _ReviewRow(
          label: WaterCopy.stepMunicipality,
          value: state.municipalityName ?? '—',
        ),
        _ReviewRow(label: WaterCopy.stepSector, value: state.sectorName ?? '—'),
        _ReviewRow(
          label: WaterCopy.stepTime,
          value: state.eventTime != null
              ? describeWaterEventTime(state.eventTime!, now: now)
              : '—',
        ),
        if (state.comment.isNotEmpty)
          _ReviewRow(label: WaterCopy.stepComment, value: state.comment),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
