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
import 'location_map_picker.dart';
import 'leak_detail_screen.dart';
import 'leak_report_controller.dart';
import 'leak_report_microcopy.dart';
import '../../privacy/data/permission_prefs.dart';

/// Pantalla raíz del flujo Reportar fuga: barra de progreso por etapa y
/// la página de la etapa actual (UX_SPEC §4:
/// Ubicación → Fotos → Datos → Revisar → Enviado).
///
/// G: PopScope intercepta el botón físico de Android para navegar al paso
/// anterior en lugar de cerrar la pantalla.
class LeakReportScreen extends ConsumerWidget {
  const LeakReportScreen({super.key});

  static const _titles = {
    ReportStep.location: 'Ubicación',
    ReportStep.data: 'Dirección',
    ReportStep.photos: 'Fotos',
    ReportStep.review: 'Revisar',
    ReportStep.result: 'Resultado',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(
      leakReportProvider.select((s) => s.currentStep),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // En el primer paso y en resultado: cerrar la pantalla normalmente.
        // pop() en lugar de maybePop(): con canPop:false, maybePop volvería
        // a disparar onPopInvokedWithResult generando recursión infinita.
        if (step == ReportStep.location || step == ReportStep.result) {
          Navigator.of(context).pop(false);
          return;
        }
        ref.read(leakReportProvider.notifier).goToPrevious();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 120,
          // X siempre cierra el reporte sin pasar por el PopScope de pasos.
          // Navigator.pop() bypasea canPop:false; el botón físico de Android
          // sigue navegando hacia atrás paso a paso.
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: Consumer(
            builder: (context, ref, _) {
              final s = ref.watch(
                leakReportProvider.select((st) => st.currentStep),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titles[s] ?? 'Reportar',
                    style: Theme.of(context).appBarTheme.titleTextStyle
                        ?.copyWith(color: Colors.white),
                  ),
                  SizedBox(height: AppSpacing.lg),
                  _StepIndicator(currentStep: s),
                ],
              );
            },
          ),
        ),
        body: SafeArea(
          child: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(leakReportProvider);
              final stepView = switch (state.currentStep) {
                ReportStep.location => const LocationStepView(),
                ReportStep.photos => const PhotosStepView(),
                ReportStep.data => const DataStepView(),
                ReportStep.review => const ReviewStepView(),
                ReportStep.result => const ResultStepView(),
              };
              if (!state.hasDraftRestored) return stepView;
              return Column(
                children: [
                  _DraftRestoredBanner(
                    onDiscard: () => ref
                        .read(leakReportProvider.notifier)
                        .discardDraft(),
                  ),
                  Expanded(child: stepView),
                ],
              );
            },
          ),
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

class _DraftRestoredBanner extends StatelessWidget {
  const _DraftRestoredBanner({required this.onDiscard});

  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.restore, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Reporte previo sin enviar',
                style: TextStyle(fontSize: 13, color: AppColors.primary),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onDiscard,
              child: const Text('Descartar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- Etapa 1: Ubicación ----------

class LocationStepView extends ConsumerStatefulWidget {
  const LocationStepView({super.key});

  @override
  ConsumerState<LocationStepView> createState() => _LocationStepViewState();
}

class _LocationStepViewState extends ConsumerState<LocationStepView> {
  Future<void> _onGpsTap() async {
    final prefsAsync = ref.read(permissionPrefsProvider);
    final prefs = prefsAsync.value;
    if (prefs != null && !prefs.locationRationaleShown) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Acceso a tu ubicación'),
          content: const Text(
            'Gota usa tu ubicación únicamente para registrar dónde está la '
            'fuga que estás reportando. No se rastrea tu posición en segundo '
            'plano.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      await prefs.setLocationRationaleShown();
      if (proceed != true) return;
    }
    ref.read(leakReportProvider.notifier).requestGps();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leakReportProvider);
    final controller = ref.read(leakReportProvider.notifier);
    final location = state.draft.location;
    final isManual = state.manualModeEnabled;

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
              const SizedBox(height: 16),

              // Banner "Modo manual activo" (cuando el usuario vuelve atrás).
              if (isManual) ...[
                Card(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.edit_location_alt_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Modo manual activo. Municipio y sector se llenan en el siguiente paso.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              FilledButton.icon(
                style: AppComponents.primaryButtonStyle(),
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Mi ubicación'),
                onPressed: _onGpsTap,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: AppComponents.secondaryButtonStyle(),
                icon: const Icon(Icons.pin_drop_outlined),
                label: const Text('Indicar dirección manualmente'),
                onPressed: controller.enterManualMode,
              ),
              const SizedBox(height: 16),

              // Indicador de carga del reverse-geocode.
              if (state.suggestionLoading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'Buscando una ubicación aproximada…',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
              ],

              // Tarjeta "Ubicación aproximada" — solo para modo GPS.
              if (!isManual && state.locationSuggestion != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ubicación aproximada',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state.locationSuggestion!.displayText ??
                              'No hay una descripción disponible.',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (state.locationSuggestion!.municipality != null ||
                            state.locationSuggestion!.state != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              state.locationSuggestion!.municipality,
                              state.locationSuggestion!.state,
                            ].whereType<String>().join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Mapa de ajuste (solo cuando hay coordenadas GPS).
              if (!isManual && location != null) ...[
                SizedBox(
                  height: 220,
                  child: ref.watch(locationMapBuilderProvider)(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    onMapTapped: (point) => controller.setAdjustedLocation(
                      latitude: point.latitude,
                      longitude: point.longitude,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Leyenda precisión GPS.
              if (!isManual && location?.accuracyMeters != null) ...[
                Text(
                  location!.accuracyMeters! <= 25
                      ? 'Precisión aproximada: buena (${location.accuracyMeters!.round()} m)'
                      : 'Precisión aproximada: ${location.accuracyMeters!.round()} m. Puedes continuar.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Sin ubicación todavía (modo GPS sin haber pulsado el botón).
              if (!isManual && location == null && !state.suggestionLoading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Usa tu GPS para detectar la ubicación, o toca '
                      '"Indicar dirección manualmente" para continuar sin coordenadas.',
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
                  onPressed: (location == null && !isManual)
                      ? null
                      : controller.goToNext,
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
                'Fotos de la fuga (opcional, máx. ${LeakReportController.photoMaxCount})',
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
              // G: botón Atrás → paso Ubicación
              Expanded(
                child: OutlinedButton(
                  style: AppComponents.secondaryButtonStyle(),
                  onPressed: () => controller.goToPrevious(),
                  child: const Text('Atrás'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: AppComponents.primaryButtonStyle(),
                  onPressed: () => controller.goToNext(),
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

/// ---------- Etapa 2 (visual): Dirección (municipio/sector/dirección/descripción) ----------

class DataStepView extends ConsumerStatefulWidget {
  const DataStepView({super.key});

  @override
  ConsumerState<DataStepView> createState() => _DataStepViewState();
}

class _DataStepViewState extends ConsumerState<DataStepView> {
  late final TextEditingController _addrController;
  late final TextEditingController _descController;
  bool _addrFocused = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(leakReportProvider);
    _addrController = TextEditingController(
      text: s.draft.address ?? s.locationSuggestion?.displayText ?? '',
    );
    _descController = TextEditingController(
      text: s.draft.description ?? '',
    );
  }

  @override
  void dispose() {
    _addrController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leakReportProvider);
    final controller = ref.read(leakReportProvider.notifier);
    final municipalitiesState = ref.watch(municipalitiesProvider);
    final isGps = !state.manualModeEnabled;

    // Pre-llena dirección desde el geocoder cuando llega después de abrir el paso.
    ref.listen(
      leakReportProvider.select((s) => s.locationSuggestion?.displayText),
      (prev, next) {
        if (next != null &&
            next.isNotEmpty &&
            state.draft.address == null &&
            !_addrFocused &&
            _addrController.text.isEmpty) {
          _addrController.text = next;
          controller.setAddress(next);
        }
      },
    );

    // Valor efectivo = selección explícita del usuario ?? sugerencia GPS.
    final effectiveMunicipalityId =
        state.draft.municipalityId ?? state.suggestedMunicipalityId;

    // Sector sugerido solo aplica si el municipio activo coincide.
    final effectiveSectorId = state.draft.sectorId ??
        (effectiveMunicipalityId == state.suggestedMunicipalityId
            ? state.suggestedSectorId
            : null);

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
              const SizedBox(height: 8),

              // Indicador de modo GPS / Manual con botón de intercambio.
              Row(
                children: [
                  Icon(
                    isGps ? Icons.gps_fixed : Icons.edit_location_alt_outlined,
                    size: 14,
                    color: isGps ? AppColors.success : AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isGps ? 'Modo GPS' : 'Modo manual',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: Icon(
                      isGps
                          ? Icons.edit_location_alt_outlined
                          : Icons.gps_fixed,
                      size: 14,
                    ),
                    label: Text(isGps ? 'Cambiar a manual' : 'Usar GPS'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.primary,
                    ),
                    onPressed:
                        isGps ? controller.enterManualMode : controller.switchToGpsMode,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              municipalitiesState.when(
                loading: () =>
                    const LoadingView(message: 'Cargando municipios…'),
                error: (error, _) => ErrorView(
                  message: 'No pudimos cargar los municipios.',
                  onRetry: () => ref.invalidate(municipalitiesProvider),
                ),
                data: (municipalities) => DropdownButtonFormField<String>(
                  key: ValueKey(effectiveMunicipalityId),
                  initialValue: effectiveMunicipalityId,
                  decoration: const InputDecoration(labelText: 'Municipio'),
                  items: municipalities
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.name),
                        ),
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
              if (effectiveMunicipalityId != null)
                _SectorsDropdown(
                  municipalityId: effectiveMunicipalityId,
                  selectedSectorId: effectiveSectorId,
                  onSelected: controller.selectSector,
                ),
              const SizedBox(height: 12),

              // Campo de dirección: pre-llenado por GPS (editable) o vacío en manual.
              Focus(
                onFocusChange: (f) => setState(() => _addrFocused = f),
                child: TextField(
                  controller: _addrController,
                  decoration: InputDecoration(
                    labelText: 'Dirección (opcional)',
                    hintText: isGps
                        ? null
                        : 'Ej: Calle Bolívar, frente a la plaza principal',
                    prefixIcon: const Icon(Icons.place_outlined, size: 18),
                  ),
                  maxLines: 2,
                  maxLength: 300,
                  onChanged: controller.setAddress,
                ),
              ),
              if (isGps && state.locationSuggestion?.displayText != null) ...[
                const SizedBox(height: 2),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    'Pre-llenada según GPS — puedes editarla.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _descController,
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
                  onPressed: controller.goToPrevious,
                  child: const Text('Atrás'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: AppComponents.primaryButtonStyle(),
                  onPressed: _buildContinueCallback(
                    state,
                    controller,
                    effectiveMunicipalityId,
                    effectiveSectorId,
                  ),
                  child: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  VoidCallback? _buildContinueCallback(
    LeakReportState state,
    LeakReportController controller,
    String? effectiveMunicipalityId,
    String? effectiveSectorId,
  ) {
    if (effectiveMunicipalityId == null || effectiveSectorId == null) {
      return null;
    }
    return () {
      if (state.draft.municipalityId == null) {
        controller.selectMunicipality(effectiveMunicipalityId);
      }
      if (state.draft.sectorId == null) {
        controller.selectSector(effectiveSectorId);
      }
      controller.goToNext();
    };
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

class _SectorName extends ConsumerWidget {
  const _SectorName({required this.sectorId});

  final String? sectorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sectorId == null) return const Text('Sin sector');
    final sectorNameState = ref.watch(sectorNameProvider(sectorId!));
    return sectorNameState.maybeWhen(
      data: (name) => Text(
        name ?? 'Sector',
        style: const TextStyle(color: AppColors.textMuted),
      ),
      orElse: () =>
          const Text('Sector', style: TextStyle(color: AppColors.textMuted)),
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
        key: ValueKey(selectedSectorId),
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
                            ? (state.manualModeEnabled
                                ? 'Modo manual (sin GPS)'
                                : 'Sin ubicación')
                            : draft.location!.source.label,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      if (draft.address != null &&
                          draft.address!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          draft.address!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      if (draft.photos.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Fotos',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: draft.photos.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(draft.photos[index].compressedPath),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                cacheWidth: 160,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Municipio y sector',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child:
                                _MunicipalityName(
                                  municipalityId: draft.municipalityId,
                                ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '·',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _SectorName(sectorId: draft.sectorId),
                          ),
                        ],
                      ),
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
              // El mensaje ya se muestra en el banner superior de la lista.
              if (state.submitState == ReportSubmitState.duplicate) ...[
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
                // G: Atrás regresa a Datos conservando todos los campos.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: AppComponents.secondaryButtonStyle(),
                    onPressed: state.submitState == ReportSubmitState.submitting
                        ? null
                        : () => ref
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
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: AppComponents.primaryButtonStyle(),
                // S10-B: devuelve true solo cuando el backend creó el
                // reporte (done + ReportCreated, mismo patrón que
                // WaterRegisterScreen.pop(true)). Duplicado/error devuelven
                // false para no invalidar recentLeaksProvider sin necesidad.
                onPressed: () {
                  final created =
                      state.submitState == ReportSubmitState.done &&
                      outcome is ReportCreated;
                  // pop() en lugar de maybePop() por la misma razón que en
                  // PopScope.onPopInvokedWithResult: evita recursión infinita.
                  Navigator.of(context).pop(created);
                },
                child: const Text('Volver al inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador visual de progreso (4 pasos: Ubicación → Dirección → Fotos → Revisar).
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});

  final ReportStep currentStep;

  // Orden visual del indicador (≠ orden del enum).
  static const _displayOrder = [
    ReportStep.location,
    ReportStep.data,
    ReportStep.photos,
    ReportStep.review,
  ];
  static const _stepLabels = ['Ubicación', 'Dirección', 'Fotos', 'Revisar'];

  @override
  Widget build(BuildContext context) {
    final displayIndex = _displayOrder.indexOf(currentStep);

    return Row(
      children: List.generate(_stepLabels.length, (index) {
        final isCompleted = displayIndex > index;
        final isCurrent = displayIndex == index;

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
      }),
    );
  }
}

/// Índice de sección usada en tests de navegación.
extension LeakSteps on LeakReportState {
  ReportStep get step => currentStep;
}
