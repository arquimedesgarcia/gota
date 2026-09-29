import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/models/municipality.dart';
import '../../../shared/models/sector.dart';
import '../../leaks/data/geolocator_location_service.dart';
import '../../leaks/data/location_service.dart';
import '../../leaks/data/reverse_geocoding_service.dart';
import '../../leaks/domain/leak_errors.dart';
import '../../leaks/domain/location_suggestion.dart';
import '../../location/presentation/location_providers.dart';
import '../data/water_event_repository.dart';
import '../domain/water_errors.dart';
import '../domain/water_event_type.dart';
import 'water_providers.dart';

enum WaterRegisterSubmitStatus { idle, submitting, done, error }

/// Resultado de un submit exitoso: `created` = evento nuevo;
/// `confirmed` = se confirmó un evento reciente de otro vecino.
enum WaterSubmitOutcome { created, confirmed }

/// Estado del flujo de registro de un evento de agua. Tras migrar a GPS +
/// reverse geocoding (paridad con Reportar fuga), el flujo es:
/// tipo → ubicación (mapa/GPS + municipio/sector) → resumen. El tipo se elige
/// fuera o en el primer paso y se confirma al enviar.
@immutable
class WaterRegisterState {
  const WaterRegisterState({
    this.municipalityId,
    this.municipalityName,
    this.sectorId,
    this.sectorName,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.isGpsLocation = false,
    this.manualModeEnabled = false,
    this.address,
    this.locationSuggestion,
    this.suggestionLoading = false,
    this.eventTime,
    this.comment = '',
    this.submitStatus = WaterRegisterSubmitStatus.idle,
    this.errorMessage,
    this.currentStep = 0,
  });

  final String? municipalityId;
  final String? municipalityName;
  final String? sectorId;
  final String? sectorName;

  /// Ubicación capturada por GPS o tocando el mapa.
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final bool isGpsLocation;

  /// `true` cuando el usuario eligió completar la ubicación a mano (sin GPS),
  /// seleccionando municipio y sector directamente en los combos del paso.
  final bool manualModeEnabled;

  /// Dirección completa sugerida por el reverse-geocoder (se persiste con el
  /// evento y se muestra en su detalle).
  final String? address;

  /// Sugerencia cruda del geocoder (para la tarjeta "Ubicación aproximada").
  final LocationSuggestion? locationSuggestion;
  final bool suggestionLoading;

  final DateTime? eventTime;
  final String comment;
  final WaterRegisterSubmitStatus submitStatus;
  final String? errorMessage;

  /// Paso actual del Stepper (0 = tipo, 1 = ubicación, 2 = resumen). Vive aquí
  /// y no en el widget para sobrevivir a cambios de configuración (rotación).
  final int currentStep;

  bool get hasLocation => latitude != null && longitude != null;

  WaterRegisterState copyWith({
    String? municipalityId,
    String? municipalityName,
    String? sectorId,
    String? sectorName,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    bool? isGpsLocation,
    String? address,
    LocationSuggestion? locationSuggestion,
    bool? suggestionLoading,
    DateTime? eventTime,
    String? comment,
    WaterRegisterSubmitStatus? submitStatus,
    String? errorMessage,
    int? currentStep,
    bool clearError = false,
    bool clearSector = false,
    bool clearLocation = false,
    bool clearLocationSuggestion = false,
    bool? manualModeEnabled,
  }) => WaterRegisterState(
    municipalityId: municipalityId ?? this.municipalityId,
    municipalityName: municipalityName ?? this.municipalityName,
    sectorId: clearSector ? null : (sectorId ?? this.sectorId),
    sectorName: clearSector ? null : (sectorName ?? this.sectorName),
    latitude: clearLocation ? null : (latitude ?? this.latitude),
    longitude: clearLocation ? null : (longitude ?? this.longitude),
    accuracyMeters: clearLocation ? null : (accuracyMeters ?? this.accuracyMeters),
    isGpsLocation: clearLocation ? false : (isGpsLocation ?? this.isGpsLocation),
    manualModeEnabled: manualModeEnabled ?? this.manualModeEnabled,
    address: (clearLocation || clearLocationSuggestion) ? null : (address ?? this.address),
    locationSuggestion: (clearLocation || clearLocationSuggestion)
        ? null
        : (locationSuggestion ?? this.locationSuggestion),
    suggestionLoading: suggestionLoading ?? this.suggestionLoading,
    eventTime: eventTime ?? this.eventTime,
    comment: comment ?? this.comment,
    submitStatus: submitStatus ?? this.submitStatus,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    currentStep: currentStep ?? this.currentStep,
  );
}

/// Controller del flujo de registro de un evento de agua. Las reglas de
/// negocio las valida el backend; aquí solo validación local de campos
/// obligatorios, captura de ubicación (GPS + reverse geocoding, reutilizando
/// los servicios del flujo de fugas) y traducción de errores a mensajes.
class WaterRegisterController extends Notifier<WaterRegisterState> {
  LocationService get _locationService => ref.watch(locationServiceProvider);
  ReverseGeocodingService get _reverseGeocoder =>
      ref.watch(reverseGeocodingServiceProvider);

  /// Descarta sugerencias obsoletas cuando el usuario vuelve a pedir GPS o
  /// mueve el pin antes de que responda el geocoder anterior.
  int _locationRequestId = 0;

  @override
  WaterRegisterState build() => WaterRegisterState(eventTime: DateTime.now());

  // ---------- Municipio / sector ----------

  void selectMunicipality(Municipality municipality) => state = state.copyWith(
    municipalityId: municipality.id,
    municipalityName: municipality.name,
    // El sector depende del municipio: se reinicia al cambiarlo.
    clearSector: true,
    clearError: true,
  );

  void selectSector(Sector sector) => state = state.copyWith(
    sectorId: sector.id,
    sectorName: sector.name,
    clearError: true,
  );

  // ---------- Ubicación (GPS + reverse geocoding) ----------

  /// Activa el modo manual: descarta el GPS y oculta el mapa/sugerencia.
  void enterManualMode() {
    ++_locationRequestId;
    state = state.copyWith(
      manualModeEnabled: true,
      clearLocation: true,
      clearLocationSuggestion: true,
      suggestionLoading: false,
      clearError: true,
    );
  }

  /// Solicita la posición actual por GPS y dispara el reverse-geocode.
  Future<void> requestGps() async {
    final requestId = ++_locationRequestId;
    try {
      final position = await _locationService.getCurrentPosition();
      state = state.copyWith(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracyMeters,
        isGpsLocation: true,
        clearError: true,
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
        errorMessage: e.userMessage,
        clearLocationSuggestion: true,
        suggestionLoading: false,
      );
    }
  }

  /// Ajusta la ubicación tocando el mapa (o vía diálogo manual) y vuelve a
  /// geocodificar.
  Future<void> setManualLocation({
    required double latitude,
    required double longitude,
  }) async {
    final requestId = ++_locationRequestId;
    state = state.copyWith(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: null,
      isGpsLocation: false,
      clearError: true,
      clearLocationSuggestion: true,
      suggestionLoading: true,
    );
    await _loadSuggestion(
      requestId: requestId,
      latitude: latitude,
      longitude: longitude,
    );
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
        address: suggestion?.displayText,
        suggestionLoading: false,
      );
      if (suggestion != null) {
        await _applyLocationSuggestion(
          requestId: requestId,
          suggestion: suggestion,
        );
      }
    } on ReverseGeocodingException {
      if (requestId != _locationRequestId) return;
      // El geocoder es una ayuda: su fallo no bloquea el registro ni se
      // muestra como error (el usuario elige municipio/sector a mano).
      state = state.copyWith(suggestionLoading: false);
    } catch (_) {
      if (requestId != _locationRequestId) return;
      state = state.copyWith(suggestionLoading: false);
    }
  }

  /// Autocompleta municipio y sector a partir del reverse-geocode, cuando hay
  /// una coincidencia única en el catálogo. El usuario siempre puede
  /// corregirlos después.
  Future<void> _applyLocationSuggestion({
    required int requestId,
    required LocationSuggestion suggestion,
  }) async {
    final rawMunicipality = suggestion.municipality ?? suggestion.city;
    if (rawMunicipality == null) return;

    try {
      final municipalities = await ref.read(municipalitiesProvider.future);
      if (requestId != _locationRequestId) return;

      final matchedMunicipality = _matchUnique(
        _normalize(rawMunicipality),
        municipalities.map((m) => (id: m.id, name: m.name)),
      );
      if (matchedMunicipality == null) return;

      final municipality =
          municipalities.firstWhere((m) => m.id == matchedMunicipality);
      state = state.copyWith(
        municipalityId: municipality.id,
        municipalityName: municipality.name,
        clearSector: true,
      );

      final localityText =
          suggestion.locality ?? suggestion.neighborhood ?? suggestion.city;
      if (localityText == null) return;

      final sectors = await ref.read(sectorsProvider(municipality.id).future);
      if (requestId != _locationRequestId) return;

      final matchedSector = _matchUnique(
        _normalize(localityText),
        sectors.map((s) => (id: s.id, name: s.name)),
      );
      if (matchedSector == null) return;

      final sector = sectors.firstWhere((s) => s.id == matchedSector);
      state = state.copyWith(sectorId: sector.id, sectorName: sector.name);
    } catch (_) {
      // Best-effort: la autocompletación es opcional.
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

  // ---------- Hora / comentario ----------

  void selectEventTime(DateTime eventTime) =>
      state = state.copyWith(eventTime: eventTime, clearError: true);

  void setComment(String comment) =>
      state = state.copyWith(comment: comment, clearError: true);

  /// Navegación del Stepper (0 = tipo, 1 = ubicación, 2 = resumen).
  void goToStep(int step) {
    if (step >= 0 && step <= 2) {
      state = state.copyWith(currentStep: step);
    }
  }

  void nextStep() => goToStep(state.currentStep + 1);

  void previousStep() => goToStep(state.currentStep - 1);

  /// Envía el evento. Devuelve el resultado cuando el backend confirma la
  /// operación (`created` o `confirmed`); devuelve `null` si hay error (el
  /// mensaje queda en `state.errorMessage` y el flujo no se cierra).
  Future<WaterSubmitOutcome?> submit(WaterEventType type) async {
    if (state.submitStatus == WaterRegisterSubmitStatus.submitting) {
      return null;
    }

    // Validación local: sin llamada al backend.
    final eventTime = state.eventTime;
    if (state.municipalityId == null || state.sectorId == null) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'Indica el municipio y el sector del evento.',
      );
      return null;
    }
    if (eventTime == null) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'Indica la hora del evento.',
      );
      return null;
    }
    if (eventTime.isAfter(DateTime.now())) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'La hora del evento no puede estar en el futuro.',
      );
      return null;
    }

    state = state.copyWith(
      submitStatus: WaterRegisterSubmitStatus.submitting,
      clearError: true,
    );
    try {
      final (_, isConfirmation) = await ref
          .read(waterEventRepositoryProvider)
          .register(
            municipalityId: state.municipalityId!,
            sectorId: state.sectorId!,
            type: type,
            eventTime: eventTime,
            comment: state.comment.trim().isEmpty ? null : state.comment.trim(),
            address: state.address,
          );
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.done,
        clearError: true,
      );
      ref.read(waterHistoryControllerProvider.notifier).refresh();
      return isConfirmation ? WaterSubmitOutcome.confirmed : WaterSubmitOutcome.created;
    } on WaterException catch (e) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: e.userMessage,
      );
      return null;
    } on AppException catch (e) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: e.userMessage,
      );
      return null;
    } on Exception {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'No pudimos registrar el evento. Intenta de nuevo.',
      );
      return null;
    }
  }
}

final waterRegisterControllerProvider =
    NotifierProvider<WaterRegisterController, WaterRegisterState>(
      WaterRegisterController.new,
    );
