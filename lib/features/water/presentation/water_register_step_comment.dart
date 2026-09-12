import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'water_copy.dart';
import 'water_register_controller.dart';

/// Quinto paso: comentario opcional.
class WaterRegisterStepComment extends ConsumerWidget {
  const WaterRegisterStepComment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(waterRegisterControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WaterCopy.stepComment,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          maxLines: 4,
          maxLength: 500,
          controller: TextEditingController(text: state.comment),
          onChanged: (value) => ref
              .read(waterRegisterControllerProvider.notifier)
              .setComment(value),
          decoration: InputDecoration(
            hintText: WaterCopy.commentHelper,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            counterText: '${state.comment.length}/500',
          ),
        ),
      ],
    );
  }
}
