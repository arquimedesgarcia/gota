import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/app_config.dart';
import 'core/errors/app_exception.dart';
import 'shared/models/app_user.dart';

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
        publishableKey: config.supabaseAnonKey,
      );
      supabaseReady = true;
    } catch (_) {
      // La app arranca igual y muestra una pantalla de error con reintento.
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
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
