import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/app_config.dart';
import 'core/errors/app_exception.dart';
import 'features/notifications/data/push_service.dart';
import 'shared/models/app_user.dart';

/// Handler de FCM en background/terminated: la notificación ya fue
/// persistida server-side; el plugin muestra la notificación del sistema.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig? config;
  var supabaseReady = false;
  try {
    config = AppConfig.fromEnvironment();
  } on ConfigMissingException {
    config = null;
  }

  if (config != null) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
        // Timeout por solicitud: un intento que se cuelga se cancela y, tras
        // agotar los reintentos internos, llega a los repositorios como
        // TimeoutException, que se traduce a NetworkException.
        postgrestOptions: const PostgrestClientOptions(
          requestTimeout: Duration(seconds: 20),
        ),
      );
      supabaseReady = true;
    } catch (_) {
      // La app arranca igual y muestra una pantalla de error con reintento.
    }
  }

  // Fail-soft: sin google-services.json la app arranca sin push (NoopPushService).
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        pushServiceProvider.overrideWithValue(
          firebaseReady
              ? FcmPushService(FirebaseMessaging.instance)
              : const NoopPushService(),
        ),
        // Si Supabase no pudo inicializarse, la sesión falla con un
        // mensaje de red en lugar de crashear al tocar el cliente.
        if (!supabaseReady)
          sessionBootstrapProvider.overrideWith(
            (ref) => Future<AppUser>.error(const NetworkException()),
          ),
      ],
      child: const GotaApp(),
    ),
  );
}
