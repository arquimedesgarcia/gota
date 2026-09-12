import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/models/municipality.dart';
import '../../../shared/models/sector.dart';
import '../data/water_event_repository.dart';
import '../domain/water_errors.dart';
import '../domain/water_event_type.dart';

enum WaterRegisterSubmitStatus { idle, submitting, done, error }

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
  });

  final String? municipalityId;
  final String? municipalityName;
  final String? sectorId;
  final String? sectorName;
  final DateTime? eventTime;
  final String comment;
  final WaterRegisterSubmitStatus submitStatus;
  final String? errorMessage;

  WaterRegisterState copyWith({
    String? municipalityId,
    String? municipalityName,
    String? sectorId,
    String? sectorName,
    DateTime? eventTime,
    String? comment,
    WaterRegisterSubmitStatus? submitStatus,
    String? errorMessage,
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
  );
}

/// Controller del flujo de registro de un evento de agua. Las reglas de
/// negocio las valida el backend; aquí solo validación local de campos
/// obligatorios y traducción de errores a mensajes para el usuario.
class WaterRegisterController extends Notifier<WaterRegisterState> {
  @override
  WaterRegisterState build() => const WaterRegisterState();

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

  /// Envía el evento. Devuelve true solo cuando el backend confirmó la
  /// creación (CREATED); cualquier otro resultado queda como estado de
  /// error con mensaje y no debe cerrar el flujo.
  Future<bool> submit(WaterEventType type) async {
    if (state.submitStatus == WaterRegisterSubmitStatus.submitting) {
      return false;
    }

    // Validación local: sin llamada al backend.
    final eventTime = state.eventTime;
    if (state.municipalityId == null || state.sectorId == null) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'Indica el municipio y el sector del evento.',
      );
      return false;
    }
    if (eventTime == null) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'Indica la hora del evento.',
      );
      return false;
    }
    if (eventTime.isAfter(DateTime.now())) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'La hora del evento no puede estar en el futuro.',
      );
      return false;
    }

    state = state.copyWith(
      submitStatus: WaterRegisterSubmitStatus.submitting,
      clearError: true,
    );
    try {
      await ref
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
      return true;
    } on WaterException catch (e) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: e.userMessage,
      );
      return false;
    } on AppException catch (e) {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: e.userMessage,
      );
      return false;
    } on Exception {
      state = state.copyWith(
        submitStatus: WaterRegisterSubmitStatus.error,
        errorMessage: 'No pudimos registrar el evento. Intenta de nuevo.',
      );
      return false;
    }
  }
}

final waterRegisterControllerProvider =
    NotifierProvider<WaterRegisterController, WaterRegisterState>(
      WaterRegisterController.new,
    );
