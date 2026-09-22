# Diagnóstico técnico pre-implementación — Gota v0.2

**Commit auditado:** `295f77d8ab486221d6084fd098ed8f6c68748520`  
**Rama:** `fix/map-r5-r6`  
**Fecha:** 2026-09-22  
**Auditor:** Claude Sonnet 4.6 (solo lectura de código)

> **Declaración de integridad:** Esta sesión NO modificó el repositorio. Se leyeron archivos en disco
> tal como existen en HEAD. No se ejecutó ningún comando destructivo, no se hizo checkout,
> staging, commit, stash ni restauración.
>
> **`git status --short` INICIAL:** *(salida vacía — árbol limpio)*  
> **`git status --short` FINAL:** `?? docs/DIAGNOSTICO_PRE_IMPLEMENTACION_2026-09-22.md` — el único
> cambio en el árbol es este informe (untracked). Ningún archivo de código, migración o test fue
> modificado; no hubo stage ni commit.

---

## Hallazgo 1 — MAPA: saltos/refresco durante pan/zoom

### Finding
"Sin fugas para mostrar" aparece brevemente durante pan o zoom y el mapa pierde fluidez.

### Archivo(s)
- `lib/features/map/presentation/map_screen.dart:73-99`
- `lib/features/map/presentation/map_providers.dart:45-71`
- `lib/features/map/presentation/widgets/gota_map_view.dart:173-188`

### Causa raíz — CONFIRMADO
El árbol de widgets desmonta físicamente `GotaMapView` cada vez que `mapReportsProvider` transiciona a `data([])` (lista vacía). Esto ocurre cuando el viewport del mapa se desplaza sobre una zona con cero reportes, lo que es posible durante cualquier pan o zoom. El ciclo completo es:

1. `onCameraIdle` → `getVisibleRegion()` → `onBoundsChanged(bounds)` → `setBounds(...)` (`gota_map_view.dart:173-188`)
2. `mapFilterProvider` cambia de estado → `mapReportsProvider` re-ejecuta (`map_providers.dart:97`)
3. Si la consulta devuelve `[]` → `MapScreen.build()` entra al bloque `if (reports.isEmpty)` (`map_screen.dart:87-99`):
   ```dart
   // map_screen.dart:87-99
   if (reports.isEmpty) {
     WidgetsBinding.instance.addPostFrameCallback((_) {
       ref.read(mapFilterProvider.notifier).clearBounds();
     });
     return _MapEmptyView(filterState: filterState);  // ← mapa desmontado aquí
   }
   ```
4. `_MapEmptyView` reemplaza `_MapViewContent` (diferente rama del `switch`), **desmontando `_MapLibreMapView`** y destruyendo el contexto OpenGL/MapLibre.
5. `clearBounds()` dispara una nueva consulta sin bbox → devuelve datos → mapa se vuelve a montar.

`skipLoadingOnReload: true` (línea 74) **no ayuda** aquí porque el estado `data([])` no es un estado de carga: es un estado de datos vacíos. `skipLoadingOnReload` solo suprime `AsyncLoading`, nunca `data(empty)`.

Sin debounce en `setBounds`: cada idle de cámara (incluso durante scroll lento) lanza una nueva consulta. Si alguna de ellas retorna vacía, se activa el desmonte del mapa.

### Evidencia

```
// map_providers.dart:45-50
void setBounds(double minLat, double minLng, double maxLat, double maxLng) {
  final boundsChanged = state.minLat != minLat || ...;
  if (!boundsChanged) return;
  state = state.copyWith(minLat: minLat, ...);
}
```
Cada idle con nuevos bounds actualiza el estado. No hay debounce.

```
// map_screen.dart:73-74  — skipLoadingOnReload solo protege AsyncLoading
child: reportsAsync.when(
  skipLoadingOnReload: true,
  ...
  data: (reports) {
    if (reports.isEmpty) {         // data([]) llega aquí, no al loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(mapFilterProvider.notifier).clearBounds();
      });
      return _MapEmptyView(filterState: filterState);  // mapa desmontado
    }
    return switch (filterState.viewMode) {
      MapViewMode.map => Stack(children: [_MapViewContent(...), ...]),  // mapa montado
      ...
    };
  },
),
```

El `_MapViewContent` y `_MapEmptyView` son ramas mutuamente excluyentes. Flutter desmonta uno y monta el otro, destruyendo el estado interno de MapLibre.

### Corrección mínima propuesta

**Opción A (debounce — menor riesgo):** Añadir un debounce de ~300 ms sobre `onBoundsChanged` en `_MapViewContent` para reducir la tasa de consultas. Esto disminuye la probabilidad de hits vacíos, pero no elimina el problema si el usuario se detiene sobre una zona vacía.

**Opción B (corrección estructural — recomendada):** Mantener el mapa montado cuando los resultados son vacíos mostrando un overlay no intrusivo en lugar de desmontarlo:

```diff
// map_screen.dart — cambio conceptual
- if (reports.isEmpty) {
-   WidgetsBinding.instance.addPostFrameCallback((_) {
-     ref.read(mapFilterProvider.notifier).clearBounds();
-   });
-   return _MapEmptyView(filterState: filterState);
- }
- return switch (filterState.viewMode) {
-   MapViewMode.map => Stack(children: [_MapViewContent(...), ...]),
+ return switch (filterState.viewMode) {
+   MapViewMode.map => Stack(children: [
+     _MapViewContent(leaks: reports, ...),   // siempre montado en modo mapa
+     if (reports.isEmpty) const _MapEmptyOverlay(),  // overlay sobre el mapa
+     ...
+   ]),
```

El `_MapEmptyOverlay` reemplaza a `_MapEmptyView` solo como banner superpuesto; no desmonta el mapa. La cláusula `clearBounds` se elimina (ya no es necesaria si el mapa sigue montado y el usuario puede seguir desplazándose).

Para el modo lista, la vista de lista puede continuar desmontándose con el estado vacío sin problema.

### Riesgo de regresión
- Opción A: bajo. Solo introduce latencia en la actualización de bounds.
- Opción B: medio. La separación lógica entre "mapa vacío" y "lista vacía" requiere validar que el mapa OpenGL no tenga fugas de memoria cuando `leaks` es lista vacía durante períodos prolongados. El overlay necesita tests de widget.

### Prueba para verificar la corrección
1. Abrir el mapa con reportes visibles.
2. Desplazarse rápidamente hacia el mar o hacia una zona sin reportes.
3. Verificar que NO aparece "Sin fugas para mostrar" durante el movimiento ni al detenerse.
4. Verificar que al volver a desplazar hacia una zona con reportes, los markers aparecen correctamente.
5. Verificar que el filtro "Mi sector" y los demás filtros siguen funcionando.

### Clasificación
`BETA FIX`

---

## Hallazgo 2 — CIERRES AL TOMAR/SELECCIONAR FOTO

### Finding
La app se cierra ocasionalmente al tomar una foto con la cámara o al seleccionarla desde la galería.

### Archivo(s)
- `lib/features/leaks/data/photo_service.dart:31-91`
- `lib/features/leaks/data/photo_limits.dart:1-49`
- `lib/features/leaks/presentation/leak_report_controller.dart:286-316`
- `android/app/src/main/AndroidManifest.xml`

### Causa raíz — CONFIRMADO (parcialmente) + HIPÓTESIS

**CONFIRMADO:** La ruta de salida del archivo comprimido se construye como `'${path}_gota.jpg'` (`photo_service.dart:61`):

```dart
// photo_service.dart:61
final compressedPath = '${path}_gota.jpg';
```

Para imágenes de galería en Android 10+, el `path` devuelto por `image_picker` puede apuntar a un archivo en la caché temporal del sistema (p. ej. `/data/user/0/com.gota/.../image_picker_...jpg`). El archivo comprimido se intenta escribir en la misma ruta con sufijo, lo que normalmente funciona. Sin embargo, para imágenes de galería seleccionadas por content URI (Android 10 scoped storage), `image_picker` puede devolver un path en `/data/user/0/.../image_picker_0.jpg` que es borrado por el sistema antes de que `FlutterImageCompress` termine de leer el original — condición de carrera con el recolector de archivos temporales del SO.

**HIPÓTESIS:** `FlutterImageCompress.compressAndGetFile` puede lanzar errores nativos (JNI) no capturados como `Exception` sino como `Error` en Dart. Los `Error` (a diferencia de `Exception`) no son atrapados por `on Exception` en `addPhoto` (`leak_report_controller.dart:308-314`). Un `Error` no capturado en un `Future` que no fue `await`-ado puede convertirse en una excepción no controlada a nivel de zona y cerrar la app.

**HIPÓTESIS (Android específico):** El `AndroidManifest.xml` no tiene declaración explícita de `FileProvider` para la cámara (`android/app/src/main/AndroidManifest.xml` revisado). Las versiones recientes de `image_picker_android` (0.8.x) incluyen el `FileProvider` en su propio manifiesto que se fusiona con el del proyecto durante el build. Con `image_picker_android:0.8.13+23` (versión en caché), este merge debería ocurrir automáticamente. **Sin confirmación en el build output** — si la fusión fallara o el `FileProvider` estuviera mal configurado, las fotos de cámara en Android 7+ fallarían con una excepción nativa que puede causar el cierre.

**Regla de negocio — foto limits (CONFIRMADO):**

| Parámetro | Valor actual (código) | Valor deseado (spec) |
|---|---|---|
| Máximo de fotos | `kReportPhotoMaxCount = 3` (`photo_limits.dart:11`) | **2** |
| Calidad picker | `imageQuality: 80` (`photo_service.dart:36`) | Estándar (OK) |
| Calidad comprimir | `quality: 82` (`photo_service.dart:66`) | Estándar (OK) |
| Max resolución | `1920×1920` (`photo_service.dart:37-38`) | Sin alta resolución (OK) |

No existe `system_config.photo_limits` en el cliente. El límite es `kReportPhotoMaxCount` en `photo_limits.dart:11` (constante cliente-side). La RPC del servidor también valida (según comentario en `photo_limits.dart:8-10`), pero el cliente expone actualmente 3 slots. Para cambiar a 2, hay que cambiar `kReportPhotoMaxCount = 3` → `kReportPhotoMaxCount = 2` en ese archivo.

### Evidencia

```dart
// photo_service.dart:60-67
final compressedPath = '${path}_gota.jpg';
final compressed = await FlutterImageCompress.compressAndGetFile(
  path,
  compressedPath,
  quality: 82,
  format: CompressFormat.jpeg,
);
if (compressed == null) {
  throw const PhotoValidationException('No pudimos procesar esa foto. Elige otra.');
}
```

```dart
// leak_report_controller.dart:286-316
Future<void> addPhoto({required bool fromCamera}) async {
  ...
  try {
    final photo = await service.pickAndPrepare(fromCamera: fromCamera);
    ...
  } on PhotoPickCanceledException { return; }
  on PhotoValidationException catch (e) { state = ...; }
  on LeakFlowException catch (e) { state = ...; }
  on Exception {  // ← NO atrapa Error ni excepciones nativas JNI
    state = state.copyWith(message: const PhotoValidationException(...).userMessage);
  }
}
```

El catch final usa `on Exception`, que en Dart **no atrapa `Error`** (que es la jerarquía de los errores de Dart como `StateError`, `ArgumentError`, ni excepciones nativas que escalen como `Error`).

### Corrección mínima propuesta

1. **Cambiar el límite de fotos a 2:**
   ```diff
   // photo_limits.dart:11
   - const kReportPhotoMaxCount = 3;
   + const kReportPhotoMaxCount = 2;
   ```

2. **Ampliar el catch para capturar `Object`:**
   ```diff
   // leak_report_controller.dart:308-313
   - on Exception {
   + catch (e) {  // captura Exception, Error y excepciones nativas
     state = state.copyWith(
       message: const PhotoValidationException(
         'No pudimos procesar esa foto. Elige otra.',
       ).userMessage,
     );
   }
   ```

3. **Verificar FileProvider merge en el build** (fora del scope del código en disco — requiere inspección del build output en dispositivo real o revisión del `image_picker_android` plugin manifests).

### Riesgo de regresión
- Cambio de límite: bajo. Solo cambia el contador máximo; no afecta fotos ya subidas.
- Cambio de catch: bajo. Amplía la captura; no puede ocultar nada que antes se veía.
- El cierre nativo (si es FileProvider) requiere verificación en dispositivo.

### Prueba necesaria para verificar la corrección
1. En Android 10+ real: tomar foto con cámara trasera → verificar que no hay crash.
2. En Android 10+ real: seleccionar foto de galería grande (> 5 MB) → verificar compresión OK.
3. Intentar agregar una cuarta foto → verificar que el botón está deshabilitado tras la tercera... **con el límite a 2, tras la segunda**.
4. Forzar error de compresión (archivo inexistente) → verificar que aparece banner de error en lugar de crash.

### Clasificación
`BLOCKER`

---

## Hallazgo 3 — DIRECCIÓN: valores preseleccionados no habilitan Continuar

### Finding
GPS → reverse geocode → municipio/sector aparecen preseleccionados en los dropdowns, pero el botón "Continuar" permanece deshabilitado hasta que el usuario interactúa manualmente con los dropdowns.

### Archivo(s)
- `lib/features/leaks/presentation/leak_report_screen.dart:562-718` (`DataStepView`)
- `lib/features/leaks/presentation/leak_report_controller.dart:182-216` (`_applyMunicipalitySuggestion`)
- `lib/features/leaks/presentation/leak_report_screen.dart:706-708` (condición del botón)

### Causa raíz — CONFIRMADO

El sistema de sugerencias guarda el municipio/sector sugerido en `suggestedMunicipalityId` / `suggestedSectorId` del estado del controlador. Estos valores **nunca se copian al borrador** (`draft.municipalityId` / `draft.sectorId`). El botón "Continuar" solo se habilita cuando `draft.municipalityId != null && draft.sectorId != null`:

```dart
// leak_report_screen.dart:706-708
onPressed: (state.draft.municipalityId != null &&
            state.draft.sectorId != null)
    ? () => controller.goToNext()
    : null,
```

Los dropdowns usan `initialValue: effectiveMunicipalityId` donde `effectiveMunicipalityId = state.draft.municipalityId ?? state.suggestedMunicipalityId`. Cuando el draft es null, `effectiveMunicipalityId` es la sugerencia — visualmente el dropdown aparece con valor preseleccionado:

```dart
// leak_report_screen.dart:572-573, 643-646
final effectiveMunicipalityId =
    state.draft.municipalityId ?? state.suggestedMunicipalityId;
...
DropdownButtonFormField<String>(
  key: ValueKey(effectiveMunicipalityId),
  initialValue: effectiveMunicipalityId,  // ← visual OK
  onChanged: (value) {
    if (value != null) {
      controller.selectMunicipality(value);  // ← solo se llama si el usuario interactúa
    }
  },
),
```

**`DropdownButtonFormField.initialValue` no dispara `onChanged`.** Flutter pre-rellena el widget visualmente pero no llama al callback. Por tanto, `controller.selectMunicipality(...)` nunca se invoca al mostrar la sugerencia. El draft permanece vacío. El botón permanece deshabilitado.

El comentario en `_applyMunicipalitySuggestion` (controller.dart:182) es explícito:  
> _"Nunca modifica `draft.municipalityId` ni `draft.sectorId`: la preselección es solo informativa; el usuario confirma vía dropdown."_

Esta fue la intención de diseño, pero es incorrecta en la práctica: el dropdown pre-muestra el valor pero no confirma nada sin interacción, lo que el usuario percibe como un bug.

El `key: ValueKey(effectiveMunicipalityId)` fuerza la reconstrucción del widget cuando llega la sugerencia, pero tampoco dispara `onChanged` — solo actualiza `initialValue` del nuevo widget reconstruido.

### Evidencia

```dart
// leak_report_controller.dart:199
state = state.copyWith(suggestedMunicipalityId: matched);
// ↑ Guarda como sugerencia, NO como draft

// leak_report_controller.dart:212-213
state = state.copyWith(suggestedSectorId: matchedSector);
// ↑ Ídem para sector
```

```dart
// leak_report_screen.dart:706-708 — solo draft, no suggested
onPressed: (state.draft.municipalityId != null &&
            state.draft.sectorId != null)
    ? () => controller.goToNext()
    : null,
```

### Corrección mínima propuesta

Tratar las sugerencias como selecciones reales al aplicarlas. En `_applyMunicipalitySuggestion`, en lugar de solo guardar en `suggestedMunicipalityId`/`suggestedSectorId`, también escribir en el borrador:

```diff
// leak_report_controller.dart — _applyMunicipalitySuggestion
- state = state.copyWith(suggestedMunicipalityId: matched);
+ state = state.copyWith(
+   suggestedMunicipalityId: matched,
+   draft: state.draft.copyWith(municipalityId: matched, sectorId: null),
+ );
...
- if (matchedSector == null) return;
- state = state.copyWith(suggestedSectorId: matchedSector);
+ if (matchedSector == null) return;
+ state = state.copyWith(
+   suggestedSectorId: matchedSector,
+   draft: state.draft.copyWith(sectorId: matchedSector),
+ );
```

Las flags `isMunicipalitySuggested` / `isSectorSuggested` en la UI siguen siendo correctas para mostrar "Sugerido según ubicación GPS", ya que se calculan a partir de `draft.municipalityId == null` → ahora quedarán `false` (la sugerencia ya es también la selección). Para mantener el indicador visual, cambiar la condición a `draft.municipalityId == suggestedMunicipalityId`:

```diff
// leak_report_screen.dart:574-576
- final isMunicipalitySuggested =
-     state.draft.municipalityId == null &&
-     state.suggestedMunicipalityId != null;
+ final isMunicipalitySuggested =
+     state.draft.municipalityId != null &&
+     state.draft.municipalityId == state.suggestedMunicipalityId;
```

Esto mantiene los dropdowns editables (el usuario puede cambiarlos), habilita "Continuar" con la sugerencia preseleccionada, y conserva el texto "Sugerido según GPS".

### Riesgo de regresión
Bajo. El cambio solo añade escritura al borrador cuando ya se escribe `suggestedMunicipalityId`. No hay efecto en los otros flujos (manual, selección explícita). El sector se reinicia si el municipio se cambia (ya implementado en `selectMunicipality:359-368`).

### Prueba necesaria para verificar la corrección
1. Activar GPS en el flujo de reporte → esperar reverse geocode → verificar que "Continuar" se habilita automáticamente cuando el municipio y sector son reconocidos.
2. Cambiar el municipio manualmente → verificar que el sector se limpia y "Continuar" se deshabilita hasta seleccionar sector.
3. Seleccionar sector explícitamente → verificar que "Continuar" se habilita.
4. Usar ubicación manual (sin GPS) → verificar que "Continuar" permanece deshabilitado (draft vacío, sin sugerencia).

### Clasificación
`BETA FIX`

---

## Hallazgo 4 — SECTOR DE INTERÉS desaparece ocasionalmente

### Finding
El sector de interés del usuario a veces aparece vacío en Ajustes sin que el usuario lo haya borrado.

### Archivo(s)
- `lib/features/notifications/presentation/notification_providers.dart:20-88`
- `lib/features/notifications/presentation/settings_screen.dart:76-213`
- `lib/features/notifications/presentation/sector_selection_screen.dart:25-53`

### Causa raíz — HIPÓTESIS (parcial) + EVIDENCIA INSUFICIENTE

No hay evidencia directa en el código de una pérdida permanente del sector. El código persiste el sector en Supabase vía RPC y lo recupera en cada carga. Las causas plausibles basadas en el código son:

**HIPÓTESIS 1 — Percepción visual durante `AsyncLoading` (más probable):**  
En `_save()`, cualquier operación de guardado (incluyendo el toggle de notificaciones de agua) establece `state = const AsyncValue.loading()`:

```dart
// notification_providers.dart:57-60
Future<void> _save({...}) async {
  final previousState = state;
  state = const AsyncValue.loading();
  ...
}
```

`_SectorCard` observa `notificationPreferencesControllerProvider`:
```dart
// settings_screen.dart:92-93
prefs.when(
  loading: () => const LoadingView(),  // ← sector desaparece visualmente
```

Durante cualquier guardado (toggle de agua, cambio de sector), el sector es reemplazado por un spinner de carga. Si el guardado tarda por red lenta, el usuario percibe que el sector "desapareció".

**HIPÓTESIS 2 — Doble invalidación al volver de `SectorSelectionScreen`:**  
Cuando el usuario guarda un sector, la cadena es:
1. `_save()` en el controller: `state = AsyncValue.data(saved)` + `ref.invalidate(notificationPreferencesProvider)` (notification_providers.dart:72)
2. `Navigator.pop()` en `SectorSelectionScreen` (sector_selection_screen.dart:51)
3. `ref.invalidate(notificationPreferencesProvider)` en `_openSectorSelection` (settings_screen.dart:174) — segunda invalidación

Aunque la doble invalidación no afecta `notificationPreferencesControllerProvider` directamente (son providers distintos), la segunda invalidación fuerza un nuevo fetch de `notificationPreferencesProvider`. Si el fetch de red falla o retorna lentamente, `communitySummaryProvider` y `sectorWaterStatusProvider` (que consumen `notificationPreferencesProvider.future`) quedan en estado loading o error, lo que puede causar que el "Agua en tu sector" del Home muestre "Sin información" — el usuario podría interpretar esto como el sector desaparecido en Home, no en Ajustes.

**EVIDENCIA INSUFICIENTE:** No hay código que explique una pérdida silenciosa y persistente del sector de interés. El valor se guarda en la BD y se recupera en cada `_load()`. Si hay una pérdida permanente, el origen más probable es un error de red silenciado en `_load()` que deja el controller en `AsyncError`:

```dart
// notification_providers.dart:40-43
} catch (error, stackTrace) {
  state = AsyncValue.error(error, stackTrace);
}
```

En `_SectorCard`, `AsyncError` muestra el botón "Reintentar" — que el usuario podría confundir con "no hay sector configurado".

No se puede confirmar desde el código si hay una condición de carrera que escribe `null` en el sector. La RPC `savePreferences` recibe `sectorId: clearSector ? null : (sectorId ?? current?.preferredSectorId)` — si `clearSector=false`, `sectorId=null`, y `current?.preferredSectorId` es null (por error de lectura), se pasa `null` como sector y el backend lo registraría como borrado.

### Evidencia

```dart
// notification_providers.dart:63-68
final saved = await ref
    .read(notificationRepositoryProvider)
    .savePreferences(
      sectorId: clearSector
          ? null
          : (sectorId ?? current?.preferredSectorId),  // null si current es null
      enabled: enabled ?? current?.waterNotificationsEnabled ?? false,
    );
```

Si `current` es null (estado no cargado aún) y se llama a `_save()` antes de que `_load()` complete, el sector se guardaría como null.

```dart
// notification_providers.dart:30-31
AsyncValue<NotificationPreferences?> build() {
  Future<void>.microtask(_load);
  return const AsyncValue.loading();  // estado inicial es loading
}
```

Si se dispara un save mientras el estado es `AsyncLoading` (es decir, `state.value == null`), el sector se escribe como null.

### Corrección mínima propuesta

Guardar la operación de escritura si el estado de preferencias no ha cargado aún:

```diff
// notification_providers.dart:53-57
Future<void> _save({...}) async {
  final previousState = state;
  final current = previousState.value;
+ if (previousState.isLoading) {
+   // Esperar que _load() complete antes de permitir escrituras
+   _saveError = null;
+   return;  // o await la carga antes de continuar
+ }
  _saveError = null;
  state = const AsyncValue.loading();
  ...
}
```

Además, eliminar la invalidación redundante en `settings_screen.dart:174` ya que el controller ya llama `ref.invalidate(notificationPreferencesProvider)` dentro de `_save()`.

### Riesgo de regresión
Medio. El guard añadido podría silenciar intentos de guardado legítimos en el arranque. Requiere pruebas de flujo completo.

### Prueba necesaria para verificar la corrección
1. Configurar sector de interés → navegar entre pestañas varias veces → verificar que el sector persiste.
2. Tener red lenta → configurar sector → volver a Ajustes → verificar que el sector persiste.
3. Toggle de notificaciones de agua → verificar que el sector NO desaparece durante el guardado.
4. Matar y relanzar la app → verificar que el sector sigue configurado.

### Clasificación
`BETA FIX`

---

## Hallazgo 5 — Ajustes visuales/UX (solo identificación de ubicación en código)

### Finding
Cinco ajustes de texto/layout identificados. **NO se implementan en este diagnóstico.**

### Archivo(s) y líneas exactas

#### 5.1 Home — eliminar texto "Resumen de hoy"
- **Archivo:** `lib/features/home/presentation/home_screen.dart:387`
- **Fragmento:**
  ```dart
  Text(
    'Resumen de hoy',
    style: Theme.of(context).textTheme.titleMedium?.copyWith(...),
  ),
  ```
- **Acción:** Eliminar ese `Text(...)` y el `SizedBox(height: AppSpacing.md)` que le sigue (línea 393).

#### 5.2 Agua — eliminar texto "Resumen"
- **Archivo:** `lib/features/water/presentation/water_screen.dart:129`
- **Constante:** `WaterCopy.summaryTitle = 'Resumen'` (`lib/features/water/presentation/water_copy.dart:6`)
- **Fragmento en water_screen.dart:**
  ```dart
  Text(
    WaterCopy.summaryTitle,
    style: Theme.of(context).textTheme.titleLarge,
  ),
  const SizedBox(height: AppSpacing.sm),
  const _StatisticsCard(),
  ```
- **Acción:** Eliminar las líneas 128-131 (`Text(WaterCopy.summaryTitle)` + `SizedBox`). La tarjeta `_StatisticsCard` queda sin encabezado o puede moverse junto al historial.

#### 5.3 Reportar — eliminar leyenda debajo de "¿Dónde está la fuga?"
- **Archivo:** `lib/features/leaks/presentation/leak_report_screen.dart:138-142`
- **Fragmento:**
  ```dart
  const Text(
    'Usa tu GPS o indica la zona manualmente. Esto ayuda a tus '
    'vecinos a encontrarla en el mapa.',
    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
  ),
  ```
- **Acción:** Eliminar ese bloque `const Text(...)` y el `SizedBox(height: 4)` anterior (línea 137).

#### 5.4 Reportar — mover tarjeta de ubicación debajo de los dropdowns
- **Archivo:** `lib/features/leaks/presentation/leak_report_screen.dart`
- **Tarjeta a mover:** Bloque `if (state.locationSuggestion?.displayText != null)` (líneas 600-632 en `DataStepView.build`)
- **Posición actual:** Antes del dropdown de municipio (línea 633)
- **Posición deseada:** Después del dropdown de sector (`_SectorsDropdown`, línea 676) y el `SizedBox(height: 12)` que lo separa de la descripción
- **Acción:** Cortar el bloque `if (state.locationSuggestion?.displayText != null) [..., SizedBox(height: 8)]` (líneas 600-632) y pegarlo tras el bloque `if (effectiveMunicipalityId != null) _SectorsDropdown(...)` + `SizedBox(height: 12)` (aproximadamente tras línea 683).

#### 5.5 Reportar — no mostrar GUID en pantalla de confirmación
- **Archivo:** `lib/features/leaks/presentation/leak_report_controller.dart:440-448` (el GUID está en el `message:`, líneas **446-447**; `442-445` sólo contiene `submitState`, `outcome` y `currentStep`)
- **Fragmento:**
  ```dart
  case ReportCreated(:final reportId):
    state = state.copyWith(
      ...
      message: '¡Reporte enviado! La fuga quedó registrada como '
               'activa (ID $reportId).',  // ← GUID expuesto al usuario
    );
  ```
- **Acción:** Reemplazar el mensaje eliminando `(ID $reportId)`:
  ```diff
  - message: '¡Reporte enviado! La fuga quedó registrada como activa (ID $reportId).',
  + message: '¡Reporte enviado! La fuga quedó registrada como activa.',
  ```

### Causa raíz
CONFIRMADO en todos los casos. Son texto literal en código o constante en `WaterCopy`.

### Corrección mínima propuesta
Ver acción por ítem arriba.

### Riesgo de regresión
Muy bajo. Son eliminaciones de texto/reordenamiento de widgets dentro de un scroll `ListView`. No afectan lógica de negocio ni providers.

### Prueba necesaria para verificar la corrección
1. Abrir Home → verificar que NO aparece "Resumen de hoy".
2. Abrir Agua → verificar que NO aparece "Resumen".
3. Abrir Reportar → Ubicación → verificar que no hay leyenda bajo "¿Dónde está la fuga?".
4. Abrir Reportar → Datos → verificar que la tarjeta de ubicación aparece DESPUÉS de los dropdowns.
5. Completar un reporte → verificar que la pantalla de resultado no muestra el GUID del reporte.

### Clasificación
`POLISH`

---

## Tabla resumen

| # | Hallazgo | Clasificación | Causa raíz (1 línea) | Archivo principal | Effort |
|---|---|---|---|---|---|
| 1 | Mapa pan/zoom — "Sin fugas" | `BETA FIX` | `data([])` desmonta `GotaMapView`; sin debounce ni overlay | `map_screen.dart:87-99` | M |
| 2 | Fotos — cierres | `BLOCKER` | `catch (e) on Exception` no captura `Error` nativo; límite a 2 exige cliente **y** `system_config.photo_limits.max_count` (ver C2) | `photo_service.dart`, `leak_report_controller.dart:308`, `photo_limits.dart:11` | S |
| 3 | Continuar deshabilitado | `BETA FIX` | `DropdownButtonFormField.initialValue` no dispara `onChanged`; draft queda vacío con sugerencia | `leak_report_controller.dart:199` | S |
| 4 | Sector de interés desaparece | `BETA FIX` | `AsyncLoading` durante `_save()` oculta el sector; posible escritura null si save antes de load | `notification_providers.dart:57` | S |
| 5 | Ajustes UX (5 ítems) | `POLISH` | Texto literal / layout en `DataStepView`; GUID en mensaje de confirmación | `home_screen.dart:387`, `water_screen.dart:129`, `leak_report_screen.dart:138`, `leak_report_controller.dart:444` | XS |

---

## Verificación independiente del orquestador (Hermes)

Contrastado contra el código, el **merged manifest del build** y la **base de datos viva** (stack
Docker local, sólo `SELECT`). Tres correcciones y dos matices al informe anterior:

### C1 — Hallazgo 2: el `FileProvider` SÍ está en el build (hipótesis descartada)

Evidencia real del manifiesto fusionado del build:
`build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml:156-158`
```xml
<provider
    android:name="io.flutter.plugins.imagepicker.ImagePickerFileProvider"
    android:authorities="com.gota.app.flutter.image_provider"
```
La fusión del manifiesto del plugin ocurre correctamente. Además, **no hay `android.permission.CAMERA`
declarado** en el manifiesto fusionado, lo cual es lo correcto: `image_picker` usa
`ACTION_IMAGE_CAPTURE` (la app de cámara del sistema es quien tiene el permiso), por lo que la
ausencia del permiso **no** es causa del cierre. → Se elimina esta hipótesis del diagnóstico y del
pendiente de validación.

### C2 — Hallazgo 2: la regla "MÁXIMO 2 FOTOS" requiere DOS cambios, no uno (omisión material)

El informe sólo propone `kReportPhotoMaxCount = 3 → 2` (cliente). La autoridad es el servidor:

| Capa | Valor actual | Evidencia |
|---|---|---|
| Cliente | `kReportPhotoMaxCount = 3` | `lib/features/leaks/data/photo_limits.dart:11` |
| Servidor (`system_config`) | `max_count: 3` | `SELECT value FROM system_config WHERE key='photo_limits'` → `{"max_bytes": 10485760, "max_count": 3, ...}` |
| RPC `create_leak_report` | rechaza fuera de `1..max_count` | `supabase/migrations/20260913000023_rate_limiting_integration.sql:128-134` → `VALIDATION_ERROR` "La cantidad de fotos debe ser entre 1 y 3" |

Con sólo el cambio en el cliente, un reporte con 3 fotos (posible vía API o si el cliente se
desincroniza) seguiría aceptándose, y el mensaje servidor seguiría diciendo "entre 1 y 3". **La regla
se aplica en dos puntos:** `photo_limits.dart:11` y el valor de `system_config.photo_limits.max_count`
(cambio de datos → requiere migración o `UPDATE` sobre `system_config`, decisión del usuario, fuera
del alcance "sin migraciones" de esta fase). Calidad ya cumple (`imageQuality: 80`, `quality: 82`,
`1920×1920`): es calidad estándar, no alta resolución.

### C3 — Hallazgo 3: el "Continuar" no puede habilitarse sin escribir el borrador (restricción que valida la opción propuesta)

`goToNext()` (`leak_report_controller.dart:383-392`) **no valida nada**: sólo avanza de paso. Los
valores que llegan al backend salen del borrador:
`lib/features/leaks/data/leak_report_repository.dart:118-119` → `'p_municipality_id': draft.municipalityId, 'p_sector_id': draft.sectorId`.

Consecuencia: una corrección que se limite a *habilitar* el botón (p. ej. condicionar `onPressed` a
los valores efectivos) permitiría avanzar y **enviar el reporte con municipio/sector nulos**. Por
tanto la corrección propuesta —escribir la sugerencia en el borrador en `_applyMunicipalitySuggestion`
(controller.dart:199 y 212-213), manteniendo los dropdowns editables— es la correcta para la causa
raíz. Variante más estrecha, equivalente: commitear los valores efectivos en el propio handler de
"Continuar" (`selectMunicipality(effectiveMunicipalityId!)` + `selectSector(effectiveSectorId!)`
antes de `goToNext()`), evitando tener que invertir la lógica de `isMunicipalitySuggested`. Ninguna
de las dos es "selección automática irreversible": el usuario sigue pudiendo cambiar ambos listados.

### C4 — Hallazgo 4: el guard propuesto silencia guardados legítimos

`return;` temprano cuando `previousState.isLoading` (corrección propuesta en el informe) descarta el
guardado del usuario sin feedback si el toggle se toca durante la carga inicial. Alternativa con
menor pérdida funcional: (a) impedir la escritura de `null` sólo cuando `current == null`
(`notification_providers.dart:63-70`), y (b) tratar el guardado como *refresh* conservando el valor
previo (`state = const AsyncValue.loading().copyWithPrevious(previousState)` +
`skipLoadingOnReload: true` en el consumo de `settings_screen.dart:92-93`), de modo que el sector no
desaparezca visualmente durante el guardado. El diagnóstico de la causa (HIPÓTESIS 1) queda igual.

### C5 — Hallazgo 1: matiz verificado sobre "temporalmente"

`skipLoadingOnReload: true` (map_screen.dart:74) no sólo no cubre `data([])`: muestra el **último
resultado completado** durante el refetch. Si ese último resultado era vacío (zona sin reportes), el
texto "Sin fugas para mostrar" se pinta durante toda la latencia de la consulta en vuelo — de ahí lo
"temporal" del síntoma, además del desmonte del mapa que describe el informe. Ambos mecanismos son
reales y se corrigen con la misma opción B (mapa siempre montado + overlay).

---

## Pendiente de validación en dispositivo

Los siguientes puntos **no se pueden determinar solo desde el código** y requieren reproducción en hardware real:

1. ~~**Hallazgo 2 — FileProvider en Android (cámara)**~~ — **DESCARTADO** en la verificación C1:
   el `FileProvider` del plugin está presente en el manifiesto fusionado del build. No requiere
   reproducción.

2. **Hallazgo 2 — Compresión en dispositivos con poca RAM:** El doble proceso de compresión (`imageQuality:80` + `FlutterImageCompress quality:82`) sobre imágenes de 12-48 MP en dispositivos Android de gama baja puede saturar la memoria antes de que Dart recoja el buffer nativo. El crash sería un OOM nativo (no un Error/Exception de Dart) y no aparecería en el log de Flutter.

3. **Hallazgo 2 — Rutas de galería en Android 10+ (Scoped Storage):** Confirmar que `image_picker` en Android 10+ devuelve un path legible por `FlutterImageCompress` y no solo una URI de contenido. Si se devuelve URI, `File(path)` en `prepareFromFile` lanzaría `FileSystemException`, que sí es un `Exception` y quedaría capturado.

4. **Hallazgo 1 — Frecuencia real de `onCameraIdle`:** Confirmar en dispositivo cuántas veces se dispara `onCameraIdle` durante un pan continuo suave vs. durante un scroll rápido. El debounce apropiado depende de la cadencia real.

5. **Hallazgo 4 — Condición de arranque en frío:** Verificar si el sector desaparece solo en la primera apertura de la app (estado de carga inicial) vs. en sesiones posteriores. Distinguiría entre un race condition de arranque vs. un problema de persistencia.

---

## Veredicto final

`DIAGNOSTIC COMPLETE — READY FOR FIX PLAN`
