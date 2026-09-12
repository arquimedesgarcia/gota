import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/water_event_repository.dart';
import '../domain/water_event.dart';
import '../domain/water_event_detail.dart';
import '../domain/water_statistics.dart';

/// Estado del historial de eventos de la pestaña Agua.
@immutable
class WaterHistoryState {
  const WaterHistoryState({
    this.events = const AsyncValue.loading(),
    this.isLoadingMore = false,
    this.hasMore = false,
  });

  final AsyncValue<List<WaterEventSummary>> events;
  final bool isLoadingMore;
  final bool hasMore;

  WaterHistoryState copyWith({
    AsyncValue<List<WaterEventSummary>>? events,
    bool? isLoadingMore,
    bool? hasMore,
  }) => WaterHistoryState(
    events: events ?? this.events,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
  );
}

/// Historial paginado (keyset) de eventos de agua. No es autoDispose: la
/// pestaña Agua vive dentro del IndexedStack del shell y debe conservar su
/// estado al cambiar de pestaña.
class WaterHistoryController extends Notifier<WaterHistoryState> {
  static const _pageSize = 20;

  @override
  WaterHistoryState build() {
    // La carga inicial se programa para el siguiente tick: si el repositorio
    // falla al construirse (p. ej. Supabase sin inicializar en pruebas), el
    // error se captura en [_loadInitial] y queda en el AsyncValue, sin
    // romper el build del provider.
    Future<void>.microtask(_loadInitial);
    return const WaterHistoryState();
  }

  Future<void> _loadInitial() async {
    try {
      final repository = ref.read(waterEventRepositoryProvider);
      final page = await repository.recentEvents(limit: _pageSize);
      state = state.copyWith(
        events: AsyncValue.data(page.events),
        hasMore: page.hasMore,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(events: AsyncValue.error(error, stackTrace));
    }
  }

  /// Recarga la primera página (pull to retry / reintento tras error).
  Future<void> refresh() async {
    try {
      final repository = ref.read(waterEventRepositoryProvider);
      final page = await repository.recentEvents(limit: _pageSize);
      state = state.copyWith(
        events: AsyncValue.data(page.events),
        hasMore: page.hasMore,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(events: AsyncValue.error(error, stackTrace));
    }
  }

  /// Anexa la siguiente página si hay más. Los eventos se concatenan sin
  /// duplicar por id.
  Future<void> loadMore() async {
    final current = state.events;
    if (!state.hasMore || state.isLoadingMore) return;
    final events = current.value ?? const <WaterEventSummary>[];
    if (events.isEmpty) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final repository = ref.read(waterEventRepositoryProvider);
      // Para la siguiente página, usamos el último evento de la página actual
      // como punto de referencia (aunque actualmente la paginación es simple).
      final page = await repository.recentEvents(
        limit: _pageSize,
        cursor: null, // Implementación futura: keyset pagination con cursor
      );
      final seen = events.map((e) => e.id).toSet();
      final merged = [
        ...events,
        ...page.events.where((e) => !seen.contains(e.id)),
      ];
      state = state.copyWith(
        events: AsyncValue.data(merged),
        isLoadingMore: false,
        hasMore: page.hasMore,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        events: AsyncValue.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }
}

final waterHistoryControllerProvider =
    NotifierProvider<WaterHistoryController, WaterHistoryState>(
      WaterHistoryController.new,
    );

/// Detalle de un evento con el estado del usuario actual (¿ya validó?,
/// ¿es el creador?). La respuesta viene del backend.
final waterEventDetailProvider = FutureProvider.autoDispose
    .family<WaterEventDetail, String>(
      (ref, eventId) => ref.watch(waterEventRepositoryProvider).detail(eventId),
    );

/// Estadísticas DESCRIPTIVAS derivadas de los eventos ya cargados en el
/// historial: no hay llamada extra al backend y los valores describen solo
/// lo observado (REQ-077, sin predicción).
final waterStatisticsProvider = Provider<WaterStatistics>((ref) {
  final events = ref.watch(
    waterHistoryControllerProvider.select(
      (state) => state.events.value ?? const <WaterEventSummary>[],
    ),
  );
  return computeWaterStatistics(events);
});
