import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/models/municipality.dart';
import '../../../shared/models/sector.dart';
import '../data/water_event_repository.dart';
import '../domain/water_errors.dart';
import '../domain/water_event_type.dart';
import 'water_providers.dart';

enum WaterRegisterSubmitStatus { idle, submitting, done, error }

/// Resultado de un submit exitoso: `created` = evento nuevo;
/// `confirmed` = se confirmó un evento reciente de otro vecino.
enum WaterSubmitOutcome { created, confirmed }

/// Estado del flujo de registro de un evento de agua (municipio → sector →
/// hora → comentario → revisar). El tipo se elige fuera o en el primer paso
/// y se confirma al enviar.
@immutable
class WaterRegisterState {
  const WaterRegisterState({
    this.municipalityId,
    this.municipalityName,
    this.sectorId,
    this.sectorName,
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
  final DateTime? eventTime;
  final String comment;
  final WaterRegisterSubmitStatus submitStatus;
  final String? errorMessage;

  /// Paso actual del Stepper (0-3). Vive aquí y no en el widget para
  /// sobrevivir a cambios de configuración (p. ej. rotación).
  final int currentStep;

  WaterRegisterState copyWith({
    String? municipalityId,
    String? municipalityName,
    String? sectorId,
    String? sectorName,
    DateTime? eventTime,
    String? comment,
    WaterRegisterSubmitStatus? submitStatus,
    String? errorMessage,
    int? currentStep,
    bool clearError = false,
  }) => WaterRegisterState(
    municipalityId: municipalityId ?? this.municipalityId,
    municipalityName: municipalityName ?? this.municipalityName,
    sectorId: sectorId ?? this.sectorId,
    sectorName: sectorName ?? this.sectorName,
    eventTime: eventTime ?? this.eventTime,
    comment: comment ?? this.comment,
    submitStatus: submitStatus ?? this.submitStatus,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    currentStep: currentStep ?? this.currentStep,
  );
}

/// Controller del flujo de registro de un evento de agua. Las reglas de
/// negocio las valida el backend; aquí solo validación local de campos
/// obligatorios y traducción de errores a mensajes para el usuario.
class WaterRegisterController extends Notifier<WaterRegisterState> {
  @override
  WaterRegisterState build() => WaterRegisterState(eventTime: DateTime.now());

  void selectMunicipality(Municipality municipality) => state = state.copyWith(
    municipalityId: municipality.id,
    municipalityName: municipality.name,
    // El sector depende del municipio: se reinicia al cambiarlo.
    sectorId: null,
    sectorName: null,
    clearError: true,
  );

  void selectSector(Sector sector) => state = state.copyWith(
    sectorId: sector.id,
    sectorName: sector.name,
    clearError: true,
  );

  void selectEventTime(DateTime eventTime) =>
      state = state.copyWith(eventTime: eventTime, clearError: true);

  void setComment(String comment) =>
      state = state.copyWith(comment: comment, clearError: true);

  /// Navegación del Stepper (0 = tipo, 1 = municipio, 2 = sector, 3 = resumen).
  void goToStep(int step) {
    if (step >= 0 && step <= 3) {
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
