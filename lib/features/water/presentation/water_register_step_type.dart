import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/water_event_type.dart';
import 'water_copy.dart';

/// Primer paso: seleccionar el tipo de evento (Llegó / Se fue).
class WaterRegisterStepType extends StatelessWidget {
  const WaterRegisterStepType({
    super.key,
    required this.currentType,
    required this.onTypeSelected,
  });

  final WaterEventType currentType;
  final ValueChanged<WaterEventType> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(WaterCopy.stepType, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        _TypeButton(
          type: WaterEventType.arrived,
          icon: Icons.water_drop,
          isSelected: currentType == WaterEventType.arrived,
          onPressed: () => onTypeSelected(WaterEventType.arrived),
        ),
        const SizedBox(height: 12),
        _TypeButton(
          type: WaterEventType.left,
          icon: Icons.water_drop_outlined,
          isSelected: currentType == WaterEventType.left,
          onPressed: () => onTypeSelected(WaterEventType.left),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.type,
    required this.icon,
    required this.isSelected,
    required this.onPressed,
  });

  final WaterEventType type;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = type == WaterEventType.arrived ? AppColors.primary : AppColors.danger;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                type.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                    ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color)
            else
              const Icon(Icons.radio_button_unchecked, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
