import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/create_leak_report_outcome.dart';
import '../domain/leak_errors.dart';
import '../domain/leak_report_draft.dart';
import '../data/geolocator_location_service.dart';
import '../data/leak_report_repository.dart';
import '../data/location_service.dart';
import '../data/photo_service.dart';
import '../domain/location_source.dart';
import '../../location/data/municipality_repository.dart';
import '../../location/data/sector_repository.dart';
import '../../../shared/models/municipality.dart';
import '../../../shared/models/sector.dart';

/// Etapas del flujo Reportar fuga (UX_SPEC §4):
/// Ubicación → Fotos → Datos → Revisar → Enviado.
enum ReportStep { location, photos, data, review, result }

enum ReportSubmitState { idle, submitting, done, duplicate, error }

@immutable
class LeakReportState {
  const LeakReportState({
    this.currentStep = ReportStep.location,
    this.draft = const LeakReportDraft(),
    this.submitState = ReportSubmitState.idle,
    this.message,
    this.outcome,
    this.municipalities = const [],
    this.sectors = const [],
    this.municipalityError,
    this.sectorsError,
  });

  final ReportStep currentStep;
  final LeakReportDraft draft;
  final ReportSubmitState submitState;

  /// Mensaje visible (error inmediato duplicado detectado, confirmación).
  final String? message;
  final CreateLeakReportOutcome? outcome;

  final List<Municipality> municipalities;
  final List<Sector> sectors;
  final String? municipalityError;
  final String? sectorsError;

  bool get canSubmit =>
      draft.location != null &&
      draft.photos.isNotEmpty &&
      draft.municipalityId != null &&
      draft.sectorId != null;

  LeakReportState copyWith({
    ReportStep? currentStep,
    LeakReportDraft? draft,
    ReportSubmitState? submitState,
    String? message,
    bool clearMessage = false,
    CreateLeakReportOutcome? outcome,
    List<Municipality>? municipalities,
    List<Sector>? sectors,
    String? municipalityError,
    String? sectorsError,
    bool clearMunicipalityError = false,
    bool clearSectorsError = false,
  }) =>
      LeakReportState(
        currentStep: currentStep ?? this.currentStep,
        draft: draft ?? this.draft,
        submitState: submitState ?? this.submitState,
        message: clearMessage ? null : (message ?? this.message),
        outcome: outcome ?? this.outcome,
        municipalities: municipalities ?? this.municipalities,
        sectors: sectors ?? this.sectors,
        municipalityError:
            clearMunicipalityError ? null : (municipalityError ?? this.municipalityError),
        sectorsError: clearSectorsError ? null : (sectorsError ?? this.sectorsError),
      );
}

/// Controller del flujo Reportar fuga.
class LeakReportController extends Notifier<LeakReportState> {
  /// True cuando el usuario ya confirmó que su fuga es distinta de un
  /// candidato detectado ("es otra fuga"): se envía a la RPC como
  /// `p_ignore_duplicate`.
  bool _ignoreDuplicate = false;

  LocationService get _locationService => ref.watch(locationServiceProvider);

  @override
  LeakReportState build() {
    _loadMunicipalities();
    return const LeakReportState();
  }

  Future<void> _loadMunicipalities() async {
    try {
      final municipalities =
          await ref.watch(municipalityRepositoryProvider).getActive();
      state = state.copyWith(
        municipalities: municipalities,
        clearMunicipalityError: true,
      );
    } on LeakFlowException catch (e) {
      state = state.copyWith(municipalityError: e.userMessage);
    } on Exception {
      state = state.copyWith(
        municipalityError: 'No pudimos cargar los municipios.',
      );
    }
  }

  Future<void> loadSectors(String municipalityId) async {
    state = state.copyWith(draft: state.draft.copyWith(sectorId: null));
    try {
      final sectors = await ref
          .watch(sectorRepositoryProvider)
          .getByMunicipality(municipalityId);
      state = state.copyWith(sectors: sectors, clearSectorsError: true);
    } on LeakFlowException catch (e) {
      state = state.copyWith(sectorsError: e.userMessage);
    } on Exception {
      state = state.copyWith(sectorsError: 'No pudimos cargar los sectores.');
    }
  }

  // ---------- Ubicación ----------

  Future<void> requestGps() async {
    try {
      final position = await _locationService.getCurrentPosition();
      state = state.copyWith(
        draft: state.draft.copyWith(
          location: SelectedLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            source: LocationSource.gps,
          ),
        ),
        clearMessage: true,
      );
    } on LeakFlowException catch (e) {
      state = state.copyWith(message: e.userMessage);
    }
  }

  void setManualLocation({
    required double latitude,
    required double longitude,
  }) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        location: SelectedLocation(
          latitude: latitude,
          longitude: longitude,
          source: LocationSource.manual,
        ),
      ),
      clearMessage: true,
    );
  }

  // ---------- Fotos ----------

  Future<void> addPhoto({required bool fromCamera}) async {
    if (state.draft.photos.length >= 3) {
      state = state.copyWith(
        message: 'Ya tienes el máximo de 3 fotos.',
      );
      return;
    }
    final service = ImagePickerPhotoService();
    try {
      final photo = await service.pickAndPrepare(fromCamera: fromCamera);
      state = state.copyWith(
        draft: state.draft.copyWith(
          photos: [...state.draft.photos, photo],
        ),
        clearMessage: true,
      );
    } on PhotoValidationException catch (e) {
      state = state.copyWith(message: e.userMessage);
    } on LeakFlowException catch (e) {
      state = state.copyWith(message: e.userMessage);
    }
  }

  void removePhoto(PreparedPhoto photo) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        photos:
            state.draft.photos.where((p) => p.id != photo.id).toList(),
      ),
    );
  }

  // ---------- Datos ----------

  void selectMunicipality(String id) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        municipalityId: id,
        // El sector depende del municipio: se reinicia al cambiarlo.
        sectorId: null,
        photos: state.draft.photos,
      ),
      clearMessage: true,
    );
    loadSectors(id);
  }

  void selectSector(String id) =>
      state = state.copyWith(draft: state.draft.copyWith(sectorId: id));

  void setDescription(String value) =>
      state = state.copyWith(draft: state.draft.copyWith(description: value));

  // ---------- Navegación del flujo ----------

  void goTo(ReportStep step) => state = state.copyWith(currentStep: step);

  void goToNext() {
    final order = ReportStep.values;
    final index = order.indexOf(state.currentStep);
    if (index < order.length - 1) {
      state = state.copyWith(currentStep: order[index + 1]);
    }
  }

  void goToPrevious() {
    final order = ReportStep.values;
    final index = order.indexOf(state.currentStep);
    if (index > 0) {
      state = state.copyWith(currentStep: order[index - 1]);
    }
  }

  /// El usuario declara "es otra fuga": se crea el reporte pese al
  /// candidato (REQ-025). Reenvía con la confirmación explícita, porque
  /// el backend solo acepta el override con esa señal.
  Future<void> continueAsNewLeak() async {
    _ignoreDuplicate = true;
    state = state.copyWith(
      currentStep: ReportStep.review,
      clearMessage: true,
    );
    await submit();
  }

  /// El usuario acepta usar el reporte existente: cierra el flujo sin
  /// duplicar.
  void useExistingReport() =>
      state = state.copyWith(currentStep: ReportStep.result, message: 'Usaste '
          'el reporte existente. Puedes validarlo desde el mapa cuando esté '
          'disponible.');

  // ---------- Envío ----------

  Future<void> submit() async {
    if (!state.canSubmit || state.submitState == ReportSubmitState.submitting) {
      return;
    }
    state = state.copyWith(
      submitState: ReportSubmitState.submitting,
      clearMessage: true,
    );
    try {
      final outcome = await ref
          .watch(leakReportRepositoryProvider)
          .createReport(state.draft, ignoreDuplicate: _ignoreDuplicate);
      switch (outcome) {
        case ReportCreated(:final reportId):
          state = state.copyWith(
            submitState: ReportSubmitState.done,
            outcome: outcome,
            currentStep: ReportStep.result,
            message: '¡Reporte enviado! La fuga quedó registrada como '
                'activa (ID $reportId).',
          );
        case PossibleDuplicateFound(:final candidates):
          state = state.copyWith(
            submitState: ReportSubmitState.duplicate,
            outcome: outcome,
            message: 'Ya existe un reporte de fuga cerca '
                '(${candidates.first.distanceMeters} m).',
          );
        case LeakReportUnauthorized():
          state = state.copyWith(
            submitState: ReportSubmitState.idle,
            message:
                'Tu sesión no está activa. Cierra y abre la app de nuevo.',
          );
      }
    } on LeakFlowException catch (e) {
      state = state.copyWith(
        submitState: ReportSubmitState.idle,
        message: e.userMessage,
      );
    } on Exception {
      state = state.copyWith(
        submitState: ReportSubmitState.idle,
        message: 'No pudimos registrar tu reporte. Intenta de nuevo.',
      );
    }
  }
}

final leakReportProvider =
    NotifierProvider<LeakReportController, LeakReportState>(
  LeakReportController.new,
);
