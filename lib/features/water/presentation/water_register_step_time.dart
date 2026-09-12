import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/water_event_age.dart';
import 'water_copy.dart';
import 'water_register_controller.dart';

/// Cuarto paso: elegir la hora efectiva del evento.
class WaterRegisterStepTime extends ConsumerWidget {
  const WaterRegisterStepTime({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(waterRegisterControllerProvider);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WaterCopy.stepTime,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (state.eventTime != null) ...[
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
                      Text(
                        describeWaterEventTime(state.eventTime!, now: now),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _openTimePicker(context, ref),
                  child: const Text(WaterCopy.changeTime),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: TextButton.icon(
                onPressed: () => _openTimePicker(context, ref),
                icon: const Icon(Icons.access_time),
                label: const Text('Seleccionar hora'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Indica cuándo ocurrió el evento (no puede ser en el futuro).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
      0,
      0,
      0,
    );

    ref
        .read(waterRegisterControllerProvider.notifier)
        .selectEventTime(combined);
  }
}
