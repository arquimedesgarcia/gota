# PROMPT 6 — DEUDA DEL PROMPT 4 · QUITAR LA API `@internal` DEL GUARDADO DE PREFERENCIAS

**Clasificación:** DEUDA TÉCNICA con riesgo de regresión silenciosa (no es BLOCKER de piloto; sí es
BETA FIX de mantenibilidad) · **Modelo sugerido:** Sonnet · **Turnos:** 25-35
**Base:** `main` @ `125b0e4` — los cambios de la tanda 1 (prompts 1 y 4) **ya están commiteados** en `main`
(la base `bbef6ae` + «sin commitear» citada antes quedó obsoleta). **Rama de trabajo:** la que asigne el
orquestador (no commitear, no cambiar de rama).

> Este prompt es autocontenido: no requiere leer el plan ni el informe de diagnóstico.

## Objetivo

Eliminar el uso de una API **interna** de Riverpod en el guardado de preferencias de notificación
(`copyWithPrevious` con `// ignore: invalid_use_of_internal_member`) **sin** perder ninguna de estas
tres propiedades, hoy garantizadas por esa API:

1. el sector de interés **no desaparece** de Ajustes mientras la app guarda;
2. los tres llamadores **se liberan** siempre (pop en éxito, SnackBar con `saveError` en fallo), sin
   quedarse con su spinner o su control deshabilitado para siempre;
3. si se guarda **antes** de que termine la carga inicial, no se escribe nada y se publica el error
   tipado (guard del prompt 4).

## Causa raíz aceptada (evidencia verificada por el orquestador)

- `copyWithPrevious` está anotado `@internal` en la versión instalada:
  `riverpod-3.4.3/lib/src/core/async_value.dart:629` (declaración abstracta), `:714` (`AsyncData`),
  `:777` (`AsyncLoading`), `:865` (`AsyncError`). No hay vía pública al mismo efecto en esa versión.
- Se usa con supresor de lint en `lib/features/notifications/presentation/notification_providers.dart:68-69`:
  ```dart
  state = const AsyncValue<NotificationPreferences?>.loading()
      .copyWithPrevious(previousState, isRefresh: true); // ignore: invalid_use_of_internal_member
  ```
- **Por qué no es cosmético:** una API interna puede cambiar de semántica entre minors sin romper la
  compilación (la firma puede sobrevivir); y el `// ignore` tapa cualquier uso indebido nuevo en ese
  archivo. El gate de piloto no lo bloquea; el mantenimiento sí.

### Restricción dura que decide el diseño (también verificada)

Los llamadores **solo reaccionan a un estado que cambia de verdad**; Riverpod no notifica cuando el
estado nuevo compara igual al anterior:

- `sector_selection_screen.dart:34-52`: `if (!_saving || next is AsyncLoading) return;` y `_selectSector`
  pone `_saving = true` (`:25-30`).
- `settings_screen.dart:240-257` (`_WaterNotificationsCard`): mismo patrón con `_toggling`.
- `settings_screen.dart:194-211` (`_confirmClear`) **no** tiene ese patrón: hace
  `await controller.clearSector()` y después lee `controller.saveError`. *(El prompt 4, C1, afirma que
  `_confirmClear` usa `next is AsyncLoading`: es incorrecto en el baseline. Son dos listeners, no tres.)*
- En el fallo con valor previo, `_save()` reasigna el estado previo
  (`notification_providers.dart:85-87`: `state = previousState.hasValue ? previousState : AsyncValue.error(...)`).

**Consecuencia:** un diseño del tipo «no tocar `state` durante el guardado y usar solo un flag
`_isSaving`» **deja colgada la UI**: en el fallo con valor previo se reasigna el mismo `previousState`
→ estado igual → sin notificación → `_saving`/`_toggling` quedan en `true` para siempre y no hay
SnackBar ni pop. Y en el éxito, si el valor guardado es **igual** al previo (guardar el mismo sector),
`state = AsyncValue.data(saved)` tampoco notifica. Cualquier solución debe cubrir **esos dos casos
concretos**, no solo el camino feliz con valor distinto.

## Archivos que SÍ se pueden tocar

- `lib/features/notifications/presentation/notification_providers.dart`
- `lib/features/notifications/presentation/settings_screen.dart`
- `lib/features/notifications/presentation/sector_selection_screen.dart` (solo si la opción elegida lo
  exige; ver C2)
- `test/features/notifications/notifications_test.dart` (agregar casos; se permite **un** archivo de test
  nuevo si el diseño lo pide)

## Archivos PROHIBIDOS

`supabase/**` (RPC de preferencias, RLS, migraciones), `notification_repository.dart`,
`push_*`, `NotificationInboxController` y la bandeja, el resto de `lib/`, `main`, y los worktrees
`.claude/worktrees/agent-a429749783d7a8538`, `tanda1-fotos`, `tanda1-mapa`, `tanda1-sector`,
`tanda2-continuar`.

## Contrato explícito

**C1 · Cero API interna.** Al terminar,
`grep -rn "copyWithPrevious\|invalid_use_of_internal_member" lib/` debe devolver **0 líneas**, y
`flutter analyze` debe estar limpio **sin ningún `// ignore` nuevo**. Pegá la salida real del `grep`.

**C2 · Transición observable garantizada en los cuatro caminos.** Toda operación de guardado debe
producir al menos un cambio de estado que notifique a los listeners, en: (a) éxito con valor distinto,
(b) éxito con valor **igual** al previo, (c) fallo con valor previo, (d) fallo sin valor previo.
Elegí **una** de estas dos vías y justificá la elección en el reporte:

- **Opción A — proveedor separado del ciclo de guardado (recomendada).** El provider de preferencias se
  queda con la **carga** (`AsyncValue<NotificationPreferences?>`), y el guardado publica en un estado
  propio (p. ej. un `Notifier<AsyncValue<void>>` que pasa por `loading` y termina en `data`/`error`), que
  por construcción **siempre** cambia en cada guardado. Los dos listeners migran a escuchar ese estado;
  `saveError` sigue leyéndose del controller (no cambies su tipo ni su nombre público).
  *Condición para descartarla:* si migrar un listener obliga a tocar un archivo PROHIBIDO o a cambiar la
  semántica observable de un llamador → reportá `BLOCKER`, no la fuerces.
- **Opción B — mantener la transición de carga en el provider de preferencias, sin API interna.**
  Emitir `AsyncLoading` **público** (sin `copyWithPrevious`) y resolver el "no ocultar el valor" en la
  UI con mecanismos públicos (`skipLoadingOnReload` en `when`, o conservar el último valor en el widget).
  *Condición para descartarla:* si al hacerlo el sector vuelve a desaparecer en algún frame durante el
  guardado, o el switch de agua parpadea a apagado → descartala (es exactamente el síntoma que el
  prompt 4 corrigió) y pasá a la opción A.

**C3 · El valor visible no se oculta.** Durante un guardado normal (con valor previo) el nombre del
sector sigue en pantalla y no aparece `LoadingView`; el switch de agua no parpadea a apagado.

**C4 · Semántica de los llamadores intacta.** Éxito → la pantalla de selección hace `pop`; fallo →
SnackBar con el mensaje de `saveError` (tipado `AppException` incluido) y el control vuelve a
habilitarse; el control queda deshabilitado **mientras** dura el guardado (hoy vía
`saving = prefs.isLoading` / `_toggling`; si tu diseño cambia de dónde sale ese flag, el efecto debe
seguir siendo el mismo y hay que decirlo con `archivo:línea`).

**C5 · El guard del prompt 4 no se toca.** Sigue bloqueando **cualquier** guardado sin valor previo
(`!clearSector && !previousState.hasValue`), publica `AsyncValue.error(_saveError!, StackTrace.current)`
y libera a los llamadores. `clearSector`, la regla 0..1 sector, el `catch` que revierte y la invalidación
en `notification_providers.dart:80` se mantienen.

## Criterios de aceptación

1. `grep` de C1 vacío y `flutter analyze` limpio (salida real pegada).
2. `flutter test` en verde con **todos** los tests existentes del grupo
   `NotificationPreferencesController` sin cambios de expectativa.
3. Los cuatro caminos de C2 quedan cubiertos por tests que **fallan** al revertir su fix (ver abajo).
4. Ni un archivo PROHIBIDO modificado (lo verifica el orquestador con `git status`).

## Tests obligatorios (mutation control obligatorio)

En `test/features/notifications/notifications_test.dart`, grupo `NotificationPreferencesController`
(ya existen `_FakeNotificationRepository` con `savedPreferences`/`preferencesError`, `_BlockedSaveRepository`
y los cuatro tests de la tanda 1):

- **`guardar dos veces el mismo sector sigue notificando a los llamadores`** — el repo falso devuelve
  exactamente el valor previo; el listener debe dispararse igual (afirmar el cambio de estado observado,
  no solo el valor final). *Mutación: si el camino de éxito no publica un estado propio, este test falla.*
- **`el fallo de guardado con valor previo notifica a los llamadores`** — `preferencesError` inyectado y
  valor previo presente; afirmar que el listener observó un estado nuevo (`!=` el previo) y que
  `saveError` quedó expuesto. *Mutación: un `return` sin cambio de estado, o reasignar el mismo
  `previousState`, hace fallar este test.*
- **No romper ni reescribir**: `guardar antes de que la carga complete no borra el sector`,
  `el guard publica el estado y libera a los llamadores`, `el guardado conserva el valor previo en el
  estado`, `el sector sigue visible mientras se guarda`.
- **Evidencia de C1** en el reporte: salida real del `grep` y del `analyze`.

## Fuera de alcance

Cambiar el modelo `NotificationPreferences`, la RPC de preferencias, el contrato de 0..1 sector, el
`NotificationInboxController`, la bandeja de notificaciones, `notification_repository.dart`, el orden de
navegación de Ajustes, o el guard del prompt 4. Tampoco actualizar la versión de Riverpod (queda fuera:
cambiar `pubspec.yaml` en la misma tanda que la corrección impide atribuir cualquier regresión).

## Rollback

Revertir los hunks de `_save()` (y de los listeners, si la opción A migró el `ref.listen`) y retirar los
tests nuevos. El estado de partida es el de la tanda 1 verificado, que ya cumple el síntoma visual con la
API interna: el rollback no deja el producto peor que antes, solo con la deuda.

## Evidencia a devolver

`STATUS / CAMBIOS(archivo:línea) / OPCIÓN ELEGIDA Y POR QUÉ / ANALYZE / TESTS(salida) / GREP C1 /
ARCHIVOS / COMMIT(ninguno) / BLOCKER / NOT VERIFIED`
