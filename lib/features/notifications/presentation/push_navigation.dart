import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../../app/router/app_navigator.dart';
import '../../water/presentation/water_event_detail_screen.dart';
import 'notifications_screen.dart';

/// Navegación al tocar una notificación push (Sprint 06).
///
/// El payload `data` de FCM trae `water_event_id`: si está presente se abre
/// el Water Event correspondiente; si no, la bandeja. Si el Navigator aún
/// no existe (cold start), la navegación se encola y se reintenta en el
/// siguiente frame, con un límite de reintentos para no colgar.
void navigateFromPush(RemoteMessage message, {int retriesLeft = 10}) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) {
    if (retriesLeft <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigateFromPush(message, retriesLeft: retriesLeft - 1);
    });
    return;
  }

  final waterEventId = message.data['water_event_id'];
  if (waterEventId is String && waterEventId.isNotEmpty) {
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => WaterEventDetailScreen(eventId: waterEventId),
      ),
    );
    return;
  }
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
  );
}
