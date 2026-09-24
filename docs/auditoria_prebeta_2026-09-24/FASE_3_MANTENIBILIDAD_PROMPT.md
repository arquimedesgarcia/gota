# FASE 3 — Mantenibilidad (refactors P2)

**Prerequisito:** Fases 1 y 2 completadas. `flutter test` en verde.
**Hallazgos corregidos:** H-03, H-04, H-06, H-07
**Commit al terminar:** `fix(quality): fase 3 — eliminar duplicación en repos y providers`

---

## Orden obligatorio

1. C3-01 (crear rate_limit.dart) — no depende de nada.
2. C3-02 (crear rpc_helper.dart) — no depende de nada.
3. C3-03 (usar rate_limit en 3 repos) — depende de C3-01.
4. C3-04 (usar rpc_helper en 4 repos) — depende de C3-02.
5. C3-05 (extraer _buildQueryParams) — independiente.
6. C3-06 (unificar navegación a ReportFlow) — independiente.

Ejecutar `flutter test` después de C3-03, C3-04, C3-05 y C3-06.

---

## Corrección C3-01 — Extraer _rateLimitMessage a core/utils/rate_limit.dart

**Hallazgo:** H-03
**Archivo nuevo:** `lib/core/utils/rate_limit.dart`

### Problema

`_rateLimitMessage(Map<String, dynamic> data)` está copiada con el mismo cuerpo en:
- `lib/features/leaks/data/leak_community_repository.dart`
- `lib/features/leaks/data/leak_report_repository.dart`
- `lib/features/water/data/water_event_repository.dart`

### Crear archivo nuevo

Crear `lib/core/utils/rate_limit.dart` con:

```dart
/// Formatea el mensaje de límite de frecuencia (RATE_LIMIT_EXCEEDED).
///
/// Usa el mensaje del backend y, si viene `reset_at`, añade la hora local
/// de reintento en formato HH:mm.
String formatRateLimitMessage(
  Map<String, dynamic> data, {
  String defaultMessage = 'Has alcanzado el límite por hora.',
}) {
  final base = data['message'] as String? ?? defaultMessage;
  final rawResetAt = data['reset_at'];
  final resetAt = rawResetAt is String ? DateTime.tryParse(rawResetAt) : null;
  if (resetAt == null) return base;
  final local = resetAt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$base Intenta de nuevo después de las $hh:$mm.';
}
```

### Validación

- `flutter analyze` → No issues.

---

## Corrección C3-02 — Extraer helper _rpc a core/utils/rpc_helper.dart

**Hallazgo:** H-04
**Archivo nuevo:** `lib/core/utils/rpc_helper.dart`

### Problema

El helper privado `_rpc(Future<Map> Function() action)` que envuelve llamadas Supabase
en try/catch está duplicado en:
- `leak_community_repository.dart`
- `water_event_repository.dart`
- `notification_repository.dart`

### Crear archivo nuevo

Crear `lib/core/utils/rpc_helper.dart` con:

```dart
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../errors/app_exception.dart';

/// Envuelve una llamada RPC de Supabase traduciendo errores de red y de
/// autenticación a [AppException] tipadas.
///
/// [networkMessage] y [authMessage] permiten personalizar el mensaje de error
/// visible; si se omiten se usan los mensajes por defecto de [NetworkException]
/// y [QueryException].
Future<Map<String, dynamic>> callRpc(
  Future<Map<String, dynamic>> Function() action, {
  String? networkMessage,
  String? authMessage,
}) async {
  try {
    return await action();
  } on TimeoutException {
    throw networkMessage != null
        ? NetworkException(networkMessage)
        : const NetworkException();
  } on SocketException {
    throw networkMessage != null
        ? NetworkException(networkMessage)
        : const NetworkException();
  } on http.ClientException {
    throw networkMessage != null
        ? NetworkException(networkMessage)
        : const NetworkException();
  } on supabase.PostgrestException {
    throw authMessage != null
        ? QueryException(authMessage)
        : const QueryException('No pudimos completar la acción. Intenta de nuevo.');
  } on supabase.AuthException {
    throw const QueryException(
      'No pudimos completar la acción. Cierra y abre la app de nuevo.',
    );
  }
}
```

**Nota:** `NetworkException` y `QueryException` están en `lib/core/errors/app_exception.dart`.
Si sus constructores no aceptan un mensaje personalizado posicional, verificar la firma
actual y adaptar: si solo tienen `const` sin parámetros, eliminar la personalización
de mensajes del helper y usar los defaults.

### Validación

- `flutter analyze` → No issues.

---

## Corrección C3-03 — Reemplazar _rateLimitMessage local con formatRateLimitMessage

**Hallazgo:** H-03 (uso del nuevo helper)
**Archivos afectados:**
- `lib/features/leaks/data/leak_community_repository.dart`
- `lib/features/leaks/data/leak_report_repository.dart`
- `lib/features/water/data/water_event_repository.dart`

### Cambio en cada archivo

**Paso 1:** Añadir import al top del archivo:
```dart
import '../../../core/utils/rate_limit.dart';
// (ajustar la ruta relativa según la ubicación del archivo)
```

Para `leak_community_repository.dart` y `leak_report_repository.dart`:
```dart
import '../../../core/utils/rate_limit.dart';
```

Para `water_event_repository.dart`:
```dart
import '../../../core/utils/rate_limit.dart';
```

**Paso 2:** Eliminar la definición privada de `_rateLimitMessage` en cada archivo
(el método privado completo).

**Paso 3:** Reemplazar cada llamada `_rateLimitMessage(data)` por
`formatRateLimitMessage(data, defaultMessage: '...')` usando el mensaje por defecto
que tenía cada archivo:

- `leak_community_repository.dart`: `defaultMessage: 'Has alcanzado el límite de acciones por hora.'`
- `leak_report_repository.dart`: `defaultMessage: 'Has alcanzado el límite de reportes por hora.'`
- `water_event_repository.dart`: `defaultMessage: 'Has alcanzado el límite de eventos de agua por hora.'`

### Validación

- `flutter analyze` → No issues.
- `flutter test` → En verde.

---

## Corrección C3-04 — Reemplazar _rpc local con callRpc

**Hallazgo:** H-04 (uso del nuevo helper)
**Archivos afectados:**
- `lib/features/leaks/data/leak_community_repository.dart`
- `lib/features/water/data/water_event_repository.dart`
- `lib/features/notifications/data/notification_repository.dart`

### Cambio en cada archivo

**Paso 1:** Añadir import:
```dart
import '../../../core/utils/rpc_helper.dart';
// (ajustar ruta relativa)
```

**Paso 2:** Eliminar el método privado `_rpc` de cada clase.

**Paso 3:** Reemplazar cada llamada `_rpc(() => ...)` por `callRpc(() => ...)`.

Los métodos que usaban `_rpc` son:
- En `leak_community_repository.dart`: `reportDetail()`, `validateLeak()`, `confirmResolution()`.
- En `water_event_repository.dart`: `register()`, `validate()`, `detail()`.
- En `notification_repository.dart`: `savePreferences()`, `registerToken()`, `unregisterToken()`.

**Nota:** Verificar que en `water_event_repository.dart` la función top-level `_rpc`
(no es método de clase) también se elimina. Si hay imports de `dart:async`, `dart:io`,
`package:http/http.dart` o `package:supabase_flutter` que solo existían por el `_rpc`
local y ya no son necesarios, eliminarlos también; pero verifica que no los uses en
otros métodos del mismo archivo antes de eliminarlos.

### Validación

- `flutter analyze` → No issues (no debe quedar ningún import sin usar).
- `flutter test` → En verde.

---

## Corrección C3-05 — Extraer _buildQueryParams en map_providers.dart

**Hallazgo:** H-06
**Archivo:** `lib/features/map/presentation/map_providers.dart`

### Problema

`mapReportsProvider` y `listReportsProvider` tienen un bloque `switch` idéntico
que construye `status`, `sectorId` y `orderBy` a partir de `filterState.filterType`.
La única diferencia es que uno pasa bounds y el otro no.

### Cambio exacto

Extraer una función privada (fuera de los providers, a nivel de archivo):

```dart
({String? status, String? sectorId, String orderBy}) _buildFilterParams(
  MapFilterState filterState,
) {
  String? status;
  String? sectorId;
  String orderBy = 'recent';

  switch (filterState.filterType) {
    case MapFilterType.all:
      status = null;
      orderBy = 'recent';
    case MapFilterType.active:
      status = 'ACTIVE';
      orderBy = 'recent';
    case MapFilterType.resolved:
      status = 'RESOLVED';
      orderBy = 'recent';
    case MapFilterType.recent:
      status = null;
      orderBy = 'recent';
    case MapFilterType.mostValidated:
      status = null;
      orderBy = 'validated';
    case MapFilterType.mySector:
      sectorId = filterState.selectedSectorId;
  }

  return (status: status, sectorId: sectorId, orderBy: orderBy);
}
```

Reemplazar los dos bloques switch en `mapReportsProvider` y `listReportsProvider` por:

```dart
final params = _buildFilterParams(filterState);
if (filterState.filterType == MapFilterType.mySector &&
    params.sectorId == null) {
  return const <LeakSummary>[];
}
```

Y en la llamada a `repository.mapReports(...)`:
```dart
return repository.mapReports(
  status: params.status,
  sectorId: params.sectorId,
  // mapReportsProvider pasa bounds; listReportsProvider los pasa null:
  minLat: filterState.minLat,   // o null según el provider
  ...
  orderBy: params.orderBy,
  limit: 100,
);
```

### Validación

- `flutter test` → En verde (especialmente los tests de map_screen_test.dart).
- `flutter analyze` → No issues.

---

## Corrección C3-06 — Unificar navegación a LeakReportScreen

**Hallazgo:** H-07
**Archivos:** `lib/app/router/app_shell.dart`, `lib/features/home/presentation/home_screen.dart`

### Problema

`AppShell._openReportFlow()` y `HomeScreen._openReport()` tienen lógica de
post-retorno casi idéntica pero con una diferencia: `AppShell` invalida
`mapReportsProvider` y `HomeScreen` no. El mapa queda desactualizado si se reporta
desde Home.

### Cambio exacto

**Paso 1:** En `HomeScreen._openReport()`, añadir la invalidación de `mapReportsProvider`
que falta:

```dart
Future<void> _openReport(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  container.invalidate(leakReportProvider);
  final created = await Navigator.of(context).push<bool>(...);
  if (created == true) {
    container.invalidate(recentLeaksProvider);
    container.invalidate(communitySummaryProvider);
    container.invalidate(latestActivityProvider);
    container.invalidate(mapReportsProvider);   // <-- añadir esta línea
  }
}
```

Verificar que `mapReportsProvider` está importado en `home_screen.dart`. Si no:
```dart
import '../../map/presentation/map_providers.dart';
```

**Paso 2 (opcional, post-beta):** Consolidar ambos métodos en una función compartida.
Para esta fase, el paso 1 es suficiente para eliminar la inconsistencia.

### Validación

- `flutter analyze` → No issues.
- `flutter test` → En verde.

---

## Checklist de finalización de Fase 3

- [ ] C3-01: `lib/core/utils/rate_limit.dart` creado con `formatRateLimitMessage`.
- [ ] C3-02: `lib/core/utils/rpc_helper.dart` creado con `callRpc`.
- [ ] C3-03: Los 3 repositorios usan `formatRateLimitMessage`, sus copias locales eliminadas.
- [ ] C3-04: Los 4 repositorios usan `callRpc`, sus copias locales eliminadas.
- [ ] C3-05: `_buildFilterParams` extraído, switch duplicado eliminado de map_providers.dart.
- [ ] C3-06: `mapReportsProvider` invalidado también desde `HomeScreen._openReport()`.
- [ ] `flutter analyze` → No issues (sin imports sin usar).
- [ ] `flutter test` → Todos en verde.
- [ ] Commit: `fix(quality): fase 3 — eliminar duplicación en repos y providers`

---

## PROMPT PARA EL AGENTE DE CODIFICACIÓN

```
Eres un agente de codificación trabajando en Gota v0.2 (Flutter · Riverpod 3 · Supabase).
Rama de trabajo: fix/map-r5-r6. Las Fases 1 y 2 ya fueron aplicadas.

Tu tarea es aplicar refactors de mantenibilidad. NO cambies comportamiento visible.
NO introduzcas nuevas dependencias. Respeta el orden indicado.

Antes de empezar: ejecuta `flutter test` y confirma baseline verde.

PASO 1 (C3-01): Crear lib/core/utils/rate_limit.dart
Función pública: formatRateLimitMessage(Map<String,dynamic> data, {String defaultMessage})
Cuerpo idéntico al de _rateLimitMessage existente en los repositorios, parametrizando
el mensaje por defecto. Ver especificación en FASE_3_MANTENIBILIDAD_PROMPT.md.

PASO 2 (C3-02): Crear lib/core/utils/rpc_helper.dart
Función pública: callRpc(Future<Map<String,dynamic>> Function() action, {...})
Cuerpo del try/catch idéntico al _rpc privado existente en los repositorios.
Ver especificación en FASE_3_MANTENIBILIDAD_PROMPT.md.
flutter analyze después.

PASO 3 (C3-03): En los 3 repositorios con _rateLimitMessage local:
  lib/features/leaks/data/leak_community_repository.dart
  lib/features/leaks/data/leak_report_repository.dart
  lib/features/water/data/water_event_repository.dart
Añadir import de rate_limit.dart, eliminar el método privado, reemplazar cada llamada
con formatRateLimitMessage(data, defaultMessage: '<mensaje original>').
flutter test después.

PASO 4 (C3-04): En los repositorios con _rpc local:
  lib/features/leaks/data/leak_community_repository.dart
  lib/features/water/data/water_event_repository.dart
  lib/features/notifications/data/notification_repository.dart
Añadir import de rpc_helper.dart, eliminar el método/función privada, reemplazar
cada llamada _rpc(() => ...) con callRpc(() => ...).
Eliminar imports que queden sin usar (dart:async, dart:io, http, supabase).
flutter analyze y flutter test después.

PASO 5 (C3-05): En lib/features/map/presentation/map_providers.dart
Extraer función privada _buildFilterParams(MapFilterState) que devuelve los
parámetros del switch. Usarla en mapReportsProvider y listReportsProvider.
flutter test después.

PASO 6 (C3-06): En lib/features/home/presentation/home_screen.dart
En _openReport(), añadir container.invalidate(mapReportsProvider) junto a las
otras invalidaciones post-creación.
Verificar import de map_providers.dart.
flutter analyze y flutter test después.

Al terminar:
1. `flutter analyze` → No issues found.
2. `flutter test` → Todos en verde.
3. Commit: `fix(quality): fase 3 — eliminar duplicación en repos y providers`
```
