import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado del permiso de notificaciones push.
enum PushPermissionStatus { granted, denied, unavailable }

/// Abstracción sobre Firebase Cloud Messaging. Permite arrancar la app sin
/// Firebase configurado (Noop) y sustituir el servicio en pruebas.
abstract class PushService {
  Future<PushPermissionStatus> requestPermission();
  Future<String?> getToken();
  Stream<String> get tokenRefresh;

  /// Mensajes recibidos con la app en primer plano.
  Stream<RemoteMessage> get onMessageForeground;

  /// Mensajes que abrieron la app desde segundo plano/terminada.
  Stream<RemoteMessage> get onMessageOpenedApp;
}

/// Implementación sin Firebase: la app funciona sin push (avisos solo
/// dentro de Gota vía bandeja realtime).
class NoopPushService implements PushService {
  const NoopPushService();

  @override
  Future<PushPermissionStatus> requestPermission() async =>
      PushPermissionStatus.unavailable;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get tokenRefresh => const Stream<String>.empty();

  @override
  Stream<RemoteMessage> get onMessageForeground => const Stream<RemoteMessage>.empty();

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => const Stream<RemoteMessage>.empty();
}

class FcmPushService implements PushService {
  FcmPushService(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<PushPermissionStatus> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized
        ? PushPermissionStatus.granted
        : PushPermissionStatus.denied;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onMessageForeground => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;
}

/// Por defecto arranca en modo no-op; `main.dart` lo sobreescribe con
/// [FcmPushService] cuando Firebase inicializa correctamente.
final pushServiceProvider = Provider<PushService>(
  (ref) => const NoopPushService(),
);
