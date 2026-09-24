import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/notification_repository.dart';
import '../data/push_service.dart';
import '../domain/notification_preferences.dart';
import '../domain/water_notification.dart';
import 'push_navigation.dart';

/// Preferencias de notificación del usuario (futuro simple de una sola
/// lectura; los cambios pasan por [NotificationPreferencesController]).
final notificationPreferencesProvider =
    FutureProvider<NotificationPreferences?>(
      (ref) => ref.watch(notificationRepositoryProvider).getPreferences(),
    );

/// Preferencias con estado de guardado: `null` dentro de [AsyncData] significa
/// que el usuario aún no tiene fila (primera escritura la crea).
class NotificationPreferencesController
    extends Notifier<AsyncValue<NotificationPreferences?>> {
  Object? _saveError;

  /// Error del último intento de guardado (`null` si tuvo éxito). Permite a
  /// quien inició el guardado distinguir el fallo de una vuelta a datos;
  /// no se propaga como excepción.
  Object? get saveError => _saveError;

  @override
  AsyncValue<NotificationPreferences?> build() {
    Future<void>.microtask(_load);
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    try {
      final preferences = await ref
          .read(notificationRepositoryProvider)
          .getPreferences();
      state = AsyncValue.data(preferences);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> selectSector(String sectorId) => _save(sectorId: sectorId);

  Future<void> clearSector() => _save(clearSector: true);

  Future<void> setWaterNotificationsEnabled(bool enabled) =>
      _save(enabled: enabled);

  Future<void> _save({
    String? sectorId,
    bool? enabled,
    bool clearSector = false,
  }) async {
    final previousState = state;
    if (!clearSector && !previousState.hasValue) {
      _saveError = StateError(
        'Tus preferencias aún están cargando. Intenta de nuevo en un momento.',
      );
      state = AsyncValue.error(_saveError!, StackTrace.current);
      return;
    }
    final current = previousState.value;
    _saveError = null;
    state = const AsyncValue<NotificationPreferences?>.loading();
    try {
      final saved = await ref
          .read(notificationRepositoryProvider)
          .savePreferences(
            sectorId: clearSector
                ? null
                : (sectorId ?? current?.preferredSectorId),
            enabled: enabled ?? current?.waterNotificationsEnabled ?? false,
          );
      state = AsyncValue.data(saved);
      ref.invalidate(notificationPreferencesProvider);
    } catch (error, stackTrace) {
      _saveError = error;
      // Volvemos al dato previo si había; si no, el error queda en el estado
      // para que la UI pueda mostrarlo. No se propaga.
      state = previousState.hasValue
          ? previousState
          : AsyncValue.error(error, stackTrace);
    }
  }
}

final notificationPreferencesControllerProvider =
    NotifierProvider<NotificationPreferencesController,
        AsyncValue<NotificationPreferences?>>(
          NotificationPreferencesController.new,
        );

/// Estado de la bandeja de notificaciones.
@immutable
class NotificationInboxState {
  const NotificationInboxState({
    this.items = const AsyncValue.loading(),
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextBeforeIso,
  });

  final AsyncValue<List<WaterNotification>> items;
  final bool isLoadingMore;
  final bool hasMore;

  /// Cursor keyset para la siguiente página (`created_at` ISO del último
  /// item, solo si la página vino llena).
  final String? nextBeforeIso;

  NotificationInboxState copyWith({
    AsyncValue<List<WaterNotification>>? items,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextBeforeIso,
  }) => NotificationInboxState(
    items: items ?? this.items,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    nextBeforeIso: nextBeforeIso ?? this.nextBeforeIso,
  );
}

/// Bandeja paginada (keyset) + suscripción realtime. No es autoDispose: la
/// pestaña Más vive dentro del IndexedStack del shell y debe conservar su
/// estado al cambiar de pestaña.
class NotificationInboxController extends Notifier<NotificationInboxState> {
  static const _pageSize = 20;

  @override
  NotificationInboxState build() {
    Future<void>.microtask(_loadInitial);
    final session = ref.watch(sessionBootstrapProvider);
    if (session.hasValue) {
      final sub = ref
          .watch(notificationRepositoryProvider)
          .watchNotifications(session.value!.id)
          .listen((_) => refresh());
      ref.onDispose(sub.cancel);
    }
    return const NotificationInboxState();
  }

  Future<void> _loadInitial() async {
    try {
      final repository = ref.read(notificationRepositoryProvider);
      final page = await repository.fetchInbox(limit: _pageSize);
      state = NotificationInboxState(
        items: AsyncValue.data(page.items),
        hasMore: page.nextBeforeIso != null,
        nextBeforeIso: page.nextBeforeIso,
      );
    } catch (error, stackTrace) {
      state = NotificationInboxState(
        items: AsyncValue.error(error, stackTrace),
      );
    }
  }

  /// Recarga la primera página (pull to refresh / reintento / realtime).
  Future<void> refresh() async {
    try {
      final repository = ref.read(notificationRepositoryProvider);
      final page = await repository.fetchInbox(limit: _pageSize);
      state = NotificationInboxState(
        items: AsyncValue.data(page.items),
        hasMore: page.nextBeforeIso != null,
        nextBeforeIso: page.nextBeforeIso,
      );
    } catch (error, stackTrace) {
      state = NotificationInboxState(
        items: AsyncValue.error(error, stackTrace),
      );
    }
  }

  /// Anexa la siguiente página si hay más, sin duplicar por id.
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;
    final items = state.items.value ?? const <WaterNotification>[];
    if (items.isEmpty) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final repository = ref.read(notificationRepositoryProvider);
      final page = await repository.fetchInbox(
        limit: _pageSize,
        beforeIso: state.nextBeforeIso,
      );
      final seen = items.map((n) => n.id).toSet();
      final merged = [
        ...items,
        ...page.items.where((n) => !seen.contains(n.id)),
      ];
      state = state.copyWith(
        items: AsyncValue.data(merged),
        isLoadingMore: false,
        hasMore: page.nextBeforeIso != null,
        nextBeforeIso: page.nextBeforeIso,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        items: AsyncValue.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  /// Marca como leída con actualización optimista; si falla, se revierte
  /// recargando la bandeja.
  Future<void> markRead(String id) async {
    final items = state.items.value;
    if (items == null) return;
    final optimistic = [
      for (final n in items) n.id == id ? n.copyWith(readAt: DateTime.now()) : n,
    ];
    state = state.copyWith(items: AsyncValue.data(optimistic));
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
    } catch (_) {
      await refresh();
    }
  }
}

final notificationInboxControllerProvider =
    NotifierProvider<NotificationInboxController, NotificationInboxState>(
      NotificationInboxController.new,
    );

/// Número de notificaciones sin leer (badge en la pestaña Más).
final unreadCountProvider = Provider<int>((ref) {
  final items = ref.watch(
    notificationInboxControllerProvider.select(
      (state) => state.items.value ?? const <WaterNotification>[],
    ),
  );
  return items.where((n) => n.isUnread).length;
});

/// Arranque del push tras la sesión: permiso, registro del token FCM,
/// refresco de la bandeja y apertura desde notificación del sistema.
/// Devuelve el estado del permiso para que Ajustes pueda informar si fue
/// denegado.
final pushBootstrapProvider = FutureProvider<PushPermissionStatus>((ref) async {
  final push = ref.watch(pushServiceProvider);
  final repo = ref.watch(notificationRepositoryProvider);

  PushPermissionStatus status;
  try {
    status = await push.requestPermission();
  } catch (_) {
    status = PushPermissionStatus.unavailable;
  }

  Future<void> registerToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await repo.registerToken(token, _platformWireName);
    } catch (_) {}
  }

  await registerToken(await _safeToken(push));

  final refreshSub = push.tokenRefresh.listen(registerToken);
  final fgSub = push.onMessageForeground.listen((_) {
    ref.invalidate(notificationInboxControllerProvider);
  });
  final openSub = push.onMessageOpenedApp.listen(navigateFromPush);
  ref.onDispose(() {
    refreshSub.cancel();
    fgSub.cancel();
    openSub.cancel();
  });

  // Cold start: la app fue lanzada tocando una notificación (terminated).
  try {
    final initialMessage = await push.getInitialMessage();
    if (initialMessage != null) navigateFromPush(initialMessage);
  } catch (_) {}

  return status;
});

Future<String?> _safeToken(PushService push) async {
  try {
    return await push.getToken();
  } catch (_) {
    return null;
  }
}

String get _platformWireName => switch (defaultTargetPlatform) {
  TargetPlatform.android => 'android',
  TargetPlatform.iOS => 'ios',
  _ => 'web',
};
