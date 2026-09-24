# FASE 2 — Estabilidad (P2 urgentes)

**Prerequisito:** Fase 1 completada. `flutter test` en verde.
**Hallazgos corregidos:** H-05, H-08, H-12
**Commit al terminar:** `fix(quality): fase 2 — estabilidad riverpod y maplibre`

---

## Corrección C2-01 — Eliminar uso de API privada copyWithPrevious

**Hallazgo:** H-05
**Archivo:** `lib/features/notifications/presentation/notification_providers.dart`
**Clase:** `NotificationPreferencesController`
**Método:** `_save()`

### Problema

El método `_save()` usa `copyWithPrevious` con `// ignore: invalid_use_of_internal_member`.
Esta es una API privada de Riverpod que puede romperse sin aviso en upgrades.

El objetivo de `copyWithPrevious` en ese contexto es preservar el dato anterior en la
UI mientras se guarda, mostrando un spinner de "refreshing" sin perder el dato visible.

### Cambio exacto

Reemplazar el uso de `copyWithPrevious` por preservación manual del estado previo.

Busca en `_save()` la línea que contiene `copyWithPrevious`:

```dart
// ANTES (línea aproximada 69):
state = const AsyncValue<NotificationPreferences?>.loading()
    .copyWithPrevious(previousState, isRefresh: true); // ignore: invalid_use_of_internal_member
```

Reemplazar por:

```dart
// DESPUÉS:
state = previousState.whenData((data) => data).whenOrNull(
      data: (data) => AsyncValue<NotificationPreferences?>.loading(),
    ) ?? const AsyncValue<NotificationPreferences?>.loading();
```

Pero esto es innecesariamente complejo. La alternativa más simple y directa es guardar
explícitamente el valor previo conocido y usarlo para restaurar en caso de error,
sin intentar mantener el "refreshing" visual con dato anterior:

```dart
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
  state = const AsyncValue<NotificationPreferences?>.loading();  // <-- simplificado
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
    state = previousState.hasValue
        ? previousState
        : AsyncValue.error(error, stackTrace);
  }
}
```

La única diferencia visible para el usuario es que durante el guardado se muestra
un spinner puro en lugar de spinner-con-dato-previo. Esto es behavior-preserving
en cuanto a datos: el dato anterior se restaura si falla.

Eliminar también la línea de import si `invalid_use_of_internal_member` era el único
uso que requería el suppress. Verificar que no haya otros `ignore:` relacionados.

### Validación

- Eliminar la línea `// ignore: invalid_use_of_internal_member`.
- `flutter analyze` → No issues.
- `flutter test` → En verde.

---

## Corrección C2-02 — Remover listener onCircleTapped en dispose()

**Hallazgo:** H-08
**Archivo:** `lib/features/map/presentation/widgets/gota_map_view.dart`
**Clase:** `_MapLibreMapViewState`

### Problema

`_onMapCreated` añade un listener con `controller.onCircleTapped.add(callback)`.
`dispose()` nunca llama a `remove()` sobre ese listener. Si el controlador nativo de
MapLibre retiene la lista de listeners más allá del ciclo de vida del widget, el
callback puede dispararse sobre un objeto dispuesto.

### Cambio exacto

**Paso 1:** Declarar una variable para guardar la referencia al callback:

En la clase `_MapLibreMapViewState`, añadir el campo:
```dart
late final void Function(Circle) _onCircleTappedCallback;
```

**Paso 2:** En `_onMapCreated`, en lugar de pasar un lambda inline, asignar primero
el callback a la variable y luego pasarlo:

```dart
void _onMapCreated(MapLibreMapController controller) {
  _controller = controller;
  _mapCreated = false;
  _styleLoaded = false;
  _onCircleTappedCallback = (circle) {    // <-- asignar a la variable
    final leak = _circleToLeak[circle];
    if (leak != null) {
      widget.onMarkerTapped(leak);
    }
  };
  controller.onCircleTapped.add(_onCircleTappedCallback);  // <-- usar variable
  _mapCreated = true;
}
```

**Paso 3:** En `dispose()`, remover el listener si el controlador existe:

```dart
@override
void dispose() {
  _controller?.onCircleTapped.remove(_onCircleTappedCallback);  // <-- añadir
  _mapCreated = false;
  _styleLoaded = false;
  super.dispose();
}
```

**Nota:** Si `_onMapCreated` nunca se llama (el mapa falló al crearse), `_onCircleTappedCallback`
puede no estar inicializado. Para evitar este caso, inicializar el campo con un noop:

```dart
void Function(Circle) _onCircleTappedCallback = (_) {};
```

### Validación

- `flutter analyze` → No issues.
- `flutter test` → En verde.

---

## Corrección C2-03 — Estrechar catch en sectorWaterStatusProvider

**Hallazgo:** H-12
**Archivo:** `lib/features/home/presentation/community_summary_providers.dart`
**Provider:** `sectorWaterStatusProvider`

### Problema

El provider usa `catch (_)` que captura absolutamente todo, incluyendo errores de
programación como `NullPointerException` o `AssertionError`. Un bug en código Flutter
quedaría completamente invisible, mostrando "Sin información" como si fuera una
respuesta vacía del backend.

### Cambio exacto

Busca en `community_summary_providers.dart` el bloque:

```dart
final sectorWaterStatusProvider =
    FutureProvider<WaterEventSummary?>((ref) async {
  final prefs = await ref.watch(notificationPreferencesProvider.future);
  try {
    return await ref
        .watch(waterEventRepositoryProvider)
        .latestEvent(sectorId: prefs?.preferredSectorId);
  } catch (_) {
    return null;
  }
});
```

Reemplazar por:

```dart
final sectorWaterStatusProvider =
    FutureProvider<WaterEventSummary?>((ref) async {
  final prefs = await ref.watch(notificationPreferencesProvider.future);
  try {
    return await ref
        .watch(waterEventRepositoryProvider)
        .latestEvent(sectorId: prefs?.preferredSectorId);
  } on AppException {
    return null;
  } on TimeoutException {
    return null;
  } on SocketException {
    return null;
  }
});
```

Verifica que los imports necesarios existan en el archivo:
```dart
import 'dart:async';      // TimeoutException
import 'dart:io';         // SocketException
import '../../../core/errors/app_exception.dart';  // AppException
```

Los errores de programación ahora propagarán y serán visibles como errores reales
en lugar de silenciarse como "sin datos".

### Validación

- `flutter analyze` → No issues.
- `flutter test` → En verde.

---

## Checklist de finalización de Fase 2

- [ ] C2-01 aplicado: `copyWithPrevious` eliminado de `_save()`.
- [ ] C2-02 aplicado: listener `onCircleTapped` removido en `dispose()`.
- [ ] C2-03 aplicado: catch tipado en `sectorWaterStatusProvider`.
- [ ] `flutter analyze` → No issues.
- [ ] `flutter test` → Todos en verde.
- [ ] Commit: `fix(quality): fase 2 — estabilidad riverpod y maplibre`

---

## PROMPT PARA EL AGENTE DE CODIFICACIÓN

```
Eres un agente de codificación trabajando en Gota v0.2 (Flutter · Riverpod 3 · Supabase).
Rama de trabajo: fix/map-r5-r6. La Fase 1 ya fue aplicada.

Tu tarea es aplicar 3 correcciones de estabilidad. NO cambies comportamiento visible,
UX, reglas de negocio ni APIs. NO introduzcas nuevas dependencias.

Antes de empezar: ejecuta `flutter test` y confirma que todos pasan.

CORRECCIÓN 1 (C2-01) — notification_providers.dart
Clase: NotificationPreferencesController, método _save()
Eliminar la línea con copyWithPrevious y su `// ignore: invalid_use_of_internal_member`.
Reemplazarla por: `state = const AsyncValue<NotificationPreferences?>.loading();`
(La restauración del estado previo en el catch ya existe correctamente, no la toques.)
Ejecuta flutter analyze. Debe desaparecer el ignore.

CORRECCIÓN 2 (C2-02) — gota_map_view.dart
Clase: _MapLibreMapViewState
1. Añadir campo: `void Function(Circle) _onCircleTappedCallback = (_) {};`
2. En _onMapCreated: extraer el lambda inline a _onCircleTappedCallback antes del .add().
3. En dispose(): añadir `_controller?.onCircleTapped.remove(_onCircleTappedCallback);`
   antes de `_mapCreated = false`.
Ejecuta flutter test después.

CORRECCIÓN 3 (C2-03) — community_summary_providers.dart
Provider: sectorWaterStatusProvider
Reemplazar `catch (_) { return null; }` por tres catch tipados:
  on AppException { return null; }
  on TimeoutException { return null; }
  on SocketException { return null; }
Añadir imports necesarios: dart:async, dart:io, app_exception.dart.
Ejecuta flutter analyze y flutter test después.

Al terminar:
1. `flutter analyze` → No issues found.
2. `flutter test` → Todos en verde.
3. Commit: `fix(quality): fase 2 — estabilidad riverpod y maplibre`
```
