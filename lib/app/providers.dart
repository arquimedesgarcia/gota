import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/app_user.dart';
import '../shared/services/auth_repository.dart';

/// Arranque de sesión: garantiza sesión anónima y perfil `app_users`.
///
/// Mientras carga se muestra [LoadingView]; si falla, [ErrorView] con
/// "Reintentar" (`ref.invalidate`).
final sessionBootstrapProvider = FutureProvider<AppUser>(
  (ref) => ref.watch(authRepositoryProvider).ensureSessionAndProfile(),
);
