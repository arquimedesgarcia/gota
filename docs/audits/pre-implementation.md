Verificación completa contra `525725c` (los 5 hallazgos, las correcciones C1–C5 y el test que fija el límite de fotos revisados en el código real). No puedo escribir en tu repo local desde acá: copiá el documento de abajo como `docs/PLAN_IMPLEMENTACION_2026-09-22.md` (sin commitear).

---

# PLAN DE IMPLEMENTACIÓN — Gota v0.2 · 2026-09-22

**Baseline:** `fix/map-r5-r6` @ `525725c` · Todo hallazgo re-verificado contra el código del baseline (rama ya pusheada a `origin`, inspección por web). Las correcciones C1–C5 del orquestador se aceptan como insumo verificado.

## §1.1 Tabla índice

| # | Hallazgo | Clasificación | Archivo(s) núcleo | Dependencias | Modelo sugerido | Turnos |
|---|---|---|---|---|---|---|
| 2 | Cierres al tomar/elegir foto + máx. 2 fotos | **BLOCKER** | `photo_limits.dart`, `leak_report_controller.dart` | Ninguna (tanda 1) | Sonnet (código) · Haiku (tests) | 4–6 |
| 1 | Mapa salta / "Sin fugas para mostrar" en pan/zoom | BETA FIX | `map_screen.dart` | Ninguna; corre solo (único que toca este archivo) | Sonnet | 6–8 |
| 4 | Sector de interés desaparece ocasionalmente | BETA FIX | `notification_providers.dart`, `settings_screen.dart` | Ninguna (tanda 1) | Sonnet | 3–4 |
| 3 | "Continuar" deshabilitado con preselección GPS | BETA FIX | `leak_report_controller.dart`, `leak_report_screen.dart` | Después de H2 (mismo controller); antes que H5 | Sonnet | 3–4 |
| 5 | Cinco ajustes de texto/layout | POLISH | `home_screen.dart`, `water_screen.dart`, `water_copy.dart`, `leak_report_screen.dart`, `leak_report_controller.dart` | Después de H2 y H3 (mismo controller/screen) | Haiku | 2–3 |

## §2 Prompts de implementación

---

### PROMPT — HALLAZGO 2 — Cierres al tomar/elegir foto + límite máximo de 2 fotos
**BLOCKER · Sonnet (implementación) + Haiku (tests) · 4–6 turnos · base `fix/map-r5-r6` @ `525725c`**

**2. Objetivo.** Al tomar o elegir una foto, cualquier fallo del proceso de imagen muestra un mensaje en pantalla y jamás cierra la app; el flujo de reporte acepta como máximo 2 fotos en el cliente.

**3. Causa raíz aceptada.**
- CONFIRMADO: `addPhoto` captura `on Exception` pero no `Error` (`leak_report_controller.dart:308-314`). Un `Error` (JNI de `FlutterImageCompress`, `StateError`, etc.) escapa al zone handler y puede tumbar la app.
- CONFIRMADO: límite cliente `kReportPhotoMaxCount = 3` (`photo_limits.dart:11`) vs regla de negocio "MÁXIMO 2 FOTOS".
- HIPÓTESIS (fuera de alcance, va a `NOT VERIFIED`): OOM nativo en compresión en gama baja — un crash de proceso nativo no es capturable desde Dart.

**4. Archivos.** SÍ: `lib/features/leaks/data/photo_limits.dart`, `lib/features/leaks/data/photo_service.dart`, `lib/features/leaks/presentation/leak_report_controller.dart`, `test/features/leaks/photo_limits_test.dart`, tests del controller. PROHIBIDOS: RPC `create_leak_report`, migraciones, `system_config` (cambio de datos aparte), backend, `main`, worktree paralelo.

**5. Contrato explícito.**
1. `photo_limits.dart:11` → `const kReportPhotoMaxCount = 2;`. La UI interpola `LeakReportController.photoMaxCount` en `leak_report_screen.dart` — no queda literal "3"; verificar con búsqueda.
2. Seam de test: en `photo_service.dart` agregar `final photoServiceProvider = Provider<PhotoService>((ref) => ImagePickerPhotoService());` (import `flutter_riverpod`). En `leak_report_controller.dart`, `addPhoto` reemplaza `final service = ImagePickerPhotoService();` por `final service = ref.read(photoServiceProvider);`.
3. En `addPhoto`, el catch final pasa de `on Exception` a `catch (_)` (captura `Exception` y `Error`); los catch específicos previos se mantienen; el mensaje no cambia: `PhotoValidationException('No pudimos procesar esa foto. Elige otra.').userMessage`.
4. `photo_limits_test.dart` línea `expect(kReportPhotoMaxCount, 3)` → `2`. Justificación (regla dura 6): la regla de negocio cambió; este test ES el control de mutación del límite.
5. Actualizar cualquier otro test existente que asuma 3 fotos o el mensaje "máximo de 3".

**6. Diff conceptual.**
```diff
 // photo_limits.dart:11
-const kReportPhotoMaxCount = 3;
+const kReportPhotoMaxCount = 2;

 // photo_service.dart (nuevo, al final)
+final photoServiceProvider = Provider<PhotoService>(
+  (ref) => ImagePickerPhotoService(),
+);

 // leak_report_controller.dart — addPhoto
-    final service = ImagePickerPhotoService();
+    final service = ref.read(photoServiceProvider);
     ...
-    on Exception {
+    catch (_) {
```

**7. Criterios de aceptación.** `flutter analyze` sin issues; `flutter test` verde; con fake que lanza `Error()` desde `pickAndPrepare`, `addPhoto` no propaga y `state.message` es el mensaje de error; con 2 fotos en el borrador, `addPhoto` deja `state.message == 'Ya tienes el máximo de 2 fotos.'` y no agrega; ningún texto visible ofrece más de 2 fotos.

**8. Tests obligatorios.** (a) Mutación límite: `expect(kReportPhotoMaxCount, 2)`. (b) Mutación catch: fake de `PhotoService` que lanza `Error()` → `state.message != null` y nada se propaga (falla si se revierte a `on Exception`). (c) Límite alcanzado con 2. NO mockear `image_picker` ni `FlutterImageCompress` reales: usar el seam del punto 5.2.

**9. Evidencia a devolver.** `STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(no) / BLOCKER`.

**10. Fuera de alcance.** RPC, `system_config` (la autoridad server-side sigue en 3 hasta la aprobación de datos — se documenta como pendiente, no se toca), calidad de compresión (ya cumple), OOM nativo.

**11. Rollback.** `git checkout -- lib/features/leaks test/features/leaks` (sin migraciones involucradas, rollback trivial). No commitear.

**12. Dependencias.** Ninguna. Libera `leak_report_controller.dart` para H3 y H5.

---

### PROMPT — HALLAZGO 1 — Mapa: salta y muestra "Sin fugas para mostrar" durante pan/zoom
**BETA FIX · Sonnet · 6–8 turnos · base `fix/map-r5-r6` @ `525725c`**

**2. Objetivo.** Durante pan/zoom el mapa nunca se desmonta ni parpadea; al detenerse sobre una zona sin reportes aparece un overlay estable sobre el mapa montado.

**3. Causa raíz aceptada.** CONFIRMADO, dos mecanismos (C5): (a) en la rama `data:` de `map_screen.dart:87-99`, `reports.isEmpty` devuelve `_MapEmptyView` en lugar del `Stack` con `_MapViewContent` → desmonta MapLibre (destrucción del contexto GL); el `addPostFrameCallback` con `clearBounds()` dispara además una segunda query sin bbox → rebote monta/desmonta. (b) con `skipLoadingOnReload: true` (línea 74), si el último resultado completado era `[]`, la vista vacía se pinta durante toda la latencia del refetch.

**4. Archivos.** SÍ: `lib/features/map/presentation/map_screen.dart` y su test. PROHIBIDOS: `widgets/gota_map_view.dart` y `map_providers.dart` (el debounce NO se implementa: la cadencia real de `onCameraIdle` es dato de dispositivo, regla de negocio §6), backend, GPS/D2, `main`.

**5. Contrato explícito.**
1. Eliminar en la rama `data:` el bloque completo `if (reports.isEmpty) { WidgetsBinding...clearBounds(); return _MapEmptyView(...); }` incluido el `addPostFrameCallback`.
2. En `MapViewMode.map`: el `Stack` incluye SIEMPRE `_MapViewContent(leaks: reports, ...)`; si `reports.isEmpty`, se añade un hijo posterior `_MapEmptyOverlay()` — widget privado nuevo, banner centrado con el texto actual 'Sin fugas para mostrar' — que NO desmonta el mapa. Reutilizar la clave pública `mapEmptyStateKey` en el overlay (los tests la referencian).
3. `MapViewMode.list`: se conserva el comportamiento vacío actual (no hay mapa montado en ese modo).
4. Intactos: filtros, "Mi sector" (overlay 'Configura tu sector en Ajustes' cuando aplica), leyenda, tarjeta de reporte seleccionado (`selectedReportId`), `skipLoadingOnReload: true`.
5. Prohibido añadir debounce temporal, timers o lógica en `map_providers.dart`.
6. Mecanismo (b) resultante: durante un refetch cuyo dato previo era `[]`, se muestra `data([])` + overlay hasta llegar el nuevo dato — aceptado: el mapa queda montado y el overlay es estable (sin destrucción GL ni parpadeo).

**6. Diff conceptual.**
```diff
 data: (reports) {
-  if (reports.isEmpty) {
-    WidgetsBinding.instance.addPostFrameCallback((_) {
-      ref.read(mapFilterProvider.notifier).clearBounds();
-    });
-    return _MapEmptyView(filterState: filterState);
-  }
   return switch (filterState.viewMode) {
     MapViewMode.map => Stack(children: [
       _MapViewContent(leaks: reports, ...),
+      if (reports.isEmpty) const _MapEmptyOverlay(),
       ...legend, selected card...
     ]),
```

**7. Criterios de aceptación.** Modo mapa con `[]` → widgets con `gotaMapContainerKey` Y `mapEmptyStateKey` presentes simultáneamente; con datos → mapa y markers, sin overlay; modo lista y filtros sin regresión; `flutter analyze` y `flutter test` verdes.

**8. Tests obligatorios.** Usar los overrides existentes (`mapWidgetBuilderProvider`, providers de reportes/filtro — ver `test/providers.dart` y `map_screen_test.dart` actuales). **Control de mutación:** test que con `data([])` en modo mapa el widget con `gotaMapContainerKey` está presente (falla con el código actual). NO mockear MapLibre: ya se inyecta vía builder.

**9. Evidencia a devolver.** `STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(no) / BLOCKER`.

**10. Fuera de alcance.** `gota_map_view.dart`, `map_providers.dart`, backend, rendimiento/fluidez en hardware (dispositivo).

**11. Rollback.** `git checkout -- lib/features/map test/features/map`.

**12. Dependencias.** Ninguna; corre solo. Ningún otro prompt toca `map_screen.dart`.

---

### PROMPT — HALLAZGO 4 — Sector de interés desaparece ocasionalmente
**BETA FIX · Sonnet · 3–4 turnos · base `fix/map-r5-r6` @ `525725c`**

**2. Objetivo.** Guardar preferencias (toggle de agua, cambiar/quitar sector) nunca hace desaparecer visualmente el sector configurado ni puede persistir un sector nulo no intencional.

**3. Causa raíz aceptada.** CONFIRMADO en código (variante C4): (a) `_save()` pone `state = const AsyncValue.loading()` (`notification_providers.dart:57-60`) → `_SectorCard` pinta `LoadingView` durante todo el guardado (HIPÓTESIS 1 del informe, verificada). (b) si `_save` corre antes de que `_load()` complete, `current == null` y se persiste `sectorId: null` (`notification_providers.dart:63-70`) — riesgo de borrado real, antes "evidencia insuficiente", ahora CONFIRMADO estructural (la persistencia efectiva depende del upsert del repository: NO tocar el repository; la prueba de integración real queda `NOT VERIFIED`).

**4. Archivos.** SÍ: `lib/features/notifications/presentation/notification_providers.dart`, `lib/features/notifications/presentation/settings_screen.dart`, tests. PROHIBIDOS: repository/RPC/RLS, backend, `main`.

**5. Contrato explícito.**
1. Guard temprano con feedback: al inicio de `_save()`, si `!state.hasValue` → `_saveError = StateError('Tus preferencias aún están cargando. Intenta de nuevo en un momento.')` y `return` SIN escribir. Los puntos de llamada ya muestran `saveError` en SnackBar (`_WaterNotificationsCard`, `_confirmClear`) — responde a C4: nunca se descarta en silencio.
2. Reemplazar `state = const AsyncValue.loading()` por `state = AsyncValue<NotificationPreferences?>.loading().copyWithPrevious(state)`: el valor previo permanece visible durante el guardado; `isLoading` sigue `true` → el switch se sigue deshabilitando (`settings_screen.dart:169`).
3. `_SectorCard`: `prefs.when(skipLoadingOnReload: true, loading: () => const LoadingView(), error: ..., data: ...)` → durante el refetch se conserva el valor previo en pantalla.
4. Eliminar el `ref.invalidate(notificationPreferencesProvider)` redundante en `_openSectorSelection` (`settings_screen.dart:174`): `_save()` ya invalida tras guardar. Añadir comentario de una línea con el porqué.
5. Semántica de `savePreferences` y contrato con backend: intactos.

**6. Diff conceptual.** según 5.1–5.4 (guard + `copyWithPrevious` + `skipLoadingOnReload` + quitar invalidate).

**7. Criterios de aceptación.** Durante un guardado con dato previo, la tarjeta de sector sigue mostrando el sector (no `LoadingView`); toggle antes de la primera carga → SnackBar con el mensaje del guard y `savePreferences` jamás invocado; `flutter analyze`/`flutter test` verdes.

**8. Tests obligatorios.** Fake de `NotificationRepository`. **Controles de mutación:** (a) con `AsyncData` (sector X), `setWaterNotificationsEnabled(true)` con repositorio de delay controlado → durante el await `state.value!.preferredSectorId == 'X'` (falla si se revierte a `loading()` puro); (b) toggle disparado antes de que `getPreferences` complete → `savePreferences` NUNCA llamado (flag de verificación) y `saveError != null`. NO mockear red real ni Supabase.

**9. Evidencia a devolver.** `STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(no) / BLOCKER`.

**10. Fuera de alcance.** Repository, RPC, persistencia real en frío (dispositivo), doble invalidación fuera de `_openSectorSelection`.

**11. Rollback.** `git checkout -- lib/features/notifications test/features/notifications`.

**12. Dependencias.** Ninguna (tanda 1, paralelo con H2 y H1).

---

### PROMPT — HALLAZGO 3 — "Continuar" deshabilitado con municipio/sector preseleccionados
**BETA FIX · Sonnet · 3–4 turnos · base `fix/map-r5-r6` @ `525725c`**

**2. Objetivo.** Si el GPS/reverse-geocode resuelve municipio y sector, "Continuar" queda habilitado sin tocar los dropdowns; los dropdowns siguen editables y el envío siempre lleva municipio/sector no nulos.

**3. Causa raíz aceptada.** CONFIRMADO: `_applyMunicipalitySuggestion` solo escribe `suggestedMunicipalityId`/`suggestedSectorId` (`leak_report_controller.dart:~199` y `:~212-213`); el botón exige `draft.municipalityId != null && draft.sectorId != null` (`leak_report_screen.dart:706-708`); `DropdownButtonFormField.initialValue` no dispara `onChanged`. C3 CONFIRMADO: el backend lee del borrador (`leak_report_repository.dart` → `p_municipality_id`/`p_sector_id`), por lo que habilitar sin commit enviaría nulos.

**4. Archivos.** SÍ: `lib/features/leaks/presentation/leak_report_controller.dart` (solo `_applyMunicipalitySuggestion` y su comentario), `lib/features/leaks/presentation/leak_report_screen.dart` (solo las condiciones `isMunicipalitySuggested`/`isSectorSuggested` en `DataStepView`), tests. PROHIBIDOS: repository, RPC, flujos GPS/D2, `goToNext` (sin cambios), `selectMunicipality`/`selectSector` (sin cambios), `main`.

**5. Contrato explícito.**
1. Al matchear municipio: `state = state.copyWith(suggestedMunicipalityId: matched, draft: state.draft.copyWith(municipalityId: matched, sectorId: null))` — el sector se anula porque el sugerido aún no está resuelto y no debe quedar un sector de otro municipio.
2. Al matchear sector (mismo municipio): `state = state.copyWith(suggestedSectorId: matchedSector, draft: state.draft.copyWith(sectorId: matchedSector))`.
3. Reescribir el comentario que hoy dice "Nunca modifica draft…": la sugerencia ES la selección inicial, editable.
4. `DataStepView`: `isMunicipalitySuggested = state.draft.municipalityId != null && state.draft.municipalityId == state.suggestedMunicipalityId`; `isSectorSuggested = state.draft.sectorId != null && state.draft.sectorId == state.suggestedSectorId`. El texto 'Sugerido según ubicación GPS' se conserva.
5. `goToNext()` intacto: el commit del punto 1–2 ya garantiza el invariante de C3 (borrador no nulo al avanzar, pues el botón solo se habilita con draft completo).
6. El usuario puede seguir cambiando ambos dropdowns después; cambiar de municipio limpia el sector (comportamiento existente de `selectMunicipality`).

**6. Diff conceptual.** según 5.1–5.4.

**7. Criterios de aceptación.** Con sugerencia que matchea municipio+sector, el botón "Continuar" habilitado sin interacción; con ubicación manual sin sugerencia, deshabilitado; cambio manual de municipio → sector limpio y botón deshabilitado hasta elegir sector; `flutter analyze`/`flutter test` verdes.

**8. Tests obligatorios.** Overrides de `suggestionServiceProvider`/`municipalitiesProvider`/`sectorsProvider` (ver `test/providers.dart`). **Control de mutación:** con sugerencia completa, `state.draft.municipalityId` y `state.draft.sectorId` no nulos (falla si se revierte el commit). Casos: cambio manual de municipio limpia sector; select explícito habilita; sin sugerencia permanece deshabilitado.

**9. Evidencia a devolver.** `STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(no) / BLOCKER`.

**10. Fuera de alcance.** Repository, RPC, autoavance de paso, invalidación de sugerencia al cambiar ubicación (mecanismo actual vía `effectiveMunicipalityId`).

**11. Rollback.** `git checkout -- lib/features/leaks test/features/leaks`.

**12. Dependencias.** Después de H2 (mismo controller). Antes que H5 (mismo controller y screen). Paralelo con H1 y H4.

---

### PROMPT — HALLAZGO 5 — Cinco ajustes de texto/layout (UX)
**POLISH · Haiku · 2–3 turnos · base `fix/map-r5-r6` @ `525725c`**

**2. Objetivo.** Aplicar los 5 ajustes del informe §7.5 con cero cambios de lógica.

**3. Causa raíz aceptada.** CONFIRMADO (los 5): texto literal en código / orden de widgets / GUID en mensaje.

**4. Archivos.** SÍ: `home_screen.dart`, `water_screen.dart`, `water_copy.dart`, `leak_report_screen.dart`, `leak_report_controller.dart`, sus tests. PROHIBIDOS: todo lo demás.

**5. Contrato explícito (los 5 ítems, exactos).**
1. **Home:** eliminar en `home_screen.dart:387-393` el `Text('Resumen de hoy', ...)` y el `SizedBox(height: AppSpacing.md)` que le sigue.
2. **Agua:** eliminar en `water_screen.dart` el `Text(WaterCopy.summaryTitle, ...)` y su `SizedBox(height: AppSpacing.sm)` (bloque previo a `_StatisticsCard()`); eliminar la constante `WaterCopy.summaryTitle` de `water_copy.dart:6` (verificar que no queda otro uso).
3. **Reportar/Ubicación:** eliminar en `leak_report_screen.dart:137-142` el `SizedBox(height: 4)` y la leyenda 'Usa tu GPS o indica la zona manualmente…'.
4. **Reportar/Datos:** mover el bloque `if (state.locationSuggestion?.displayText != null) [...Card...SizedBox(height: 8)]` (hoy antes del dropdown de municipio) para que quede DESPUÉS del bloque `if (effectiveMunicipalityId != null) _SectorsDropdown(...)` + su `SizedBox(height: 12)`, y antes del `TextField` de descripción. Solo reordenamiento.
5. **GUID:** en `leak_report_controller.dart:446-447` reemplazar el mensaje por `'¡Reporte enviado! La fuga quedó registrada como activa.'` (sin `(ID $reportId)`). El `reportId` se conserva en `state.outcome` (`ReportCreated`) para diagnóstico — no se elimina del estado.

**6. Diff conceptual.** según 5.1–5.5.

**7. Criterios de aceptación.** Los 5 textos/posiciones verificados en widget tests o ausencia de los literales (búsqueda en código); `flutter analyze`/`flutter test` verdes; ningún cambio de lógica (diff revisable a ojo).

**8. Tests obligatorios.** Ajustar tests existentes que afirmen textos eliminados. **Control de mutación (único nuevo, barato):** con repository fake que devuelve `ReportCreated(reportId: 'abc-123')`, tras `submit()` `state.message` no contiene `'abc-123'` (falla si se revierte 5.5).

**9. Evidencia a devolver.** `STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(no) / BLOCKER`.

**10. Fuera de alcance.** Cualquier cambio de lógica, providers, copy distinto al especificado.

**11. Rollback.** `git checkout -- lib/features`.

**12. Dependencias.** Después de H2 y H3 (mismo controller/screen). No bloquea a nadie.

## §3 Matriz de dependencias y orden de ejecución

```
Tanda 1 (paralelo):   H2  ∥  H4  ∥  H1(solo; nadie más toca map_screen.dart)
Tanda 2:              H3   (requiere controller libre → después de H2)
Tanda 3:              H5   (requiere controller libre → H2; screen estable → H3)
Aparte, con aprobación: system_config.photo_limits.max_count 3→2 (cambio de datos)
```
- Con un solo agente, orden serial: **2 → 1 → 4 → 3 → 5**.
- Conflicto de archivos que impide paralelismo: `leak_report_controller.dart` (H2, H3, H5) y `leak_report_screen.dart` (H3, H5).

## §4 Aprobaciones requeridas del usuario

1. **`system_config.photo_limits.max_count` 3→2 (LOCAL):**
   `docker exec -i supabase_db_gota psql -U postgres -d postgres -c "SELECT value FROM public.system_config WHERE key='photo_limits';"` (antes) y
   `docker exec -i supabase_db_gota psql -U postgres -d postgres -c "UPDATE public.system_config SET value = jsonb_set(value, '{max_count}', '2') WHERE key='photo_limits';"` (después, repetir el SELECT).
2. **Mismo cambio en el cloud piloto** (ref `eghphmugrrbvbvodhasq`), solo con `npx supabase db query --linked -f "<archivo .sql con el UPDATE>"` y aprobación explícita. **Prohibido `npx supabase db push`** (re-aplicaría todas las migraciones locales; el remoto no tiene historial).
3. Merge a `main` / push: **no solicitado en esta fase** (los 3 commits locales de `main` quedan intactos; ningún prompt propone merge).

## §5 Plan de verificación por hallazgo (ejecuta el orquestador, no el agente)

**Precondición:** re-medir el baseline antes de arrancar agentes: `flutter analyze` (sin issues) y `flutter test` (contar tests reales; la referencia 164/164 es histórica, no evidencia).

| Hallazgo | Qué se ejecuta | Salida esperada | NOT VERIFIED |
|---|---|---|---|
| 2 | `flutter analyze` + `flutter test`; revisión del diff (catch `catch (_)` + `= 2`) | Verde; el test de mutación con `Error()` pasa | Cierre real en Android, OOM nativo, picker/cámara del sistema |
| 1 | Tests de mapa (mutación: mapa montado con `[]`); diff revisado a ojo | `gotaMapContainerKey` + `mapEmptyStateKey` presentes a la vez | Fluidez en hardware, frecuencia real de `onCameraIdle` |
| 4 | Tests del controller (mutación: valor previo durante save; guard anti-null) | Verde; SnackBar de guard en toggle temprano | Persistencia en frío en dispositivo, red lenta real |
| 3 | Tests del controller con sugerencia completa | `draft.municipalityId`/`sectorId` no nulos; botón habilitado | — (cubierto por tests de contrato) |
| 5 | `flutter test` (tests ajustados + mutación GUID) | Verde | Apariencia visual final |

**Gate de contrato de datos:** cualquier query PostgREST nueva debe usarse con `select` explícito. **Gate de base de datos:** solo probes de lectura contra `supabase_db_gota` (54322).

## §6 Veredicto del documento

`READY FOR CODING AGENTS`

---

```
VEREDICTO: READY FOR CODING AGENTS
DOCUMENTO: docs/PLAN_IMPLEMENTACION_2026-09-22.md   (sin commit; generado fuera del repo — copiar al repo local)
ÍNDICE:
  2. Cierres foto + máx. 2 fotos — BLOCKER — Sonnet+Haiku — 4–6 turnos — photo_limits.dart / leak_report_controller.dart
  1. Mapa pan/zoom "Sin fugas" — BETA FIX — Sonnet — 6–8 turnos — map_screen.dart
  4. Sector de interés desaparece — BETA FIX — Sonnet — 3–4 turnos — notification_providers.dart / settings_screen.dart
  3. Continuar con preselección — BETA FIX — Sonnet — 3–4 turnos — leak_report_controller.dart / leak_report_screen.dart
  5. Ajustes UX (5 ítems) — POLISH — Haiku — 2–3 turnos — home/water/leak_report
ORDEN DE EJECUCIÓN Y PARALELISMO: Tanda 1 en paralelo: H2 ∥ H4 ∥ H1 (H1 solo, único en map_screen.dart) → Tanda 2: H3 → Tanda 3: H5. Serial si hay un solo agente: 2 → 1 → 4 → 3 → 5.
APROBACIONES REQUERIDAS DEL USUARIO:
  - UPDATE de system_config.photo_limits.max_count 3→2 en local (docker exec psql, comando exacto en §4.1)
  - Mismo UPDATE en cloud piloto solo vía npx supabase db query --linked (§4.2; prohibido db push)
  - Merge/push a main: NO requerido en esta fase
DISCREPANCIAS CON EL INFORME:
  - H4: el riesgo de escritura de sector null (antes "evidencia insuficiente") queda CONFIRMADO estructuralmente (notification_providers.dart:63-70 con current==null); el fix propuesto es la variante C4 (guard con feedback vía saveError + copyWithPrevious + skipLoadingOnReload), no el return; silencioso del informe
  - H2: la causa del cierre en sí sigue siendo parcialmente HIPÓTESIS en lo nativo (OOM/crash de proceso no capturable desde Dart); el fix estructural cubre Error/Exception; lo nativo queda NOT VERIFIED
  - Resto: ninguna; C1–C5 aceptadas y verificadas
NO VERIFICABLE EN ESTE ENTORNO: cierre real de foto en Android, OOM nativo, cámara/galería del sistema, fluidez del mapa en hardware, frecuencia real de onCameraIdle, persistencia del sector en frío con red real, apariencia visual final (sin dispositivo conectado — solo Edge web)
```