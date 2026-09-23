# PLAN DE IMPLEMENTACIÓN — Gota v0.2 · Correcciones pre-beta

**Baseline auditado:** `fix/map-r5-r6` @ `525725c` · **Informe insumo:**
`docs/DIAGNOSTICO_PRE_IMPLEMENTACION_2026-09-22.md` · **Fecha:** 2026-09-22
**Estado:** pendiente de aprobación del usuario. **Ningún agente ha sido lanzado.**

Este documento contiene 5 prompts autocontenidos para agentes de codificación. Cada uno puede
pegarse solo: no requieren leer este plan ni el informe de diagnóstico.

---

## Índice y orden de ejecución

| # | Prompt | Clase | Archivo núcleo | Modelo | Turnos | Dependencias |
|---|---|---|---|---|---|---|
| 1 | Fotos: cierres + límite 2 + seam de test | BETA FIX *(ex-BLOCKER: no reproducido en device)* | `leaks/data/photo_service.dart`, `leaks/data/photo_limits.dart`, `leaks/presentation/leak_report_controller.dart` | Sonnet | 30-40 | ninguna |
| 2 | Mapa: no desmontar MapLibre + overlay estable | BETA FIX *(reproducido en device)* | `map/presentation/map_screen.dart` | Sonnet | 30-40 | ninguna |
| 3 | "Continuar" con preselección: commit al borrador | BETA FIX | `leaks/presentation/leak_report_screen.dart` | Haiku | 15-20 | serializar con 5 (mismo archivo) |
| 4 | Sector de interés: no ocultar ni borrar el valor | BETA FIX | `notifications/presentation/notification_providers.dart`, `notifications/presentation/settings_screen.dart` | Sonnet | 25-35 | ninguna |
| 5 | UX/POLISH (5 ítems de texto/layout) | POLISH | `home/presentation/home_screen.dart`, `water/presentation/water_screen.dart`, `leaks/presentation/leak_report_screen.dart`, `leaks/presentation/leak_report_controller.dart` | Haiku | 15-25 | **después de 1 y 3** |

**Conflictos de archivo reales (verificados):**

- `leak_report_controller.dart` lo tocan **1** (`addPhoto`) y **5** (`message` del `ReportCreated`) → **no pueden correr en paralelo**.
- `leak_report_screen.dart` lo tocan **3** y **5** → serializar.
- `map_screen.dart` (2) y `notification_*` (4) son exclusivos.

**Orden:**

```
Tanda 1 (paralelo, sin conflictos):  1  ∥  2  ∥  4
Tanda 2:                              3   (screen libre)
Tanda 3:                              5   (controller y screen libres)
```

Serial con un solo agente: **1 → 2 → 4 → 3 → 5**.

---

## Aprobaciones requeridas del usuario (fuera del alcance de los agentes)

| # | Acción | Por qué |
|---|---|---|
| A1 | `system_config.photo_limits.max_count = 3 → 2` en **local** — comandos exactos: <br>`docker exec -i supabase_db_gota psql -U postgres -d postgres -c "SELECT value FROM public.system_config WHERE key='photo_limits';"` (antes) <br>`docker exec -i supabase_db_gota psql -U postgres -d postgres -c "UPDATE public.system_config SET value = jsonb_set(value, '{max_count}', '2') WHERE key='photo_limits';"` <br>y repetir el `SELECT` para confirmar | Es la autoridad del límite: `create_leak_report` rechaza fuera de `1..max_count` (`migrations/20260913000023:128-134`). Mientras el servidor siga en 3, cliente (2) y servidor (3) quedan desalineados: la app no ofrece una tercera foto, pero la RPC la aceptaría. |
| A2 | Aplicar lo mismo al cloud piloto `eghphmugrrbvbvodhasq` **solo** con `npx supabase db query --linked -f "<archivo .sql con el UPDATE>"` | **Prohibido `npx supabase db push`**: el remoto no tiene historial de migraciones y re-aplicaría todas las locales. |
| A3 | Decidir y ejecutar el destino de la rama: **`fix/map-r5-r6` → `main`**, y reconstruir el **APK release** desde esa rama con los `--dart-define` de piloto | La auditoría RC (veredicto `NOT READY`) determinó que el gate de piloto está bloqueado por esto: el `app-release.apk` del 20-sep **no contiene el Home nuevo** y `main` sirve el Home anterior. Ya no es sólo una preferencia de orden: es la acción que desbloquea el gate de build. |
| A4 | QA en **dispositivo físico** para los hallazgos 2 y 1 | Existe uno (Samsung SM-A245M, Android 16, serial `R58W709201M`, usado por la auditoría RC) pero **hoy está desconectado** (`adb devices` vacío). Reconectarlo habilita: (a) reproducir o descartar el cierre de foto, (b) medir la cadencia real de `onCameraIdle`. Sin device, esos puntos quedan `NOT VERIFIED`. |
| A5 | Medir la cadencia real de `onCameraIdle` en device → decidir si hace falta debounce del bbox | El debounce quedó **fuera** de esta tanda (ver prompt 2, C5): su intervalo es un parámetro que no se inventa sin dato de dispositivo. |
| A6 | Limpieza de datos de prueba del piloto y anónimos residuales del Docker local | Lo reporta la RC (INFO): 1 reporte, 2 eventos de agua, 2 notificaciones y 1 fila de `notification_preferences` escribidos con autorización, más 3 usuarios anónimos de las suites E2E. Requiere service-role; no afecta a los prompts. |

---

## Gates comunes a todos los prompts

- **Baseline ya medido** por la auditoría RC sobre **este mismo commit** (`525725c`):
  `flutter analyze` → *No issues*; `flutter test` → **189/189 PASS**; SQL 9/9; E2E 6/6
  (fuente: `docs/audits/2026-09-22_final_rc_pilot_readiness.md`). Se adopta como gate de partida; si
  se quiere firma propia, re-ejecutar antes de delegar (es barato y no toca código).
- **Al terminar:** `flutter analyze` sin issues nuevos y `flutter test` en verde, con los tests nuevos
  ejecutados y su salida pegada. Un test que no se puede ejecutar se declara `NOT RUN`, no se omite.
- **Nunca** exponer secretos. **Nunca** commit, stage, push, checkout ni migraciones.
- **No tocar** `main`, ni `.claude/worktrees/agent-a429749783d7a8538` (worktree paralelo con 96
  archivos propios y base vieja; no es baseline).
- **No debilitar tests**: no borrar, no `skip`, no cambiar aserciones a la ligera. Si un cambio
  invalida una aserción existente, se justifica y se actualiza (los 3 casos están identificados abajo).
- Evidencia obligatoria en la respuesta final:
  `STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(ninguno) / BLOCKER`.

---
---

# PROMPT 1 — HALLAZGO 2 · CIERRES AL TOMAR/SELECCIONAR FOTO

**Clasificación:** BETA FIX *(declarado BLOCKER por el diagnóstico; la auditoría RC **no lo reprodujo**
en device con cámara y galería reales → baja a BETA FIX y **escala a BLOCKER si se reproduce**;
requiere A4)* · **Modelo sugerido:** Sonnet · **Turnos:** 30-40
**Base:** `fix/map-r5-r6` @ `525725c` · **Rama de trabajo:** la actual (no cambiar de rama, no commitear)

### Objetivo

Que el flujo de reporte **no se cierre** al tomar una foto con la cámara ni al elegirla de la
galería, y que el límite de fotos del cliente sea **2** (la calidad ya es estándar y no se toca).

### Causa raíz aceptada

`CONFIRMADO` (parcial) + `HIPÓTESIS`:

- `leak_report_controller.dart:307-314` captura con `on Exception`, que en Dart **no** atrapa `Error`
  ni fallos que escalan fuera de la jerarquía `Exception`. Si el plugin nativo
  (`FlutterImageCompress`) falla o el proceso muere, **nada** en Dart lo contiene.
- `photo_service.dart:62-67` llama `FlutterImageCompress.compressAndGetFile` **sin try/catch**: una
  excepción de plataforma sube por `prepareFromFile` hacia el controller.
- `photo_service.dart:33-39` ya limita la selección (`imageQuality: 80`, `maxWidth/maxHeight: 1920`),
  pero luego se hace un **segundo** decodificado nativo completo en `photo_service.dart:62` antes de
  reencodear: es el momento de mayor presión de memoria del flujo.
- `HIPÓTESIS` no confirmable sin device: el cierre puede ser muerte de proceso / OOM nativo
  (no aparece como excepción de Dart). El prompt **no debe prometer** que el cierre desaparece: debe
  eliminar las vías de fallo controlables y dejar evidencia para diagnosticar en device.

**Evidencia de dispositivo contraria (importante):** la auditoría RC ejecutó el flujo real en un
Samsung SM-A245M (Android 16) — permiso GPS, reverse-geocode, **foto presente** y reporte persistido en
el piloto — **sin observar el cierre** (`docs/audits/2026-09-22_final_rc_pilot_readiness.md`, LEAK_REPORT
y BLOCKER: *"1 declarado por el equipo y no reproducido"*). Consecuencia práctica: este prompt se
justifica por (a) el hueco de código verificable (ninguna vía de `Error`/nativo está contenida) y
(b) la **regla de producto de 2 fotos**, que es independiente del crash. Si al reconectar el device
(A4) el cierre no se reproduce, el fix sigue valiendo como blindaje + regla; si se reproduce, se
escala a BLOCKER y se documenta el log.

### Archivos que SÍ se pueden tocar

- `lib/features/leaks/data/photo_service.dart`
- `lib/features/leaks/data/photo_limits.dart`
- `lib/features/leaks/presentation/leak_report_controller.dart` (sólo el bloque `addPhoto`)
- `test/features/leaks/photo_limits_test.dart` (sólo la aserción de `:85`)
- `test/features/leaks/leak_report_flow_test.dart` (sólo agregar casos)
- `test/features/leaks/photo_service_test.dart` (archivo nuevo)

### Archivos PROHIBIDOS

`supabase/**` (RPC, migraciones, `system_config`), `android/**`, todo `lib/` fuera de la lista de
arriba, cualquier otro test, `main`, el worktree paralelo.

### Contrato explícito

**C0 · Punto de inyección para el test (seam) — obligatorio.**
Hoy `addPhoto` instancia el servicio a mano (`leak_report_controller.dart:293`:
`final service = ImagePickerPhotoService();`), lo que hace **imposible** testear la ruta de error sin
el plugin real. Agregá en `photo_service.dart`:

```dart
final photoServiceProvider = Provider<PhotoService>((ref) => ImagePickerPhotoService());
```

(import `package:flutter_riverpod/flutter_riverpod.dart`) y en `addPhoto` reemplazá la instanciación
por `final service = ref.read(photoServiceProvider);`. Sin esto, el test de mutación del catch no se
puede escribir.

**C1 · Límite del cliente a 2.**
`photo_limits.dart:11` → `const kReportPhotoMaxCount = 2;`
El comentario del archivo debe seguir diciendo que la autoridad es `system_config.photo_limits`, y
agregar: *"el dueño del producto ajusta `max_count` a 2 en la BD por separado; esta constante no
puede quedar por encima del valor del servidor"*.
**No** se toca la RPC ni la BD.

**C2 · `addPhoto` captura todo.**
En `leak_report_controller.dart:286-316`, mantener el orden de los handlers específicos
(`PhotoPickCanceledException` → silencio; `PhotoValidationException` → `message`; `LeakFlowException`
→ `message`) y reemplazar el último `on Exception` por `catch (error, stackTrace)` **que captura
`Object`**. Debe:
- asignar el mismo mensaje tipado que hoy (`'No pudimos procesar esa foto. Elige otra.'`),
- registrar el error crudo **sólo** con `debugPrint` bajo `if (kDebugMode)` (no exponer texto técnico
  en UI, no usar `print`),
- no re-lanzar.

**C3 · `prepareFromFile` no deja escapar fallos nativos.**
Envolver `FlutterImageCompress.compressAndGetFile` en `try/catch (Object)` y traducir cualquier fallo
(preservando el `null` actual) a `PhotoValidationException('No pudimos procesar esa foto. Elige otra.')`.
Si usás `debugPrint`/`kDebugMode` acá, agregá `import 'package:flutter/foundation.dart';` a
`photo_service.dart` (hoy no lo importa; en `leak_report_controller.dart` ya está en `:1`).
Mantener las validaciones existentes (existencia del archivo, formato, tamaño, resultado comprimido).

**C4 · Elegir UNA de estas dos mitigaciones de memoria, con verificación previa obligatoria.**
Antes de decidir, confirmá en el código instalado del plugin la semántica de los parámetros — no la
inventes. Fuente: `$LOCALAPPDATA/Pub/Cache/hosted/pub.dev/flutter_image_compress-<versión>/`
(README, secciones *minWidth and minHeight* e *inSampleSize*) y
`image_picker_android-0.8.13+23` para saber si `imageQuality`/`maxWidth` ya reencodan la imagen.

- **Opción A (preferida si se verifica):** el picker ya entrega un JPEG reencodado bajo presupuesto →
  **no hacer un segundo pase** cuando el archivo elegido ya es `.jpg`/`.jpeg` y su tamaño es
  `<= 1.5 MB`; usar `compressedPath = path`. **Condición:** el segundo pase hoy existe también para
  eliminar EXIF (privacidad: `photo_service.dart:12-15`). Si la verificación **no** demuestra que el
  picker elimina EXIF, **no aplicar A**.
- **Opción B (si A no se puede verificar):** conservar el pase, pero declarar explícitamente los
  parámetros de escalado (`minWidth`/`minHeight`) en lugar de depender de los defaults, y documentos
  en el comentario del método cuál es el tamaño de salida esperado para una foto de 12 MP y por qué
  (el README define `minWidth`/`minHeight` como **límites inferiores** de escalado: 4000×2000 con
  1920×1080 sale 2160×1080).

Dejá en el resumen cuál opción aplicaste **y la evidencia** (ruta del archivo leído + la cita).
Si ninguna se puede verificar, aplicá C1+C2+C3 y reportá C4 como `BLOQUEADO POR VERIFICACIÓN`.

**C5 · Calidad: NO se toca.** `imageQuality: 80`, `quality: 82`, `maxWidth/maxHeight: 1920` ya son
calidad estándar (regla del producto: básica/estándar, sin alta resolución).

### Diff conceptual

```diff
# photo_limits.dart
-const kReportPhotoMaxCount = 3;
+const kReportPhotoMaxCount = 2;

# photo_service.dart (nuevo, al final)
+final photoServiceProvider = Provider<PhotoService>(
+  (ref) => ImagePickerPhotoService(),
+);

# leak_report_controller.dart (addPhoto)
-    final service = ImagePickerPhotoService();
+    final service = ref.read(photoServiceProvider);
     ...
-    } on Exception {
+    } catch (error, stackTrace) {
+      if (kDebugMode) debugPrint('addPhoto falló: $error\n$stackTrace');
       state = state.copyWith(
         message: const PhotoValidationException(
           'No pudimos procesar esa foto. Elige otra.',
         ).userMessage,
       );

# photo_service.dart (prepareFromFile)
-    final compressed = await FlutterImageCompress.compressAndGetFile(...);
+    XFile? compressed;
+    try {
+      compressed = await FlutterImageCompress.compressAndGetFile(...);
+    } catch (error, stackTrace) {
+      if (kDebugMode) debugPrint('compressAndGetFile falló: $error');
+      throw const PhotoValidationException('No pudimos procesar esa foto. Elige otra.');
+    }
```

### Criterios de aceptación

1. `kReportPhotoMaxCount == 2` y el flujo de UI no permite agregar una tercera foto
   (`addPhoto` corta con el mensaje existente `'Ya tienes el máximo de 2 fotos.'`).
2. Ningún camino de `addPhoto` puede terminar en una excepción no controlada: un fallo del picker,
   del sistema de archivos o del compresor produce banner tipado, no crash.
3. `prepareFromFile` con path inexistente → `PhotoValidationException` (comportamiento actual, sin
   regresión).
4. `flutter analyze` sin issues nuevos; suite completa en verde.

### Tests obligatorios

En `test/features/leaks/photo_limits_test.dart` — **actualizar** `:85`
(`expect(kReportPhotoMaxCount, 3)` → `2`; la aserción de `kReportPhotoMaxBytes` se mantiene) y
actualizar el comentario que referencia la migración 00009 para que diga que el valor del servidor se
ajusta por separado. **No borrar el test.**

Nuevos (mutation control obligatorio: cada uno debe fallar si se revierte su fix):
- `photo_service_test.dart`: `prepareFromFile` con un path inexistente lanza `PhotoValidationException`;
  con extensión no permitida lanza `PhotoValidationException`; con un archivo de 0 bytes lanza
  `PhotoValidationException`. (No mockear el compresor nativo: cubrir sólo las ramas que no lo llaman.)
- `leak_report_flow_test.dart`: `agregar foto cuando el servicio lanza Error no cierra el flujo y
  muestra banner` — con `photoServiceProvider.overrideWithValue(_ExplodingPhotoService())` (un fake
  cuyo `pickAndPrepare` lance un `Error`, p. ej. `StateError`), verificar que el estado queda con
  `message` y que nada se propaga. **(Este test es imposible hoy: el seam C0 es su requisito.)**
- `leak_report_flow_test.dart`: `el máximo de fotos es 2` — agregar 2 fotos preparadas y verificar que
  la tercera es rechazada con el mensaje del contrato.

Qué **no** se puede mockear ni debe simularse: la cámara/galería del sistema, el proceso nativo de
compresión y el OOM. Esos quedan como `NOT VERIFIED` en device.

### Fuera de alcance

Cambiar la RPC `create_leak_report` o `system_config` (A1); rediseñar la estrategia de subida a
Storage; añadir dependencias nuevas; tocar `image_picker` en `AndroidManifest`/Gradle; cambiar la
calidad de compresión; tocar otros flujos del reporte.

### Rollback

Revertir los 3 hunks de `lib/` y las aserciones actualizadas de `photo_limits_test.dart`. Ningún
cambio de datos ni de infraestructura.

### Evidencia a devolver

```
STATUS: ...
CAMBIOS: <archivo:línea por hunk>
ANALYZE: <salida o resumen + conteo>
TESTS: <comando + resultado, con los tests nuevos nombrados>
OPCIÓN C4: <A | B | BLOQUEADO POR VERIFICACIÓN> + evidencia de la lectura del plugin
ARCHIVOS: <lista>
COMMIT: ninguno
BLOCKER: <o NINGUNO>
```

---
---

# PROMPT 2 — HALLAZGO 1 · MAPA: SALTOS Y "SIN FUGAS PARA MOSTRAR" EN PAN/ZOOM

**Clasificación:** BETA FIX · **Modelo sugerido:** Sonnet · **Turnos:** 35-45
**Base:** `fix/map-r5-r6` @ `525725c` · **Rama de trabajo:** la actual (no commitear)

### Objetivo

Que durante un pan o un zoom el mapa **nunca** se desmonte ni pierda fluidez, y que el mensaje
"Sin fugas para mostrar" sólo aparezca cuando la consulta terminó y el área **realmente** está vacía.

### Causa raíz aceptada

`CONFIRMADO` — dos mecanismos que se suman:

1. **Desmonte de MapLibre.** `map_screen.dart:86-99`: en modo mapa, cuando `reports.isEmpty` la rama
   `data:` devuelve `_MapEmptyView` en lugar de `_MapViewContent`. Son widgets mutuamente excluyentes:
   Flutter desmonta el árbol de MapLibre (contexto OpenGL, estilo, cámara) cada vez que el viewport
   cae sobre una zona sin reportes — situación normal durante cualquier pan. Además programa
   `clearBounds()` en post-frame, que cambia `mapFilterProvider` y lanza **otra** consulta sin bbox.
2. **Estado vacío con datos rancios.** `map_screen.dart:74` usa `skipLoadingOnReload: true`, que
   durante un refetch muestra el **último resultado completado**. Si ese resultado era `[]`, el texto
   se pinta durante toda la latencia de la consulta en vuelo (de ahí que el síntoma sea "temporal").

`map_providers.dart:45-58` (`setBounds`) ya descarta cambios idénticos pero **no** hay debounce:
cada `onCameraIdle` (`gota_map_view.dart:173-189`) dispara una consulta nueva.

**Evidencia de dispositivo (auditoría RC, Samsung SM-A245M / Android 16):**

- Mecanismo (a) **REPRODUCIDO en device**: con el filtro "Mi sector" y resultado vacío, el mapa se
  desmonta — píxeles de mapa 506.438 → 3.146 (pantalla 95 % blanca) — y se recrea al volver a "Todas".
  Eso convierte esta corrección en la de **mayor respaldo empírico** de las cinco.
- Mecanismo (b) **NO reproducido**: dos capturas separadas 10 s tras un pan resultaron
  byte-idénticas ("sin blink/reset tras pan"). El flash del mensaje durante el refetch no se observó en
  device; la guarda C6 se mantiene como corrección de diseño (es el mecanismo que explicaría el "aparece
  temporalmente" del reporte), pero **debe declararse como no respaldada por reproducción** en el
  reporte final, no como causa confirmada en hardware.

### Archivos que SÍ se pueden tocar

- `lib/features/map/presentation/map_screen.dart`
- `test/features/map/map_screen_test.dart` (agregar casos; no romper los existentes)

### Archivos PROHIBIDOS

`lib/features/map/presentation/widgets/gota_map_view.dart`, `map/presentation/map_providers.dart`,
`map/domain/**`, `supabase/**`, el resto de `lib/`, `main`, el worktree paralelo.
La corrección es **exclusivamente estructural en `map_screen.dart`** (C5): nada de debounce, timers ni
cambios en los providers.

### Contrato explícito

**C1 · En modo mapa, el mapa siempre está montado.**
En `MapScreen.build`, la rama `data:` **no** puede devolver otro widget en lugar de `_MapViewContent`
cuando `reports.isEmpty` y `viewMode == MapViewMode.map`. El estado vacío pasa a ser un **overlay**
(`Positioned`/`Align` dentro del `Stack` existente) que reutiliza la copy y el **mismo key
`mapEmptyStateKey`** de `_MapEmptyView` (`map_screen.dart:707`) y su texto
`'Sin fugas para mostrar'` con la ayuda `'Cambia los filtros o amplía el área para ver más resultados.'`.
El overlay debe ser no intrusivo (no bloquea gestos del mapa: no usar `AbsorbPointer`/`GestureDetector`
que capturen el pan).

**C2 · Excepción legítima: "Mi sector" sin sector elegido.**
Cuando `filterType == MapFilterType.mySector && selectedSectorId == null`, se conserva el
comportamiento actual de `_MapEmptyView` (`'Configura tu sector'`, `map_screen.dart:702-734`) como
vista completa — ahí no hay nada que panear. **Ese caso sigue montando la vista de guía, no el mapa.**

**C3 · Modo lista sin cambios de comportamiento.** `MapViewMode.list` con `reports.isEmpty` puede
seguir mostrando la vista vacía actual.

**C4 · Se elimina el `clearBounds()` del estado vacío.** Con el mapa siempre montado, el usuario
puede ampliar el área con un gesto y el bbox dejará de limitar en el siguiente `onCameraIdle`; el
`addPostFrameCallback` que limpia bounds sale del flujo de render. **`clearBounds()` no se borra de
`map_providers.dart`** (sigue siendo API válida y testeada), sólo se deja de invocar desde el render.

**C5 · NO se agrega debounce en esta tanda.**
Medir primero la cadencia real de `onCameraIdle` en dispositivo (hoy no hay device) y decidir después
con ese dato: el intervalo de un debounce es un parámetro que no se inventa (queda como **A5**). Por
eso este prompt **no** toca `gota_map_view.dart` ni `map_providers.dart`: la corrección es
exclusivamente estructural, en `map_screen.dart`. `setBounds` (`map_providers.dart:45-58`) conserva su
descarte por igualdad exacta y `clearBounds()` sigue existiendo como API (sólo deja de invocarse desde
el render, ver C4).

**C6 · El overlay no se muestra mientras hay una consulta en vuelo (cierra el síntoma reportado).**
Este punto es el que evita el "aparece temporalmente": el overlay se condiciona a que el provider
**no** esté cargando:

```dart
if (reports.isEmpty && !reportsAsync.isLoading && !_isMySectorWithoutSelection(filterState))
  const _MapEmptyOverlay(),
```

Sin esta condición queda el mecanismo (b) de la causa raíz: durante un refetch cuyo último resultado
fue `[]`, el overlay se pintaría durante toda la latencia de la red. Con `isLoading` como guarda, el
usuario ve el mapa montado y sin mensaje hasta que la consulta termina.

### Diff conceptual

```diff
# map_screen.dart — rama data:
   data: (reports) {
-    if (reports.isEmpty) {
-      WidgetsBinding.instance.addPostFrameCallback((_) {
-        ref.read(mapFilterProvider.notifier).clearBounds();
-      });
-      return _MapEmptyView(filterState: filterState);
-    }
     return switch (filterState.viewMode) {
       MapViewMode.map => Stack(children: [
         _MapViewContent(leaks: reports, ...),   // SIEMPRE montado
+        if (reports.isEmpty &&
+            !reportsAsync.isLoading &&            // C6: sin overlay durante el refetch
+            !_isMySectorWithoutSelection(filterState))
+          const _MapEmptyOverlay(),               // key: mapEmptyStateKey
         const _MapLegend(),
         ...
       ]),
       MapViewMode.list => reports.isEmpty
           ? _MapEmptyView(filterState: filterState)   // se conserva en lista
           : _MapListView(leaks: reports, ...),
     };
   }
```

### Criterios de aceptación

1. Con `reports == []` y `viewMode == map`: el contenedor del mapa **sigue montado** y el overlay
   vacío es visible.
2. Ningún render llama a `clearBounds()`.
3. Con `mySector` sin `selectedSectorId`: se ve `'Configura tu sector'` (comportamiento actual, ya
   cubierto por el test `:312-337`) y **no** se muestra el overlay de "Sin fugas".
4. Mientras una consulta está en vuelo (`reportsAsync.isLoading`), el overlay **no** se muestra: el
   mapa queda montado y sin mensaje (C6).
5. Filtros existentes (Todas/Activas/Resueltas/Mi sector/Recientes/Más validadas) y el toggle
   Mapa/Lista siguen funcionando; `flutter analyze` sin issues nuevos y suite en verde.

### Tests obligatorios (mutation control: cada uno debe fallar al revertir su fix)

En `test/features/map/map_screen_test.dart` (ya existen el helper `_pumpMapScreen`, el builder inyectable
`mapWidgetBuilderProvider.overrideWithValue(_testMapBuilder)` y las claves públicas
`gotaMapContainerKey` y `mapEmptyStateKey`, usadas hoy en `:250`, `:264` y `:225`):

- `estado vacío en modo mapa no desmonta el mapa`: con `reports: []`, afirmar
  `find.byKey(mapEmptyStateKey)` **y** `find.byKey(gotaMapContainerKey)` presentes a la vez. La clave es
  la **pública** `gotaMapContainerKey` (`gota_map_view.dart:11`, envuelve a cualquier builder inyectado),
  no la del builder de prueba. *(Este es el test que hoy falla: el mapa se desmonta.)*
- `el overlay vacío no se muestra con la consulta en vuelo`: con el repositorio falso devolviendo un
  `Future.delayed` y datos previos `[]` (usar un `pumpWidget` + `pump` sin `pumpAndSettle`), afirmar que
  `mapEmptyStateKey` **no** está presente mientras carga y que `gotaMapContainerKey` sí.
- `Mi sector sin selección muestra la guía y no el overlay vacío`.
- `el estado vacío no limpia los bounds`: montar con `reports: []` y afirmar que `mapFilterProvider`
  conserva los bounds que tenía (no pasa a `null`).
- **No** agregar tests de debounce (C5 lo deja fuera). Mantener sin cambios los tests existentes
  (`muestra estado vacío cuando no hay fugas`: 222, `muestra lista de fugas en modo mapa`: 240,
  `filtro Mi sector...`: 312); si alguno depende del desmonte, **actualizarlo con justificación**, no
  borrarlo.

No mockeable: MapLibre real (gestos, cámara, fluidez). Eso queda `NOT VERIFIED` sin device.

### Fuera de alcance

Rediseñar el estilo del mapa, cambiar `get_map_reports`/RPC, alterar filtros o su semántica, tocar
`gota_map_view.dart` o `map_providers.dart`, agregar debounce (queda como A5), cachear respuestas,
cambiar el `limit: 100`.

### Rollback

Revertir `map_screen.dart` (rama `data:` + overlay + guarda de carga) y los tests nuevos. Riesgo
contenido: el único cambio de estado observable es que ya no se limpian los bounds al quedar vacío.

### Evidencia a devolver

`STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(ninguno) / BLOCKER` + una línea indicando
dónde quedó la guarda `!reportsAsync.isLoading` y qué se hizo con el helper de "Mi sector".

---
---

# PROMPT 3 — HALLAZGO 3 · "CONTINUAR" DESHABILITADO CON VALORES PRESELECCIONADOS

**Clasificación:** BETA FIX · **Modelo sugerido:** Haiku · **Turnos:** 15-20
**Base:** `fix/map-r5-r6` @ `525725c` · **Rama de trabajo:** la actual (no commitear)

### Objetivo

Que cuando el GPS y el reverse geocode dejen municipio y sector preseleccionados, el usuario pueda
pulsar "Continuar" sin tener que cambiar y volver a elegir los listados a mano.

### Causa raíz aceptada

`CONFIRMADO`:

- `leak_report_controller.dart:176-181`: la sugerencia se guarda **sólo** en
  `suggestedMunicipalityId` / `suggestedSectorId`; el borrador (`draft.municipalityId`,
  `draft.sectorId`) queda en `null` por diseño explícito ("la preselección es solo informativa").
- `leak_report_screen.dart:705-709`: el botón "Continuar" se habilita **sólo** con
  `state.draft.municipalityId != null && state.draft.sectorId != null`.
- `leak_report_screen.dart:643-646`: el dropdown muestra `initialValue: effectiveMunicipalityId`
  (= borrador ?? sugerencia), pero `DropdownButtonFormField.initialValue` **no dispara `onChanged`**;
  por eso el valor se ve pero no se registra.

**Restricción crítica:** `goToNext()` no valida (`leak_report_controller.dart:383-392`) y el backend
lee del borrador (`leak_report_repository.dart:118-119` → `p_municipality_id` / `p_sector_id`).
Habilitar el botón sin escribir el borrador permitiría **enviar un reporte con municipio/sector
nulos**. La corrección debe cubrir ambos lados.

### Archivos que SÍ se pueden tocar

- `lib/features/leaks/presentation/leak_report_screen.dart` (sólo `DataStepView`)
- `test/features/leaks/leak_report_flow_test.dart` (agregar casos)

### Archivos PROHIBIDOS

`leak_report_controller.dart` (no se toca: la sugerencia sigue siendo informativa),
`leak_report_repository.dart`, `supabase/**`, cualquier otro archivo.

### Contrato explícito

**C1 · El botón se habilita con los valores efectivos.**
En `DataStepView`, la condición de `onPressed` pasa a usar los valores efectivos ya calculados en
`:572-586`:

```dart
final canContinue = effectiveMunicipalityId != null && effectiveSectorId != null;
...
onPressed: canContinue ? () => _continueWithEffectiveSelection(...) : null,
```

**C2 · Al pulsar, se escriben los valores efectivos en el borrador ANTES de avanzar.**

```dart
void _continueWithEffectiveSelection(...) {
  final controller = ref.read(leakReportProvider.notifier);
  if (state.draft.municipalityId == null && effectiveMunicipalityId != null) {
    controller.selectMunicipality(effectiveMunicipalityId);   // ojo: resetea sectorId a null
  }
  if (state.draft.sectorId == null && effectiveSectorId != null) {
    controller.selectSector(effectiveSectorId);                // DESPUÉS del municipio
  }
  controller.goToNext();
}
```

El orden importa: `selectMunicipality` limpia `sectorId` (`leak_report_controller.dart:358-364`), así
que el sector se escribe después. `selectSector` es `:370-371`.

**C3 · Los avisos "Sugerido según ubicación GPS" (`:662-671`, `:681`) siguen apareciendo** mientras el
valor sea la sugerencia (misma condición `isMunicipalitySuggested` / `isSectorSuggested`, sin cambios).

**C4 · Nada más cambia.** No se auto-avanza de paso, no se deshabilitan los listados, el usuario puede
seguir cambiando municipio y sector (y `selectMunicipality` sigue limpiando el sector al cambiar).

### Criterios de aceptación

1. Con sugerencia de municipio y sector presentes y borrador vacío: "Continuar" está **habilitado**.
2. Al pulsarlo, el borrador contiene el municipio y el sector sugeridos (verificado por el payload
   del repositorio: `p_municipality_id` y `p_sector_id` no nulos).
3. Sin sugerencia y sin selección manual: "Continuar" sigue **deshabilitado**.
4. Cambiar el municipio a mano limpia el sector y "Continuar" vuelve a deshabilitarse hasta elegir
   sector.
5. `flutter analyze` sin issues nuevos; suite en verde.

### Tests obligatorios (mutation control obligatorio)

En `test/features/leaks/leak_report_flow_test.dart`:

- `preselección GPS habilita Continuar`: montar con GPS + reverse geocode que devuelvan municipio y
  sector conocidos, afirmar que el botón está habilitado **sin** tocar los dropdowns.
  *(Hoy falla: el botón está deshabilitado.)*
- `Continuar con preselección llega al borrador`: pulsar y afirmar que el reporte se puede completar
  con municipio/sector no nulos (control de mutación: si se revierte C2, el envío queda con nulos y el
  test debe fallar).
- `sin sugerencia el botón sigue deshabilitado` (no regresión).
- Mantener los tests existentes de `leak_report_flow_test.dart` sin cambios.

### Fuera de alcance

Cambiar `_applyMunicipalitySuggestion` en el controller (variante alternativa descartada: escribir la
sugerencia en el borrador al aplicarla — altera el significado de "sugerido" y toca el controller);
tocar el paso de fotos o de ubicación; SQL.

### Rollback

Revertir `DataStepView` (condición del botón + helper de commit) y los tests nuevos.

### Evidencia a devolver

`STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(ninguno) / BLOCKER`

---
---

# PROMPT 4 — HALLAZGO 4 · "SECTOR DE INTERÉS" DESAPARECE OCASIONALMENTE

**Clasificación:** BETA FIX · **Modelo sugerido:** Sonnet · **Turnos:** 25-35
**Base:** `fix/map-r5-r6` @ `525725c` · **Rama de trabajo:** la actual (no commitear)

### Objetivo

Que el sector de interés del usuario no desaparezca de Ajustes mientras la app guarda preferencias, y
que ninguna operación de guardado pueda borrar el sector sin una acción explícita del usuario.

### Causa raíz aceptada

`CONFIRMADO` para el síntoma visual + `HIPÓTESIS` para la pérdida real:

- `notification_providers.dart:58-61`: `_save()` guarda el estado previo y pone
  `state = const AsyncValue.loading()` **en cualquier guardado** (incluido el toggle de notificaciones
  de agua, `:50-51`). `settings_screen.dart:92-93` reacciona a `loading:` con `LoadingView()` → el
  sector desaparece de la pantalla mientras dura el guardado. Con red lenta, el usuario lo ve vacío.
- `notification_providers.dart:63-70`: el sector que se envía es
  `sectorId ?? current?.preferredSectorId`, con `current = previousState.value`. Si se guarda
  **antes** de que `_load()` complete (`build()` devuelve `AsyncValue.loading()` en `:30-33` y lanza
  `_load` en microtask en `:31`), `current` es `null` → se envía `sectorId: null` **sin** que el
  usuario lo haya pedido: pérdida real y persistente de la preferencia.
- `settings_screen.dart:170-175`: al volver de `SectorSelectionScreen` se invalida
  `notificationPreferencesProvider` (provider distinto del controller: no es la causa del borrado,
  pero multiplica recargas; **no** forma parte de la corrección).

### Archivos que SÍ se pueden tocar

- `lib/features/notifications/presentation/notification_providers.dart` (sólo
  `NotificationPreferencesController`)
- `lib/features/notifications/presentation/settings_screen.dart` (sólo `_SectorCard` y, si hace falta,
  `_WaterNotificationsCard` en su consumo de `prefs.when`)
- `test/features/notifications/notifications_test.dart` (grupo `NotificationPreferencesController`)

### Archivos PROHIBIDOS

`supabase/**` (RPC de preferencias, RLS), `notification_repository.dart`, `sector_selection_screen.dart`,
`push_*`, el resto de `lib/`, `main`, el worktree paralelo.

### Contrato explícito

**C1 · Nunca enviar `null` por falta de dato — con guard que PUBLICA el error.**
En `_save()`, si el estado no tiene valor (`!state.hasValue`, es decir la carga inicial no terminó),
la operación **no puede** traducirse en `sectorId: null`. Comportamiento exigido:

- Si `clearSector == true` → `sectorId: null` (explícito del usuario, como hoy).
- **CORREGIDO EN LA v4 (ver `Registro de revisión — v4`):** el guard se evalúa **antes** de resolver el
  valor, con la condición `!clearSector && !previousState.hasValue`. Es decir: **cualquier** guardado sin
  carga previa se bloquea, incluido un `sectorId != null` explícito del usuario. El motivo verificado es
  que la regla original tenía un agujero destructivo: con `current == null`,
  `enabled = enabled ?? false` enviaría **`enabled: false`** apagando las notificaciones de agua que el
  usuario tenía encendidas, sin que lo haya pedido. Bloquear toda escritura sin valor previo evita esa
  escritura y el error tipado llega igual al usuario.
- Si `previousState.hasValue` y `sectorId != null` → ese valor.
- Si `previousState.hasValue` y `sectorId == null` y `!clearSector` → el sector previo
  (`current?.preferredSectorId`), como hoy.
- En el caso bloqueado, asignar
  `_saveError = StateError('Tus preferencias aún están cargando. Intenta de nuevo en un momento.')` y
  **cambiar el estado** (ver el porqué abajo), luego `return`.
- `enabled` mantiene su regla actual (`enabled ?? current?.waterNotificationsEnabled ?? false`) para no
  cambiar el comportamiento del toggle.

**Por qué el guard DEBE publicar un estado y no basta con `return`:** los tres llamadores reaccionan
sólo cuando el estado **deja** de estar en `AsyncLoading`:

- `sector_selection_screen.dart:34-52`: `ref.listen(..., (previous, next) { if (!_saving || next is AsyncLoading) return; ... })`
  y su `_selectSector` pone `_saving = true` (`:25-30`). Con un `return` que no cambie el estado, el
  listener **nunca dispara**, `_saving` queda `true` para siempre y la pantalla se queda con el spinner
  sin hacer pop ni mostrar el error.
- `settings_screen.dart:240-257` (`_WaterNotificationsCard`) y `:199-210` (`_confirmClear`) tienen el
  mismo patrón (`if (!_toggling || next is AsyncLoading) return;`).

Además, **re-emitir el mismo estado no sirve**: `AsyncValue` compara por valor y Riverpod no notifica
si el valor no cambia. Publicá un estado distinto y honesto:

```dart
_saveError = StateError('Tus preferencias aún están cargando. Intenta de nuevo en un momento.');
state = AsyncValue.error(_saveError!, StackTrace.current);
return;
```

Cualquier `AsyncError` nuevo es `!=` al `AsyncLoading` previo → los listeners disparan, `_saving` se
libera y el SnackBar con `saveError` aparece (los tres llamadores ya lo hacen). El `_load()` que sigue
en vuelo termina después y deja `AsyncValue.data`, limpiando el error. **No** toques
`sector_selection_screen.dart` ni los llamadores: si el guard está bien hecho, no hace falta.

**C2 · El guardado no oculta el valor.** **SUPERADO POR EL PROMPT 6 (v4):** la implementación de la
tanda 1 cumplió este punto con `copyWithPrevious`, que en riverpod 3.4.3 está anotado `@internal`
(`riverpod-3.4.3/lib/src/core/async_value.dart:630`) y obligó a un `// ignore:
invalid_use_of_internal_member` en código de producción. El prompt 6
(`docs/PROMPT_6_IS_SAVING_2026-09-23.md`) sustituye esa vía por un flag `_isSaving` explícito. Lo de
abajo queda como registro de lo ejecutado en la tanda 1.
`state = const AsyncValue.loading()` pasa a conservar el dato previo **con `isRefresh`**:
`state = const AsyncValue<NotificationPreferences?>.loading().copyWithPrevious(previousState, isRefresh: true);`

Con `isRefresh: true`, `AsyncValue.when` (cuyo `skipLoadingOnRefresh` ya es `true` por defecto) sigue
renderizando la rama `data` mientras dura el guardado: **`_SectorCard` deja de mostrar `LoadingView()` sin
tocar `settings_screen.dart`**. No agregues `skipLoadingOnReload` ni `skipLoadingOnRefresh` explícitos: no
hacen falta y amplían el cambio sin motivo.

Verificá que **no** se rompe lo que ya depende de `isLoading`:

- `_WaterNotificationsCard` (`settings_screen.dart:236-241`) calcula `saving = prefs.isLoading` y usa
  `onChanged: saving || _toggling ? null : _toggle`. Con `copyWithPrevious`, `isLoading` sigue siendo
  `true` durante el guardado → el switch permanece deshabilitado: **comportamiento esperado, no cambiar**.
- Su `ref.listen` (`:240-257`) descarta `next is AsyncLoading` y actúa al llegar el `data` final →
  sigue funcionando igual (el estado final tras el guardado es `AsyncValue.data`).
- El `catch` de `:73-80` se mantiene: si falla, vuelve al estado previo cuando había valor.

Si al ejecutar los tests alguna de esas dos piezas cambia de comportamiento, **reportalo como blocker**
en lugar de ajustar `settings_screen.dart` por tu cuenta.

**C3 · Lo que NO cambia.** El contrato de 0..1 sectores, el toggle de notificaciones, el botón
"Quitar sector" con confirmación, `clearSector`, la invalidación de
`notificationPreferencesProvider` en `:72` y el error tipado en `saveError`.

**C4 · Eliminación de una recarga redundante: opcional.** Si al terminar C1-C2 el agente concluye con
evidencia que `ref.invalidate(notificationPreferencesProvider)` en `settings_screen.dart:174` no
aporta nada (el controller ya invalida en `:72`), puede quitarlo **diciéndolo** en el reporte. Si hay
duda, **no** se toca.

### Criterios de aceptación

1. Guardar el toggle de notificaciones de agua **no** oculta el sector en pantalla.
2. Llamar a `selectSector('x')` / `setWaterNotificationsEnabled(true)` antes de que la carga inicial
   complete **no** produce ninguna escritura con `sectorId: null`.
3. `clearSector()` sigue enviando `(null, enabled actual)`.
4. Si la lectura de preferencias falla durante un guardado sin valor previo, `saveError` queda
   expuesto y no se escribe nada.
5. `flutter analyze` sin issues nuevos; suite en verde.

### Tests obligatorios (mutation control obligatorio)

Grupo `NotificationPreferencesController` de `test/features/notifications/notifications_test.dart`
(ya existe `_FakeNotificationRepository` con `savedPreferences` y `preferencesError`):

- `guardar antes de que la carga complete no borra el sector`: preferencias con
  `preferredSectorId: 'sector-x'` en el repo falso, invocar `setWaterNotificationsEnabled(true)`
  **sin** esperar la carga, y afirmar que `savedPreferences` no contiene ningún par con `null` y que el
  estado final conserva `'sector-x'`. *(Hoy falla: se envía `(null, true)`.)*
- `el guard publica el estado y libera a los llamadores` — con la carga inicial sin resolver, invocar
  `selectSector('x')` y afirmar que el estado **cambió** (dejó de ser `AsyncLoading`) y que
  `saveError is StateError`. Sin esta aserción, el guard puede pasar los tests del controller y dejar
  la pantalla de selección colgada (ver C1). Mutation control: si se revierte a un `return` sin cambio
  de estado, este test debe fallar.
- `el guardado conserva el valor previo en el estado` (`copyWithPrevious`: `isRefreshing`/`hasValue`
  verdadero durante el guardado).
- Test de widget en `settings_screen`: `el sector sigue visible mientras se guarda` — con un repo
  falso que retrase `savePreferences`, disparar el toggle y afirmar que el nombre del sector sigue
  presente y que no aparece `LoadingView`.
- Mantener los dos tests existentes del grupo (`:313` y `:344`) sin cambios.

### Fuera de alcance

Cambiar el modelo `NotificationPreferences`, la RPC de preferencias, la pantalla de selección de
sector, el orden de navegación, o el comportamiento de la bandeja de notificaciones
(`NotificationInboxController`).

### Rollback

Revertir los hunks de `_save()` y el `skipLoadingOnReload` en `settings_screen.dart`; los tests nuevos
se retiran con ellos.

### Evidencia a devolver

`STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(ninguno) / BLOCKER` + si se aplicó C4.

---
---

# PROMPT 5 — HALLAZGO 5 · AJUSTES UX (TEXTO Y ORDEN DE WIDGETS)

**Clasificación:** POLISH · **Modelo sugerido:** Haiku · **Turnos:** 15-25
**Base:** `fix/map-r5-r6` @ `525725c` · **Rama de trabajo:** la actual (no commitear)

### Objetivo

Cinco ajustes de copy/layout pedidos por el producto, sin ningún cambio de lógica.

### Causa raíz aceptada

`CONFIRMADO` — son textos literales y un orden de widgets, localizados en el código:

| # | Ubicación | Qué es |
|---|---|---|
| 5.1 | `home_screen.dart:386-393` | `Text('Resumen de hoy')` + su `SizedBox(height: AppSpacing.md)` |
| 5.2 | `water_screen.dart:128-131` | `Text(WaterCopy.summaryTitle)` (= `'Resumen'`, `water_copy.dart:6`) + `SizedBox` |
| 5.3 | `leak_report_screen.dart:137-142` | leyenda bajo `'¿Dónde está la fuga?'` (`:133-136`) |
| 5.4 | `leak_report_screen.dart:600-632` | tarjeta de referencia de ubicación en `DataStepView`, hoy **antes** del dropdown de municipio (`:633`) |
| 5.5 | `leak_report_controller.dart:446-447` | `message: '¡Reporte enviado! ... activa (ID $reportId).'` — expone el GUID |

### Archivos que SÍ se pueden tocar

- `lib/features/home/presentation/home_screen.dart`
- `lib/features/water/presentation/water_screen.dart`
- `lib/features/water/presentation/water_copy.dart`
- `lib/features/leaks/presentation/leak_report_screen.dart` (sólo `LocationStepView` y `DataStepView`)
- `lib/features/leaks/presentation/leak_report_controller.dart` (sólo el `message` de `ReportCreated`)
- `test/features/home/community_summary_card_test.dart`
- `test/features/water/water_screen_test.dart`

### Archivos PROHIBIDOS

`supabase/**`, cualquier otro `lib/`, cualquier otro test, `main`, el worktree paralelo.

### Contrato explícito

**C1 (5.1).** Eliminar el `Text('Resumen de hoy')` y el `SizedBox(height: AppSpacing.md)` que le sigue.
La tarjeta de resumen y su contenido **no** se tocan.

**C2 (5.2).** Eliminar el `Text(WaterCopy.summaryTitle)` y su `SizedBox` de `water_screen.dart:128-131`.
`_StatisticsCard` y el encabezado del historial (`:135-138`) quedan como están: verificar que el layout
no queda con espaciado doble (ajustar sólo el `SizedBox` que quede huérfano, sin agregar otros).
`WaterCopy.summaryTitle` queda sin uso: **eliminar la constante** de `water_copy.dart:6` en el mismo
cambio para no dejar código muerto.

**C3 (5.3).** Eliminar el `const Text('Usa tu GPS o indica la zona manualmente...')` (`:138-142`) y el
`SizedBox(height: 4)` de `:137`. El título `'¿Dónde está la fuga?'` se mantiene.

**C4 (5.4).** Mover el bloque `if (state.locationSuggestion?.displayText != null) [...Card...]`
(`:600-632`) a **después** del bloque `if (effectiveMunicipalityId != null) _SectorsDropdown(...)`
(`:676-682`) y de su `SizedBox(height: 12)` (`:683`), dejándolo antes del `TextField` de descripción
(`:684`). Mismo widget, misma Card, mismo `Icon` y mismo `displayText`: sólo cambia el orden. No
introducir `null`-safety nueva: el bloque ya está condicionado.

**C5 (5.5).** En `leak_report_controller.dart:446-447`, el mensaje pasa a
`'¡Reporte enviado! La fuga quedó registrada como activa.'` (sin `(ID $reportId)`).
**El `reportId` se conserva en el estado** (`outcome`/`ReportCreated`): no se toca el modelo ni la
navegación. Verificar que ningún otro texto de la pantalla de resultado imprima el id; si lo hace,
quitarlo también y decirlo.

### Criterios de aceptación

1. Home: no aparece el texto `Resumen de hoy`; la tarjeta de resumen sigue renderizando sus datos.
2. Agua: no aparece el texto `Resumen`; la tarjeta de estadísticas y la lista del historial siguen
   visibles.
3. Reportar (paso ubicación): no hay leyenda bajo `¿Dónde está la fuga?`.
4. Reportar (paso datos): la tarjeta de ubicación aparece **después** del dropdown de sector y antes de
   la descripción.
5. Confirmación de reporte: el mensaje no contiene el id ni un UUID.
6. `flutter analyze` sin issues nuevos (incluida la constante eliminada); suite en verde.

### Tests a actualizar (justificación obligatoria en el reporte)

- `test/features/home/community_summary_card_test.dart:192, 206, 224, 232` afirman
  `find.text('Resumen de hoy')`. **Actualizar**: cambiar esas aserciones por
  `expect(find.text('Resumen de hoy'), findsNothing)` y **conservar** las aserciones de contenido de
  cada test. No borrar ningún test.
- `test/features/water/water_screen_test.dart:85` afirma `find.text(WaterCopy.summaryTitle)`. Al
  eliminar la constante, la aserción pasa a `find.text('Resumen')` con `findsNothing` (mutation control
  del cambio).

Nuevos (mutation control):
- `Reportar: la leyenda bajo "¿Dónde está la fuga?" no se muestra`.
- `Reportar: la tarjeta de ubicación aparece después del dropdown de sector` (comparar orden con
  `tester.getTopLeft` de ambos, o con el orden del árbol con `find.byType`/keys existentes).
- `Confirmación de reporte: el mensaje no expone el id` (el mensaje no debe contener el id del
  outcome).

### Fuera de alcance

Cambiar copy de otros textos, rediseñar la tarjeta de resumen o de estadísticas, tocar el Design
System (`AppSpacing`, `AppColors`), reordenar cualquier otro bloque, cambiar el flujo del reporte.

### Rollback

Revertir los 5 hunks (4 de copy/orden + 1 de constante) y las aserciones actualizadas. Riesgo nulo de
datos.

### Evidencia a devolver

`STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(ninguno) / BLOCKER` + la lista de tests
actualizados con su justificación.

---

## Plan de verificación (lo ejecuta el orquestador, no el agente que implementó)

| Prompt | Verificación independiente | Riesgo que no se puede cubrir acá |
|---|---|---|
| 1 | `flutter analyze` + `flutter test` ejecutados por el orquestador; lectura del diff de `addPhoto`/`prepareFromFile`; `grep kReportPhotoMaxCount` = 2 y `grep "kReportPhotoMaxCount, 3"` = 0; confirmar que `addPhoto` ya no instancia `ImagePickerPhotoService()` a mano | Cierre real en Android (OOM nativo, cámara del sistema): `NOT VERIFIED` sin device |
| 2 | Suite de map al verde; leer el diff de la rama `data:`; `grep clearBounds` = 0 en `map_screen.dart`; confirmar el overlay con `mapEmptyStateKey` y la guarda `isLoading` | Fluidez real del mapa, gestos y cadencia de `onCameraIdle`: `NOT VERIFIED` sin device |
| 3 | Test de preselección ejecutado; leer el helper de commit y confirmar el orden municipio→sector | Ninguno relevante |
| 4 | Tests de carrera ejecutados; `grep` de `copyWithPrevious` en `_save()`; confirmar por diff que `settings_screen.dart` y `sector_selection_screen.dart` **no** cambiaron; prueba read-only contra `notification_preferences` si hace falta | Persistencia real entre sesiones y arranque en frío: `NOT VERIFIED` sin device |
| 5 | `flutter test` en verde; `grep` de los 5 textos eliminados = 0 resultados; verificación de que el GUID no aparece en ningún texto de UI | Aspecto visual final: `NOT VERIFIED` sin device |

**Regla de oro:** "no probado" nunca es "PASS". Lo que dependa del dispositivo se documenta como
`NOT VERIFIED`, no se inventa.

---

## Anexo — hallazgos de la auditoría RC fuera de los 5 del brief

La auditoría RC (`docs/audits/2026-09-22_final_rc_pilot_readiness.md`, veredicto **NOT READY**) dejó 4
BETA FIX y 5 POLISH. Estos **no** forman parte del encargo original; quedan fuera de alcance hasta que
lo apruebes. Verifiqué cada uno en el código del baseline:

| Origen RC | Verificación propia | Estado |
|---|---|---|
| APK release obsoleto (20-sep, sin el Home nuevo) | No re-verificado por mí (artefacto de build); la RC lo probó por `strings` en `libapp.so` | **Operacional** → aprobación A3 |
| Home de piloto no mergeado (`main` sirve el anterior) | Verificado: `main` no contiene `8a14443`/`67c06fd`/`295f77d` | **Operacional** → A3 |
| Refetch del viewport sin debounce | Verificado: `setBounds` sin debounce (`map_providers.dart:45-58`) | Ya cubierto por prompt 2 C5 + A5 |
| "Notificaciones de agua" activable **sin** sector de interés | Verificado: `_WaterNotificationsCard` (`settings_screen.dart:215-271`) sólo mira permisos y `waterNotificationsEnabled`; nunca consulta `preferredSectorId` | POLISH → candidato a prompt 6 |
| `Stepper` muestra "Continue"/"Cancel" en UI española | Verificado: `water_register_screen.dart:72-74` usa `Stepper` **sin** `controlsBuilder` (los textos por defecto son de Material) | POLISH → candidato a prompt 6 |
| El `Stepper` permite llegar a Resumen sin municipio/sector | Verificado **y matizado**: sí existe una guarda cliente en `water_register_controller.dart:97-105` que corta con `'Indica el municipio y el sector del evento.'` **sin llamar a la RPC** (la RC dice "el RPC lo rechaza" — no es así por esta ruta). El defecto real es de UX: se puede recorrer el stepper hasta Resumen y sólo se descubre al confirmar | POLISH → candidato a prompt 6 |
| Los tiempos relativos no avanzan mientras la pantalla vive | Verificado: `leak_age.dart` calcula desde `diff` en el `build`, sin ticker (`grep Timer/periodic` sin resultados en `lib/`) | POLISH → prompt aparte (toca widgets compartidos) |
| "Fallas activas" del Home acotado al sector (0) mientras el mapa muestra 10 | No verificado: es una **decisión de producto** (¿el resumen debe ser global o por sector?), no un defecto de código | Requiere tu criterio antes de especificar nada |

**Prompt 6 propuesto (opcional, requiere tu aprobación):** un solo prompt POLISH con los tres primeros
ítems de la columna anterior — deshabilitar el toggle de agua sin sector, `controlsBuilder` en español y
guarda por paso en el stepper de agua. Dominio coherente (`water/*` + `notifications/settings_screen`),
modelo **Haiku**, ~15-20 turnos. El ítem de los tiempos relativos va en un prompt separado (toca widgets
de Home y de la lista), y el de "Fallas activas" no se especifica hasta que definas el criterio.

---

## Registro de revisión — v2 (2026-09-22)

Cambios respecto de la v1 de este plan, tras contrastarlo con una propuesta externa del equipo de
arquitectura y verificar cada punto contra el código del baseline:

**Incorporado (aportaba valor real):**

1. **Seam `photoServiceProvider`** (prompt 1, C0). `addPhoto` instancia `ImagePickerPhotoService()` a
   mano (`leak_report_controller.dart:293`), así que el test de mutación del catch `Error` era
   **imposible** de escribir en la v1. Sin este seam no hay test.
2. **Guard con feedback en `_save()`** (prompt 4, C1), en reemplazo de "esperar la carga y escribir":
   más simple, sin una segunda lectura de red, y el mensaje llega al usuario por `saveError`.
3. **Sin debounce en esta tanda** (prompt 2, C5). El intervalo es un parámetro sin dato de
   dispositivo: queda como aprobación A5 (medir la cadencia real de `onCameraIdle` primero). Esto
   también reduce el blast radius: el prompt 2 ya no toca `gota_map_view.dart` ni `map_providers.dart`.
4. **Corrección de la matriz de conflictos.** La v1 decía que 2 y 5 podían correr en paralelo: es
   falso. `leak_report_controller.dart` lo tocan 1 (`addPhoto`) y 5 (`message`) →
   tanda 1 = **1 ∥ 2 ∥ 4**, luego 3, luego 5.
5. **Clave de aserción correcta** (prompt 2): `gotaMapContainerKey` (`gota_map_view.dart:11`, envuelve
   a cualquier builder inyectado, ya usada en los tests `:250`/`:264`) en lugar de la clave privada del
   builder de prueba.
6. **Comandos exactos** para el cambio de `system_config.photo_limits.max_count` (aprobación A1), con
   la verificación antes/después y la prohibición explícita de `db push`.

**Rechazado (con motivo verificado):**

1. **Escribir la sugerencia en el borrador desde `_applyMunicipalitySuggestion`** (su variante para el
   hallazgo 3). El contrato que proponían escribe siempre `draft.municipalityId = matched`, así que
   cada nuevo reverse-geocode **sobrescribiría una elección manual previa** del usuario. Se mantiene la
   variante de la v1 (commit en el handler de "Continuar", sólo si el borrador está vacío) y se
   conserva el aviso "Sugerido según ubicación GPS".
2. **`skipLoadingOnReload` en `_SectorCard` como requisito**: no hace falta. Con
   `copyWithPrevious(previousState, isRefresh: true)`, `AsyncValue.when` ya conserva el dato
   (`skipLoadingOnRefresh` es `true` por defecto). Añadirlo es inocuo, pero el diff mínimo no lo
   necesita; lo que sí se verificó es que el switch de agua sigue deshabilitado durante el guardado
   (`saving = prefs.isLoading`).
3. **Overlay con copy propio para "Mi sector"** ('Configura tu sector en Ajustes'): rompería el test
   existente `map_screen_test.dart:312-337`, que afirma `'Configura tu sector'` y la descripción
   específica. Se conserva la vista de guía actual a pantalla completa para ese caso.
4. **`test/providers.dart`**: la referencia no existe en el repo; los helpers reales son
   `_pumpMapScreen` y `_testMapBuilder` en `test/features/map/map_screen_test.dart`.
5. **Dar por aceptado el render de `data([])` durante el refetch** (su punto 6 del hallazgo 1): es
   exactamente el síntoma reportado ("aparece temporalmente"). Se agrega la guarda
   `!reportsAsync.isLoading` (prompt 2, C6) para que el overlay no se pinte mientras la consulta está
   en vuelo.

**Defecto detectado en su propuesta, corregido al incorporarla:** el guard con `return` sin cambiar el
estado dejaría **colgada** la pantalla de selección de sector (`sector_selection_screen.dart:34-52`
pone `_saving = true` y su listener sale temprano si `next is AsyncLoading`; re-emitir el mismo
`AsyncValue` tampoco notifica porque compara por valor). El contrato de C1 exige publicar
`AsyncValue.error(...)` y el test `el guard publica el estado y libera a los llamadores` cubre el caso.

---

## Registro de revisión — v3 (2026-09-22, tras la auditoría RC)

La auditoría RC cerró con veredicto **`NOT READY`** mientras este plan estaba en revisión. Sus datos
cambiaron supuestos de la v2 y ya están incorporados:

1. **Baseline dejó de ser "referencia histórica":** la RC midió sobre este mismo commit
   `flutter analyze` limpio y `flutter test` **189/189**. Reemplaza el "re-medir" como paso previo.
2. **Hallazgo 2 (fotos) baja de BLOCKER a BETA FIX:** la RC recorrió el flujo real en device con cámara
   y galería y **no reprodujo** el cierre. El hueco de código sigue siendo real y la regla de 2 fotos
   es requisito de producto, así que el prompt se mantiene; si se reproduce en device, escala a BLOCKER.
3. **Hallazgo 1 queda como el de mayor respaldo empírico:** desmonte de MapLibre **reproducido en
   device** (píxeles 506.438 → 3.146, pantalla 95 % blanca). En cambio el flash de "Sin fugas para
   mostrar" durante el pan **no** se reprodujo (capturas 10 s byte-idénticas): C6 se mantiene, pero debe
   declararse como no respaldada por reproducción, no como causa confirmada en hardware.
4. **`A3` pasó de preferencia a bloqueante del gate de build:** el APK release del 20-sep no contiene el
   Home nuevo y `main` sirve el anterior. Merge de la rama + rebuild del release es lo que desbloquea el
   piloto (junto con los fixes).
5. **`A4` se precisó:** existe dispositivo físico (Samsung SM-A245M, Android 16, `R58W709201M`) usado por
   la RC, pero **hoy está desconectado** (verificado: `adb devices` vacío).
6. **Nuevo `A6`:** limpieza de los datos de prueba del piloto y de los 3 anónimos residuales del Docker
   local que reporta la RC como INFO.
7. **Anexo nuevo:** los 7 hallazgos de la RC que no venían en el brief, con mi verificación en código
   (uno de ellos **matizado**: la RC afirma que la RPC rechaza el stepper sin municipio/sector, y en
   realidad hay una guarda cliente previa en `water_register_controller.dart:97-105`). Tres de ellos son
   candidatos a un prompt 6 que **requiere tu aprobación** para entrar en alcance.

**Lo que la RC NO cambia:** los 5 prompts, sus modelos, el orden por tandas y las aprobaciones A1/A2
siguen igual; tampoco habilita mergear a `main` sin tu decisión.

---

## Registro de revisión — v4 (2026-09-23, tras ejecutar y verificar la tanda 1)

La tanda 1 (**prompt 2 ∥ 1 ∥ 4**, Sonnet, en worktrees separados) se ejecutó y el orquestador la
verificó con evidencia propia: `flutter analyze` limpio y `flutter test` **194/194** (prompt 1),
**193/193** (prompts 2 y 4), más control de mutación reproducido en los tres (revertir el fix hace
fallar los tests nuevos). Archivos PROHIBIDOS respetados; ningún commit. Dos correcciones al plan:

1. **Prompt 4, C1 — el guard correcto es más amplio que el contratado.** El plan exigía escribir el
   `sectorId` explícito aunque no hubiera carga previa, y bloquear solo el caso `sectorId == null`. La
   implementación bloquea **cualquier** guardado sin valor previo
   (`notification_providers.dart:59-65`: `!clearSector && !previousState.hasValue`). El motivo, verificado
   en el código: con `current == null`, `enabled = enabled ?? false` (`:77`) enviaría **`enabled: false`**
   apagando las notificaciones de agua que el usuario tenía encendidas, sin pedirlo. El contrato literal
   tenía un agujero destructivo; se adopta el guard amplio y se corrige el texto de C1 arriba.
2. **Prompt 4, C2 — la vía elegida usa una API `@internal`.** `copyWithPrevious` está anotado
   `@internal` en riverpod 3.4.3 (`riverpod-3.4.3/lib/src/core/async_value.dart:629`, `:714`, `:777`,
   `:865`); se usó con `// ignore: invalid_use_of_internal_member`
   (`notification_providers.dart:68-69`). No hay vía pública al mismo efecto. Se abre el **prompt 6**
   (`docs/PROMPT_6_IS_SAVING_2026-09-23.md`, Sonnet) para eliminarla sin perder el "no ocultar el valor"
   ni la liberación de los llamadores. Ojo: su contrato exige cubrir dos casos que el diseño "solo flag"
   rompe — **éxito con valor igual al previo** y **fallo con valor previo** (en este último, `:85-87`
   reasigna el mismo `previousState`, que no notifica).

**Error del plan detectado al verificar (corregido en el prompt 6):** el prompt 4, C1, afirma que
`settings_screen.dart:199-210` (`_confirmClear`) tiene el patrón `if (!_toggling || next is AsyncLoading)
return;`. En el baseline **no lo tiene**: hace `await controller.clearSector()` y luego lee `saveError`.
Los listeners que sí existen son dos (`sector_selection_screen.dart:34-52` y
`settings_screen.dart:240-257`).

**Aprobaciones A3–A6 siguen intactas y sin ejecutar** (merge a `main`, rebuild del release, device,
medición de `onCameraIdle`, limpieza de datos). La tanda 1 **no** desbloquea el gate de build por sí sola.

---

## Registro de revisión — v5 (2026-09-23, prompt del owner sobre Reportar/fotos/estado)

El dueño del producto entregó un prompt paralelo («GOTA — Implementación: Reportar / UX, fotos y estado de
ubicación»). Lo contrasté punto por punto contra lo ya ejecutado y verificado. Resultado:

**Ya cubierto y verificado (6 de 10 puntos) — no se re-ejecuta nada:**

| Punto del prompt del owner | Dónde quedó |
|---|---|
| 1 · quitar la leyenda bajo «¿Dónde está la fuga?» | prompt 5, C3 (`leak_report_screen.dart:137-142`) |
| 3 · «Continuar» habilitado con municipio/sector preseleccionados, sin `onChanged` artificial, sin selección automática irreversible | prompt 3 (implementado y verificado; usa los valores efectivos y los escribe en el borrador **al pulsar**, sólo si están vacíos) |
| 4 · sector de interés que desaparece | prompt 4 (guard + `copyWithPrevious`; deuda de la API `@internal` delegada al prompt 6) |
| 5 · máximo 2 fotos con feedback y sin perder las existentes | prompt 1 (`kReportPhotoMaxCount = 2`; el guard publica mensaje, **no** lanza excepción) |
| 7 · no silenciar con un `try/catch` genérico; error recuperable → estado de UI | prompt 1 (`PhotoValidationException` tipada + banner; el `catch` del controller traduce y `debugPrint` en modo debug, no silencia) |
| 8 · no mostrar el GUID en la confirmación | prompt 5, C5 |

**Adoptado (aporta valor nuevo): el punto 6 — presupuesto de resolución/calidad de foto.** Estaba
implícito y sin cifra en el plan (que solo decía «la calidad ya es estándar y no se toca»). Se implementó
como **prompt 7** (`docs/PROMPT_7_PRESUPUESTO_FOTO_2026-09-23.md`): `image_picker` 1920 → **1280**,
compresión 1920×1080 @82 → **1280 @75**, con seam inyectable para poder testearlo. Ataca directamente la
hipótesis de OOM del hallazgo 2 (menos memoria en el decode/reencode) y estabiliza la subida.

**Rechazado / en conflicto (con motivo verificado):**

1. **Punto 2 (orden de la tarjeta de ubicación):** pide «Ubicación/Dirección → tarjeta de
   coordenadas/precisión → Municipio/Sector → resto». En `DataStepView` la única tarjeta de esa zona es la
   de la **dirección sugerida** (`displayText`, `:601-633`); las coordenadas (`'Lat: …'`) están en
   `LocationStepView` (`:190`). El orden pedido **es el actual**, así que no hay cambio; y **contradice**
   el punto 5.4 del plan (que pedía mover esa tarjeta debajo del dropdown de sector). Se retira 5.4 del
   prompt 5 y queda anotado que traer las coordenadas al paso de datos sería un cambio nuevo.
2. **Punto 10 «crear un commit único»:** el plan exige commits `docs-only` separados de los de código, y
   la tanda 1 son cuatro cambios independientes. Propuesta: **un commit de código** con el mensaje pedido
   (`fix: stabilize leak report photos and form state`) sobre `fix/map-r5-r6`, manteniendo los docs en sus
   commits propios ya existentes.
3. **Punto 10 «probar físicamente en Android» (13 pasos):** **no ejecutable hoy** — A4 sigue pendiente y
   `adb devices` está vacío. Sin device, esos 13 pasos quedan `NOT VERIFIED`; no se declaran PASS.

**Sin cambios:** rama de trabajo (`fix/map-r5-r6`, nunca `main`), prohibiciones (RPC, RLS, Storage, FCM,
mapa, Home, Water Events, esquema), y la exigencia de `flutter analyze` + `flutter test` como gate.
