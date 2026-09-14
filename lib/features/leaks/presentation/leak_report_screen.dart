import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../location/presentation/location_providers.dart';
import '../domain/create_leak_report_outcome.dart';
import '../domain/location_source.dart';
import 'leak_detail_screen.dart';
import 'leak_report_controller.dart';
import 'leak_report_microcopy.dart';

/// Pantalla raíz del flujo Reportar fuga: barra de progreso por etapa y
/// la página de la etapa actual (UX_SPEC §4:
/// Ubicación → Fotos → Datos → Revisar → Enviado).
class LeakReportScreen extends StatelessWidget {
  const LeakReportScreen({super.key});

  static const _titles = {
    ReportStep.location: 'Ubicación',
    ReportStep.photos: 'Fotos',
    ReportStep.data: 'Datos',
    ReportStep.review: 'Revisar',
    ReportStep.result: 'Resultado',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 120,
        title: Consumer(
          builder: (context, ref, _) {
            final step = ref.watch(
              leakReportProvider.select((s) => s.currentStep),
            );
            final stepIndex = step.index; // 0-4 for location, photos, data, review, result

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titles[step] ?? 'Reportar',
                  style: Theme.of(context).appBarTheme.titleTextStyle
                      ?.copyWith(color: Colors.white),
                ),
                SizedBox(height: AppSpacing.lg),
                _StepIndicator(currentStep: stepIndex),
              ],
            );
          },
        ),
      ),
      body: SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(leakReportProvider);
            return switch (state.currentStep) {
              ReportStep.location => const LocationStepView(),
              ReportStep.photos => const PhotosStepView(),
              ReportStep.data => const DataStepView(),
              ReportStep.review => const ReviewStepView(),
              ReportStep.result => const ResultStepView(),
            };
          },
        ),
      ),
    );
  }
}

/// Mensaje de estado reutilizable (errores, duplicado, confirmación).
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isError
          ? AppColors.danger.withValues(alpha: 0.08)
          : AppColors.success.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? AppColors.danger : AppColors.success,
            ),
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

/// ---------- Etapa 1: Ubicación ----------

class LocationStepView extends ConsumerWidget {
  const LocationStepView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leakReportProvider);
    final location = state.draft.location;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.message != null) ...[
                StatusBanner(message: state.message!),
                const SizedBox(height: 12),
              ],
              Text(
                '¿Dónde está la fuga?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'Usa tu GPS o indica la zona manualmente. Esto ayuda a tus '
                'vecinos a encontrarla en el mapa.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Usar mi ubicación (GPS)'),
                onPressed: () =>
                    ref.read(leakReportProvider.notifier).requestGps(),
              ),
              const SizedBox(height: 12),
              // Selección manual provisional: coordenadas de contexto.
              // Sprint 05 la reemplaza por el punto en el mapa (MapLibre)
              // usando el mismo método manual del controller.
              OutlinedButton.icon(
                style: AppComponents.secondaryButtonStyle(),
                icon: const Icon(Icons.pin_drop_outlined),
                label: const Text('Indicar ubicación manual'),
                onPressed: () => _showManualLocationDialog(context, ref),
              ),
              const SizedBox(height: 24),
              if (location != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              location.source == LocationSource.gps
                                  ? Icons.gps_fixed
                                  : Icons.pin_drop,
                              color: location.isGps
                                  ? AppColors.success
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                location.source.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lat: ${location.latitude.toStringAsFixed(5)}, '
                          'Lng: ${location.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sin ubicación todavía. Elige GPS o manual para '
                      'continuar.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Spacer(),
              Expanded(
                child: FilledButton(
                  style: AppComponents.primaryButtonStyle(),
                  onPressed: location == null
                      ? null
                      : () => ref.read(leakReportProvider.notifier).goToNext(),
                  child: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showManualLocationDialog(BuildContext context, WidgetRef ref) {
    final latController = TextEditingController();
    final lngController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ubicación manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latController,
              decoration: const InputDecoration(labelText: 'Latitud'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextField(
              controller: lngController,
              decoration: const InputDecoration(labelText: 'Longitud'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              LeakReportCopy.manualHint,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final lat = double.tryParse(
                latController.text.replaceAll(',', '.'),
              );
              final lng = double.tryParse(
                lngController.text.replaceAll(',', '.'),
              );
              if (lat == null ||
                  lng == null ||
                  lat < -90 ||
                  lat > 90 ||
                  lng < -180 ||
                  lng > 180) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Coordenadas inválidas. Revisa los números e intenta '
                      'de nuevo.',
                    ),
                  ),
                );
                return;
              }
              ref
                  .read(leakReportProvider.notifier)
                  .setManualLocation(latitude: lat, longitude: lng);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// ---------- Etapa 2: Fotos ----------

class PhotosStepView extends ConsumerWidget {
  const PhotosStepView({super.key});

  void _showPhotoSourceSheet(
    BuildContext context,
    LeakReportController controller,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text(LeakReportCopy.fromCamera),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.addPhoto(fromCamera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(LeakReportCopy.fromGallery),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.addPhoto(fromCamera: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leakReportProvider);
    final photos = state.draft.photos;
    final controller = ref.read(leakReportProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.message != null) ...[
                StatusBanner(message: state.message!),
                const SizedBox(height: 12),
              ],
              Text(
                'Agrega de 1 a ${LeakReportController.photoMaxCount} fotos de la fuga',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Fotos agregadas: ${photos.length} de ${LeakReportController.photoMaxCount}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount:
                photos.length +
                (photos.length < LeakReportController.photoMaxCount ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < photos.length) {
                final photo = photos[index];
                return Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          // Vista previa comprimida local, aún no se sube.
                          // AUD-S2-16: cacheWidth evita decodificar a
                          // resolución completa en la grilla.
                          File(photo.compressedPath),
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => controller.removePhoto(photo),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                // AUD-S2-09: cámara o galería (bottom sheet, UX_SPEC §4).
                onTap: () => _showPhotoSourceSheet(context, controller),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_a_photo_outlined,
                    color: AppColors.textMuted,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: AppComponents.secondaryButtonStyle(),
                  onPressed: () {
                    if (photos.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Necesitas al menos 1 foto para continuar.',
                          ),
                        ),
                      );
                      return;
                    }
                    controller.goToNext();
                  },
                  child: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------- Etapa 3: Datos (municipio/sector/descripción) ----------

class DataStepView extends ConsumerWidget {
  const DataStepView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leakReportProvider);
    final controller = ref.read(leakReportProvider.notifier);
    final municipalitiesState = ref.watch(municipalitiesProvider);
    final selectedMunicipalityId = state.draft.municipalityId;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.message != null) ...[
                StatusBanner(message: state.message!),
                const SizedBox(height: 12),
              ],
              Text('¿Dónde?', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              municipalitiesState.when(
                loading: () =>
                    const LoadingView(message: 'Cargando municipios…'),
                error: (error, _) => ErrorView(
                  message: 'No pudimos cargar los municipios.',
                  onRetry: () => ref.invalidate(municipalitiesProvider),
                ),
                data: (municipalities) => DropdownButtonFormField<String>(
                  initialValue: selectedMunicipalityId,
                  decoration: const InputDecoration(labelText: 'Municipio'),
                  items: municipalities
                      .map(
                        (m) =>
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      ref.invalidate(sectorsProvider(value));
                      controller.selectMunicipality(value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (state.draft.municipalityId != null)
                _SectorsDropdown(
                  municipalityId: state.draft.municipalityId!,
                  selectedSectorId: state.draft.sectorId,
                  onSelected: controller.selectSector,
                ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  hintText: 'Ej: brocal roto frente a la panadería.',
                ),
                maxLines: 3,
                maxLength: 500,
                onChanged: controller.setDescription,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: AppComponents.secondaryButtonStyle(),
                  // El municipio es obligatorio; el sector también
                  // (REQ-020). La descripción es opcional.
                  onPressed:
                      (state.draft.municipalityId != null &&
                          state.draft.sectorId != null)
                      ? () => controller.goToNext()
                      : null,
                  child: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Nombre del municipio para el resumen de revisión: fuente única
/// (municipalitiesProvider, AUD-S2-12).
class _MunicipalityName extends ConsumerWidget {
  const _MunicipalityName({required this.municipalityId});

  final String? municipalityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (municipalityId == null) return const Text('Sin municipio');
    final municipalities = ref.watch(municipalitiesProvider);
    return municipalities.maybeWhen(
      data: (list) => Text(
        list.where((m) => m.id == municipalityId).firstOrNull?.name ??
            'Municipio',
        style: const TextStyle(color: AppColors.textMuted),
      ),
      orElse: () =>
          const Text('Municipio', style: TextStyle(color: AppColors.textMuted)),
    );
  }
}

class _SectorsDropdown extends ConsumerWidget {
  const _SectorsDropdown({
    required this.municipalityId,
    required this.selectedSectorId,
    required this.onSelected,
  });

  final String municipalityId;
  final String? selectedSectorId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectorsState = ref.watch(sectorsProvider(municipalityId));
    return sectorsState.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message: 'No pudimos cargar los sectores.',
        onRetry: () => ref.invalidate(sectorsProvider(municipalityId)),
      ),
      data: (sectors) => DropdownButtonFormField<String>(
        initialValue: selectedSectorId,
        decoration: const InputDecoration(labelText: 'Sector'),
        items: sectors
            .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
            .toList(),
        onChanged: (value) {
          if (value != null) onSelected(value);
        },
      ),
    );
  }
}

/// ---------- Etapa 4: Revisar ----------

class ReviewStepView extends ConsumerWidget {
  const ReviewStepView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leakReportProvider);
    final draft = state.draft;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.message != null) ...[
                StatusBanner(message: state.message!),
                const SizedBox(height: 12),
              ],
              Text(
                'Revisa tu reporte',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ubicación',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        draft.location == null
                            ? 'Sin ubicación'
                            : draft.location!.source.label,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Fotos',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${draft.photos.length} foto(s) agregada(s).',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Municipio y sector',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      // AUD-S2-12: el nombre sale del provider único.
                      _MunicipalityName(municipalityId: draft.municipalityId),
                      const SizedBox(height: 12),
                      Text(
                        'Descripción',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (draft.description == null ||
                                draft.description!.trim().isEmpty)
                            ? 'Sin descripción'
                            : draft.description!,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Al enviar, tus fotos se subirán y el sistema revisará si '
                'existe un reporte similar cerca antes de publicar el tuyo.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Duplicado detectado: el usuario decide (UX_SPEC §5:
              // Ver y validar / Es otra fuga; nada en silencio).
              if (state.submitState == ReportSubmitState.duplicate) ...[
                StatusBanner(
                  message: state.message ?? LeakReportCopy.duplicateTitle,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: AppComponents.secondaryButtonStyle(),
                    // AUD-S2-05: ver/validar el existente desde el
                    // candidato que la RPC ya devolvió. La validación
                    // vive en la pantalla de detalle (Sprint 03).
                    onPressed: () {
                      final outcome = state.outcome;
                      if (outcome is! PossibleDuplicateFound) return;
                      final candidates = outcome.candidates;
                      if (candidates.isEmpty) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              LeakDetailScreen(reportId: candidates.first.id),
                        ),
                      );
                    },
                    child: const Text(LeakReportCopy.duplicateViewAndValidate),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: AppComponents.secondaryButtonStyle(),
                    onPressed: () => ref
                        .read(leakReportProvider.notifier)
                        .useExistingReport(),
                    child: const Text(LeakReportCopy.duplicateUseExisting),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: AppComponents.primaryButtonStyle(),
                    onPressed: () => ref
                        .read(leakReportProvider.notifier)
                        .continueAsNewLeak(),
                    child: const Text(LeakReportCopy.duplicateOtherLeak),
                  ),
                ),
              ] else ...[
                state.submitState == ReportSubmitState.submitting
                    ? const SizedBox(
                        height: 48,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: AppComponents.primaryButtonStyle(),
                          onPressed: () =>
                              ref.read(leakReportProvider.notifier).submit(),
                          child: const Text('Enviar reporte'),
                        ),
                      ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: AppComponents.secondaryButtonStyle(),
                    onPressed: () => ref
                        .read(leakReportProvider.notifier)
                        .goTo(ReportStep.data),
                    child: const Text('Editar datos'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------- Etapa 4b: Duplicado detectado ----------
///
/// Sin diálogo aparte: el estado duplicate se resuelve inline en
/// ReviewStepView (ver arriba). El antiguo DuplicateDialog muerto se
/// eliminó (AUD-S2-13).

/// ---------- Etapa 5: Resultado ----------
///
/// AUD-S2-06: el título/icono se deriva del OUTCOME real
/// (creado / duplicado-aceptado / error); nunca se anuncia "Reporte
/// enviado" si el backend no creó el reporte (FUNCTIONAL_SPEC §12).
class ResultStepView extends ConsumerWidget {
  const ResultStepView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(leakReportProvider);
    final outcome = state.outcome;
    // useExistingReport mantiene submitState=duplicate con paso=resultado;
    // ambos caminos caen en ese case. La ruta done exige outcome CREATED.

    final (icon, iconColor, title) = switch (state.submitState) {
      ReportSubmitState.done when outcome is ReportCreated => (
        Icons.check_circle_outline,
        AppColors.success,
        'Reporte enviado',
      ),
      ReportSubmitState.done => (
        Icons.error_outline,
        AppColors.danger,
        'No se pudo enviar',
      ),
      ReportSubmitState.duplicate => (
        Icons.not_interested,
        AppColors.textMuted,
        'No se creó un reporte nuevo',
      ),
      _ => (Icons.error_outline, AppColors.danger, 'No se pudo enviar'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 64),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              state.message ?? 'Ocurrió un problema al enviar tu reporte.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador visual de progreso de pasos (4 pasos: ubicación → fotos → datos → revisar).
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});

  final int currentStep; // 0-indexed: 0=location, 1=photos, 2=data, 3=review, 4=result
  static const _stepLabels = ['Ubicación', 'Fotos', 'Datos', 'Revisar'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_stepLabels.length, (index) {
            final isCompleted = index < currentStep;
            final isCurrent = index == currentStep;

            return Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: isCompleted || isCurrent
                          ? AppColors.primary
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    _stepLabels[index],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isCompleted || isCurrent
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Índice de sección usada en tests de navegación.
extension LeakSteps on LeakReportState {
  ReportStep get step => currentStep;
}
