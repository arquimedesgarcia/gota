import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leaks/data/community_summary_repository.dart';
import '../../leaks/domain/community_summary.dart';

/// Servicio que programa y envía la notificación local de resumen diario
/// a las 8:00 pm hora de Caracas (UTC-4, sin horario de verano).
///
/// Actualmente siempre activo. En un sprint futuro se integrará con una
/// preferencia en la pantalla de Ajustes para activarlo/desactivarlo.
///
/// Limitación: requiere que la app esté en primer o segundo plano a las
/// 8 pm para disparar el timer. La integración con Firebase Cloud
/// Messaging (server-side cron) permitirá enviarlo también con la app
/// cerrada en una iteración posterior.
class DailyDigestService {
  DailyDigestService({
    required FlutterLocalNotificationsPlugin notifications,
    required CommunitySummaryRepository summaryRepository,
  })  : _notifications = notifications,
        _summaryRepository = summaryRepository;

  final FlutterLocalNotificationsPlugin _notifications;
  final CommunitySummaryRepository _summaryRepository;
  Timer? _timer;
  bool _initialized = false;

  static const _kChannelId = 'daily_summary';
  static const _kChannelName = 'Resumen diario';
  static const _kNotificationId = 1001;

  /// Inicializa el plugin de notificaciones locales y programa el primer
  /// disparo. Idempotente: llamadas repetidas no duplican el timer.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now().toUtc();
    final target = _next8pmCaracasUtc(now);
    final delay = target.difference(now);
    _timer = Timer(delay, _onTimerFired);
  }

  Future<void> _onTimerFired() async {
    try {
      final summary = await _summaryRepository.todaySummary();
      if (summary.reportedToday > 0 || summary.resolvedToday > 0) {
        await _showNotification(summary);
      }
    } catch (_) {
      // Error silencioso: la notificación simplemente no se muestra.
    } finally {
      _schedule(); // Reprogramar para mañana.
    }
  }

  Future<void> _showNotification(CommunitySummary summary) async {
    final parts = <String>[];
    if (summary.reportedToday > 0) {
      final n = summary.reportedToday;
      parts.add('$n ${n == 1 ? "fuga reportada" : "fugas reportadas"}');
    }
    if (summary.resolvedToday > 0) {
      final n = summary.resolvedToday;
      parts.add('$n ${n == 1 ? "resuelta" : "resueltas"}');
    }
    if (parts.isEmpty) return;

    final body = parts.join(', ');
    final bodyCapitalized =
        '${body[0].toUpperCase()}${body.substring(1)} en tu comunidad.';

    await _notifications.show(
      _kNotificationId,
      'Resumen del día · Gota',
      bodyCapitalized,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          channelDescription:
              'Resumen diario de actividad comunitaria en Gota.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Calcula el próximo momento 8:00 pm hora Caracas expresado en UTC.
  ///
  /// Venezuela usa UTC-4 todo el año (sin horario de verano desde 2016).
  static DateTime _next8pmCaracasUtc(DateTime nowUtc) {
    const caracasOffsetHours = 4; // UTC - 4 → nowCaracas = nowUtc - 4 h
    final caracasNow =
        nowUtc.subtract(const Duration(hours: caracasOffsetHours));
    final today8pm = DateTime(
      caracasNow.year,
      caracasNow.month,
      caracasNow.day,
      20,
    );
    final targetCaracas = today8pm.isAfter(caracasNow)
        ? today8pm
        : today8pm.add(const Duration(days: 1));
    return targetCaracas.add(const Duration(hours: caracasOffsetHours));
  }
}

/// Proveedor del servicio de resumen diario. Se construye una sola vez
/// y se destruye con el scope (salida de sesión).
final dailyDigestServiceProvider = Provider<DailyDigestService>((ref) {
  final notifications = FlutterLocalNotificationsPlugin();
  final repository = ref.watch(communitySummaryRepositoryProvider);
  final service = DailyDigestService(
    notifications: notifications,
    summaryRepository: repository,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Arranca e inicializa el servicio de resumen diario junto con la
/// sesión del usuario. Solo debe observarse en la raíz del árbol.
final dailyDigestBootstrapProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(dailyDigestServiceProvider);
  await service.initialize();
});
