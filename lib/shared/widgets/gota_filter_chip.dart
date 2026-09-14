import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Chip de filtro reutilizable (patrón del prototipo §mapa/lista):
/// píldora de 36dp de alto, superficie blanca con borde sutil cuando está
/// inactiva y relleno azul cuando está activa (texto + color + relleno,
/// nunca solo color). Targets táctiles >= 48dp vía [IconButton.constraints]
/// no aplica aquí: el chip entero es el target (>=44dp alto, ancho libre);
/// cumple accesibilidad por tener etiqueta textual.
class GotaFilterChip extends StatelessWidget {
  const GotaFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onSelected,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
