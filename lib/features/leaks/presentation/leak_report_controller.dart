import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../location/presentation/location_providers.dart';
import '../domain/create_leak_report_outcome.dart';
import '../domain/leak_errors.dart';
import '../domain/leak_report_draft.dart';
import '../data/geolocator_location_service.dart';
import '../data/leak_report_repository.dart';
import '../data/location_service.dart';
import '../data/photo_service.dart';
import '../data/photo_limits.dart';
import '../data/reverse_geocoding_service.dart';
import '../domain/location_source.dart';
import '../domain/location_suggestion.dart';

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
    this.locationSuggestion,
    this.suggestionLoading = false,
    this.suggestedMunicipalityId,
    this.suggestedSectorId,
  });

  final ReportStep currentStep;
  final LeakReportDraft draft;
  final ReportSubmitState submitState;

  /// Mensaje visible (error inmediato duplicado detectado, confirmación).
  final String? message;
  final CreateLeakReportOutcome? outcome;
  final LocationSuggestion? locationSuggestion;
  final bool suggestionLoading;

  /// ID del municipio sugerido por reverse-geocode (nunca sobreescribe
  /// una selección manual almacenada en [draft.municipalityId]).
  final String? suggestedMunicipalityId;

  /// ID del sector sugerido; válido solo cuando el municipio activo
  /// coincide con [suggestedMunicipalityId].
  final String? suggestedSectorId;

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
    LocationSuggestion? locationSuggestion,
    bool clearLocationSuggestion = false,
    bool? suggestionLoading,
    String? suggestedMunicipalityId,
    String? suggestedSectorId,
  }) => LeakReportState(
    currentStep: currentStep ?? this.currentStep,
    draft: draft ?? this.draft,
    submitState: submitState ?? this.submitState,
    message: clearMessage ? null : (message ?? this.message),
    outcome: outcome ?? this.outcome,
    locationSuggestion: clearLocationSuggestion
        ? null
        : (locationSuggestion ?? this.locationSuggestion),
    suggestionLoading: suggestionLoading ?? this.suggestionLoading,
    // Limpiar sugerencias derivadas al limpiar la sugerencia de ubicación.
    suggestedMunicipalityId: clearLocationSuggestion
        ? null
        : (suggestedMunicipalityId ?? this.suggestedMunicipalityId),
    suggestedSectorId: clearLocationSuggestion
        ? null
        : (suggestedSectorId ?? this.suggestedSectorId),
  );
}

/// Controller del flujo Reportar fuga.
class LeakReportController extends Notifier<LeakReportState> {
  /// CAP de configuración: máximo de fotos (fuente de verdad client-side
  /// hasta leerlo de `system_config`; la RPC vuelve a validar).
  static const photoMaxCount = kReportPhotoMaxCount;

  LocationService get _locationService => ref.watch(locationServiceProvider);
  ReverseGeocodingService get _reverseGeocoder =>
      ref.watch(reverseGeocodingServiceProvider);
  int _locationRequestId = 0;

  @override
  LeakReportState build() {
    // AUD-S2-12: municipios/sectores viven SOLO en municipalitiesProvider /
    // sectorsProvider (location_providers); el controller ya no duplica
    // la carga ni el estado.
    return const LeakReportState();
  }

  // ---------- Ubicación ----------

  Future<void> requestGps() async {
    final requestId = ++_locationRequestId;
    try {
      final position = await _locationService.getCurrentPosition();
      state = state.copyWith(
        draft: state.draft.copyWith(
          location: SelectedLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracyMeters,
            source: LocationSource.gps,
          ),
        ),
        clearMessage: true,
        clearLocationSuggestion: true,
        suggestionLoading: true,
      );
      await _loadSuggestion(
        requestId: requestId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on LeakFlowException catch (e) {
      state = state.copyWith(
        message: e.userMessage,
        clearLocationSuggestion: true,
        suggestionLoading: false,
      );
    }
  }

  Future<void> _loadSuggestion({
    required int requestId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final suggestion = await _reverseGeocoder.reverse(
        latitude: latitude,
        longitude: longitude,
      );
      if (requestId != _locationRequestId) return;
      state = state.copyWith(
        locationSuggestion: suggestion,
        suggestionLoading: false,
      );
      if (suggestion != null) {
        await _applyMunicipalitySuggestion(
          requestId: requestId,
          suggestion: suggestion,
        );
      }
    } on ReverseGeocodingException catch (e) {
      if (requestId != _locationRequestId) return;
      state = state.copyWith(
        message: e.userMessage,
        suggestionLoading: false,
      );
    }
  }

  /// Calcula sugerencias de municipio y sector a partir de los datos del
  /// reverse-geocoder y las guarda como [suggestedMunicipalityId] /
  /// [suggestedSectorId] en el estado.
  ///
  /// Nunca modifica [draft.municipalityId] ni [draft.sectorId]: la
  /// preselección es solo informativa; el usuario confirma vía dropdown.
  Future<void> _applyMunicipalitySuggestion({
    required int requestId,
    required LocationSuggestion suggestion,
  }) async {
    final rawMunicipality = suggestion.municipality ?? suggestion.city;
    if (rawMunicipality == null) return;

    try {
      final municipalities = await ref.read(municipalitiesProvider.future);
      if (requestId != _locationRequestId) return;

      final matched = _matchUnique(
        _normalize(rawMunicipality),
        municipalities.map((m) => (id: m.id, name: m.name)),
      );
      if (matched == null) return;

      state = state.copyWith(suggestedMunicipalityId: matched);

      final localityText =
          suggestion.locality ?? suggestion.neighborhood ?? suggestion.city;
      if (localityText == null) return;

      final sectors = await ref.read(sectorsProvider(matched).future);
      if (requestId != _locationRequestId) return;

      final matchedSector = _matchUnique(
        _normalize(localityText),
        sectors.map((s) => (id: s.id, name: s.name)),
      );
      if (matchedSector == null) return;
      state = state.copyWith(suggestedSectorId: matchedSector);
    } catch (_) {
      // Best-effort; errores son silenciosos.
    }
  }

  static String _normalize(String text) => text
      .toLowerCase()
      .replaceFirst(RegExp(r'^municipio\s+'), '')
      .trim();

  /// Devuelve el id del único elemento cuyo nombre [contains] el [target]
  /// (o viceversa). Si hay 0 o ≥2 coincidencias devuelve null (ambigüedad).
  static String? _matchUnique(
    String target,
    Iterable<({String id, String name})> items,
  ) {
    String? unique;
    for (final item in items) {
      final norm = item.name.toLowerCase();
      if (norm.contains(target) || target.contains(norm)) {
        if (unique != null) return null; // ambigüedad
        unique = item.id;
      }
    }
    return unique;
  }

  void setManualLocation({
    required double latitude,
    required double longitude,
  }) {
    ++_locationRequestId;
    state = state.copyWith(
      draft: state.draft.copyWith(
        location: SelectedLocation(
          latitude: latitude,
          longitude: longitude,
          source: LocationSource.manual,
        ),
      ),
      clearMessage: true,
      clearLocationSuggestion: true,
      suggestionLoading: false,
    );
  }

  Future<void> setAdjustedLocation({
    required double latitude,
    required double longitude,
  }) async {
    final requestId = ++_locationRequestId;
    state = state.copyWith(
      draft: state.draft.copyWith(
        location: SelectedLocation(
          latitude: latitude,
          longitude: longitude,
          source: LocationSource.manual,
        ),
      ),
      clearMessage: true,
      clearLocationSuggestion: true,
      suggestionLoading: true,
    );
    await _loadSuggestion(
      requestId: requestId,
      latitude: latitude,
      longitude: longitude,
    );
  }

  // ---------- Fotos ----------

  Future<void> addPhoto({required bool fromCamera}) async {
    if (state.draft.photos.length >= photoMaxCount) {
      state = state.copyWith(
        message: 'Ya tienes el máximo de $photoMaxCount fotos.',
      );
      return;
    }
    final service = ref.read(photoServiceProvider);
    try {
      final photo = await service.pickAndPrepare(fromCamera: fromCamera);
      state = state.copyWith(
        draft: state.draft.copyWith(photos: [...state.draft.photos, photo]),
        clearMessage: true,
      );
    } on PhotoPickCanceledException {
      // AUD-S2-14: cancelar el picker no muestra banner de error.
      return;
    } on PhotoValidationException catch (e) {
      state = state.copyWith(message: e.userMessage);
    } on LeakFlowException catch (e) {
      state = state.copyWith(message: e.userMessage);
    } catch (error, stackTrace) {
          if (kDebugMode) debugPrint('addPhoto falló: $error\n$stackTrace');
      state = state.copyWith(
        message: const PhotoValidationException(
          'No pudimos procesar esa foto. Elige otra.',
        ).userMessage,
      );
    }
  }

  void removePhoto(PreparedPhoto photo) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        photos: state.draft.photos.where((p) => p.id != photo.id).toList(),
      ),
    );
  }

  /// SOLO para pruebas: inserta una foto ya preparada sin image_picker.
  @visibleForTesting
  void addPreparedPhotoForTest(PreparedPhoto photo) {
    state = state.copyWith(
      draft: state.draft.copyWith(photos: [...state.draft.photos, photo]),
      clearMessage: true,
    );
  }

  /// SOLO para pruebas: completa el borrador con una foto sintética.
  @visibleForTesting
  void completeDraftForTest({
    required PreparedPhoto photo,
    required String municipalityId,
    required String sectorId,
  }) {
    selectMunicipality(municipalityId);
    selectSector(sectorId);
    addPreparedPhotoForTest(photo);
    state = state.copyWith(
      draft: state.draft.copyWith(
        location: SelectedLocation(
          latitude: 10.99,
          longitude: -63.87,
          source: LocationSource.manual,
        ),
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
  }

  void selectSector(String id) =>
      state = state.copyWith(draft: state.draft.copyWith(sectorId: id));

  void setDescription(String value) =>
      state = state.copyWith(draft: state.draft.copyWith(description: value));

  // ---------- Navegación del flujo ----------

  void goTo(ReportStep step) => state = state.copyWith(
    currentStep: step,
    clearMessage: state.submitState == ReportSubmitState.idle,
  );

  void goToNext() {
    final order = ReportStep.values;
    final index = order.indexOf(state.currentStep);
    if (index < order.length - 1) {
      state = state.copyWith(
        currentStep: order[index + 1],
        clearMessage: state.submitState == ReportSubmitState.idle,
      );
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
  ///
  /// AUD-S2-04: la confirmación es un ARGUMENTO del envío, no estado del
  /// controller. Mutar el borrador (ubicación/fotos/municipio) y volver a
  /// enviar SIN pulsar "Es otra fuga" de nuevo viaja con
  /// `p_ignore_duplicate: false`.
  Future<void> continueAsNewLeak() async {
    state = state.copyWith(currentStep: ReportStep.review, clearMessage: true);
    await submit(ignoreDuplicate: true);
  }

  /// El usuario acepta usar el reporte existente: cierra el flujo sin
  /// duplicar (no se crea ningún reporte; la UI lo refleja como
  /// "dup-aceptado", nunca como "enviado" — FUNCTIONAL_SPEC §12).
  void useExistingReport() => state = state.copyWith(
    currentStep: ReportStep.result,
    message:
        'Usaste el reporte existente. Puedes validarlo en su '
        'detalle.',
  );

  // ---------- Envío ----------

  Future<void> submit({bool ignoreDuplicate = false}) async {
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
          .createReport(state.draft, ignoreDuplicate: ignoreDuplicate);
      switch (outcome) {
        case ReportCreated(:final reportId):
          state = state.copyWith(
            submitState: ReportSubmitState.done,
            outcome: outcome,
            currentStep: ReportStep.result,
            message:
                '¡Reporte enviado! La fuga quedó registrada como '
                'activa (ID $reportId).',
          );
        case PossibleDuplicateFound(:final candidates):
          state = state.copyWith(
            submitState: ReportSubmitState.duplicate,
            outcome: outcome,
            message:
                'Ya existe un reporte de fuga cerca '
                '(${candidates.first.distanceMeters} m).',
          );
        case LeakReportUnauthorized():
          state = state.copyWith(
            submitState: ReportSubmitState.idle,
            message: 'Tu sesión no está activa. Cierra y abre la app de nuevo.',
          );
      }
    } on LeakFlowException catch (e) {
      state = state.copyWith(
        submitState: ReportSubmitState.idle,
        message: e.userMessage,
      );
    } on AppException catch (e) {
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
