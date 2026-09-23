# PROMPT 9 — DELEGACIÓN · REPORTAR: orden de ubicación, copy sin GUID y borrador persistente (BLOCKER)

> Spec autocontenido para un agente codificador. Lee este archivo y ejecútalo **exactamente**.
> Responde solo con el formato de `§9`. No pidas el diagnóstico, el plan ni el chat: todo lo
> necesario está aquí dentro.

## 0. Rol, gate de arranque y política de modelos

Eres el agente codificador de Gota. Implementas con tests reales y **no reportas como verificado
nada que no hayas ejecutado**. Antes de tocar código:

1. Corre los 4 comandos de `§2` y confirma la base.
2. Propón con `clarify`, en un solo formulario: (a) el plan por tanda, (b) quién ejecuta y **qué
   modelo** por tanda, (c) la confirmación de la interpretación de `R2` (`§4.2`), que es la única
   decisión abierta en este spec.
3. **No ejecutes nada** (ni `flutter`, ni `git` de escritura, ni agentes, ni builds) hasta tener
   la aprobación explícita del dueño.

Política de motores (instrucción explícita del dueño: *«no uses Sonnet para test, para test usa un
modelo gratuito o muy barato»*):

| Tarea | Motor |
|---|---|
| Tests, copy, cambios mecánicos | gratis o lo más barato: `opencode run --model opencode/ling-3.0-flash-fin-free` (probado, $0), Copilot `gpt-5-mini` por cuota, Ollama local (`qwen3-coder-instruct-128k`) |
| Diagnóstico y refactor con criterio | Sonnet |
| Arquitectura y dictámenes | Opus |
| Verificación mecánica (analyze / test / mutación / adb / git) | el orquestador (Hermes directo), no un agente |

Tandas de este spec:

- **T-A · Sonnet** → `R4` (borrador persistente + recuperación de la captura). Es la pieza con criterio.
- **T-B · gratis/barato** → `R1`, `R2`, `R3`, `R5` (copy y orden) y la actualización de los tests existentes.
- **T-C · gratis** → los tests nuevos de `R1`/`R2`/`R3`.

**Orden y paralelismo:** T-A y T-B **no** pueden correr en paralelo: ambas tocan
`lib/features/leaks/presentation/leak_report_screen.dart` (T-A añade el banner de reanudación) y
`leak_report_controller.dart`. Si hay un solo agente: **T-A → T-B → T-C**. T-C se puede escribir
después de T-B, nunca antes.

## 1. Qué cambia respecto del prompt original del dueño (y por qué)

El prompt del dueño (2026-09-22/23) pedía 10 puntos, con base `fix/map-r5-r6` @ `525725c`. **Esa base
ya no existe como punto de trabajo** y 6 de los 10 puntos ya están implementados y verificados. Este
spec solo cubre el **delta real**; lo demás queda en `§3` como «no repetir».

Las dos razones por las que el prompt original no se puede ejecutar tal cual:

- **El punto 7 (cierres al tomar foto) tiene causa raíz nueva y verificada**: no es una excepción no
  capturada (ese `catch` ya existe), es el **low-memory killer de Android** matando el proceso con la
  cámara en primer plano. Ningún `try/catch` puede atrapar eso: la mitigación real es **persistir el
  borrador** y **recuperar la captura** que el plugin dejó en disco. Por eso `R4` es la pieza grande.
- **El commit que pedía el prompt original ya existe** (`10e6826`, mensaje literal
  `fix: stabilize leak report photos and form state`). La tanda nueva necesita mensaje propio (`§8`).

## 2. Base: verificación obligatoria (pegar salida real, no resumida)

```bash
cd /d/Proyectos/Gota/v0.2
git log --oneline -3
git status --short
git branch --show-current
"C:/Users/arqui/AppData/Local/Android/Sdk/platform-tools/adb.exe" devices
```

- **Base real esperada:** `main` @ `ac2015d` (local). `origin/main` está **2 commits por detrás**: son
  docs pendientes de push, decisión del dueño, no los pushees.
- **`fix/map-r5-r6` ya no es la base de trabajo**: quedó idéntica a `main` por fast-forward. Los
  commits `525725c` y `bbef6ae` que citaba el prompt viejo son historia: si algo los menciona, está
  obsoleto, no los uses como base.
- **Entorno:** repo `D:\Proyectos\Gota\v0.2`, bash MSYS. App Flutter Android + Supabase; piloto
  controlado en la Isla de Margarita. Device físico: Samsung SM-A245M, Android 16, 1080x2340, serial
  `R58W709201M`, paquete `com.gota.app`, RAM total 3.77 GB.
- **Cloud piloto:** `eghphmugrrbvbvodhasq` (`SUPABASE_ENV=pilot`), credenciales en
  `.local-supabase-pilot.env`. **Esta tanda no toca el cloud** (ver `§5`).

## 3. Estado REAL de los 10 puntos del dueño — no repetir lo hecho

| Punto del prompt del dueño | Estado verificado hoy | Evidencia |
|---|---|---|
| 1. leyenda bajo «¿Dónde está la fuga?» | **pendiente** → `R1` | `leak_report_screen.dart:137-142` |
| 2. tarjeta de ubicación/coordenadas | **pendiente** → `R2` (interpretación en `§4.2`) | `leak_report_screen.dart:165-205`, `:250-…` |
| 3. «Continuar» con preselección | **HECHO y verificado** (device QA: `Continuar clickable=true`). Mecanismo real: valores *efectivos* + `_continueWithEffectiveSelection`. **No lo toques.** | `leak_report_screen.dart` (`_buildContinueCallback`), `leak_report_controller.dart:182-217` |
| 4. sector de interés vacío | **HECHO y verificado** | `notification_providers.dart:57-69` |
| 5. máx. 2 fotos (cliente) | **HECHO**: `kReportPhotoMaxCount = 2` y test que lo fija | `photo_limits.dart:13`, `photo_limits_test.dart:86` |
| 5. máx. 2 fotos (servidor) | **PENDIENTE y FUERA DE ALCANCE** (SQL con aprobación aparte) | `system_config.photo_limits` |
| 6. calidad de foto | **HECHO**: 1280 px @75, un solo pase, seam inyectable | `photo_limits.dart:22-24`, `photo_service.dart:29-36,110-125` |
| 7. cierres al tomar/elegir foto | **PARCIAL**: el `catch` que cubre `Error` ya está; la causa raíz real es el LMK → **`R4`** | `leak_report_controller.dart:307-314` |
| 8. GUID en la confirmación | **pendiente** → `R3` | `leak_report_controller.dart:445-446` |
| 9/10. no tocar / validar | vigentes, ver `§5`, `§7`, `§10` | — |

**Baseline de la suite: 209/209, `flutter analyze` sin issues** (medido por el orquestador sobre
`main`). Cualquier conteo distinto al final hay que explicarlo, no maquillarlo.

## 4. Contratos

### 4.1 · R1 — quitar la leyenda bajo «¿Dónde está la fuga?»

- Eliminar en `leak_report_screen.dart:137-142` el `const SizedBox(height: 4)` y el
  `const Text('Usa tu GPS o indica la zona manualmente. Esto ayuda a tus vecinos a encontrarla en el
  mapa.')`.
- El título `'¿Dónde está la fuga?'` (`:133-136`) **se mantiene**.
- Nada más cambia en el paso de ubicación (GPS, ubicación manual, reverse-geocode, sugerencia,
  municipio, sector y las coordenadas como fuente de verdad quedan intactos). No tocar D2.
- **Test (mutation control):** en el paso de ubicación, `expect(find.textContaining('Usa tu GPS'),
  findsNothing)`. Revertir la eliminación debe ponerlo en rojo.

### 4.2 · R2 — orden de ubicación: dirección → tarjeta de coordenadas/precisión → mapa

**Interpretación fijada (confirmarla en el gate del `§0`).** El requisito del dueño dice: *«la tarjeta
que muestra las coordenadas/detalles técnicos de ubicación debe aparecer inmediatamente debajo de esa
información»*, con el esquema `Ubicación/Dirección ↓ Tarjeta de coordenadas/precisión ↓
Municipio/Sector ↓ resto del formulario`, y **«no duplicar información»**. Además «Municipio/Sector»
vive en un paso distinto (Datos). Por eso la lectura que se implementa es **dentro del paso de
Ubicación**: la información de dirección va inmediatamente **encima** de la tarjeta de
coordenadas/precisión. No se crea ninguna tarjeta nueva y no se duplica nada.

Orden objetivo del paso de ubicación, exacto:

1. `'¿Dónde está la fuga?'` (título).
2. Botones `'Usar mi ubicación (GPS)'` y `'Indicar ubicación manual'`.
3. Tarjeta de dirección: bloque `'Ubicación aproximada'` (`displayText` del reverse-geocode) **cuando
   exista**, junto con su indicador de carga (`suggestionLoading`) y los mensajes de error del geocoder.
4. Tarjeta de coordenadas/precisión: la que hoy está en `:165-205` (icono, `location.source.label`,
   `'Lat: … Lng: …'`) seguida del texto de precisión (`'Precisión aproximada: …'`, hoy en `:215-225`).
5. Mapa de ajuste (`locationMapBuilderProvider`, alto 220).
6. El `Card` de `'Sin ubicación todavía. Elige GPS o manual para continuar.'` se mantiene donde está
   hoy (cuando `location == null`).

**El paso de Datos no se reordena**: la tarjeta compacta de dirección sigue **antes** del dropdown de
Municipio (`:601-633`), y luego Sector (`:676-682`) y Descripción (`:684-692`). La frase del plan viejo
que pedía mover esa tarjeta **después** del dropdown de sector queda **anulada** (era una lectura
equivocada de este mismo requisito). Solo se toca el paso de Ubicación.

- **Test (mutation control):** con ubicación GPS y sugerencia cargada, el bloque de dirección queda por
  encima de la tarjeta de coordenadas. Affirmarlo con geometría real y no con estado del controller:
  `tester.getTopLeft(find.text('Ubicación aproximada')).dy < tester.getTopLeft(find.textContaining('Lat:')).dy`.
  Revertir el reordenamiento debe ponerlo en rojo.
- **Trampa:** los widgets del paso viven en un `ListView`; lo que queda fuera de pantalla **no se
  construye**. Usar `tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first)`
  o `ensureVisible` antes de medir o pulsar. Un `find` que devuelve 0 widgets suele ser esto, no un bug.

### 4.3 · R3 — quitar el GUID de la confirmación

- En `leak_report_controller.dart:445-446` el mensaje pasa a:
  `'¡Reporte enviado! La fuga quedó registrada como activa.'` (sin `(ID $reportId)`).
- **El `reportId` se conserva** en `state.outcome` (`ReportCreated`) para diagnóstico: no toques el
  modelo, ni `copyWith`, ni la navegación.
- No tocar el título `'Reporte enviado'` (`leak_report_screen.dart:1066`) ni la pantalla de duplicado
  (`:977` usa `candidates.first.id` para navegar, no lo imprime).
- **Barrer el resto:** buscar cualquier otro texto visible que imprima el id (`grep` de `reportId` y de
  `'ID '` en `lib/features/leaks/presentation/`); si aparece otro, quitalo y **reportalo**.
- **Test (mutation control):** con un repository falso que devuelve `ReportCreated(reportId: 'abc-123')`,
  tras `submit()` el `state.message` **no** contiene `'abc-123'`. Restaurar el mensaje viejo debe ponerlo
  en rojo.
- **Tests existentes:** `test/features/leaks/leak_report_duplicate_flow_test.dart:188,270` afirman
  `find.text('Reporte enviado')` (el título) — **no se tocan**.

### 4.4 · R5 — copy arrastrado del prompt 5 v5 (misma tanda de UX)

No vienen del prompt del dueño sino de la spec `PROMPT_5_UX_2026-09-23.md` (C1/C2), y siguen vigentes:

- **C1:** en `home_screen.dart:386-393`, eliminar `Text('Resumen de hoy')` y el
  `SizedBox(height: AppSpacing.md)` que le sigue. La tarjeta de resumen y su contenido (`summaryAsync.when`)
  no se tocan.
- **C2:** en `water_screen.dart:128-131`, eliminar `Text(WaterCopy.summaryTitle)` y su
  `const SizedBox(height: AppSpacing.sm)`; y eliminar la constante `WaterCopy.summaryTitle`
  (`water_copy.dart:6`), que queda sin uso. Si al quitar el bloque queda un `SizedBox` huérfano de más,
  ajustar **solo** ese. `historyTitle`, `stepType` y `emptyList` se siguen usando: no los toques.
- **Tests existentes que afirman ese copy (actualizaciones justificadas, NO borrados):**
  `test/features/home/community_summary_card_test.dart:192,206,224,232`
  (`find.text('Resumen de hoy')` → `findsNothing`, conservando el resto de aserciones de cada test) y
  `test/features/water/water_screen_test.dart:85` (`find.text(WaterCopy.summaryTitle)` →
  `find.text('Resumen')` + `findsNothing`). Las otras líneas que usan `WaterCopy` (`:86,106,114`) quedan
  intactas.

### 4.5 · R4 — BORRADOR PERSISTENTE (BLOCKER del piloto)

**Evidencia cruda de la causa (device, 2026-09-23, reproducido por el orquestador):**

```
23:54:11.386 lmkd: Reclaim 'com.gota.app' (30364), oom_score_adj 700, state 15
                  to free 113444kB rss, 138548kB swap; reason: min watermark
23:54:11.616 Zygote: Process 30364 exited due to signal 9 (Killed)
```

No hay `FATAL` ni `ANR`: `logcat -b crash` y `dumpsys dropbox` están **vacíos** para Gota. La app venía
pesando **PSS 241 MB / RSS 279 MB** tras pasar por el mapa, y el teléfono ese minuto tenía 940 MB
disponibles (el LMK también reclamó Settings, GMS, Photos y Facebook). **Es el sistema, no la app**: por
eso el objetivo no es «evitar el cierre» (imposible desde Dart) sino que **el trabajo del usuario
sobreviva**.

Punto fino que decide el diseño: la foto se toma con **la app en segundo plano** (la cámara pasa a primer
plano) y el kill ocurre ahí, cuando todavía no se volvió. Guardar «al volver» no sirve: no se vuelve.
Hay que guardar **antes de abrir el picker** y recuperar al arrancar de nuevo.

**R4.1 · Puerto de persistencia (costura inyectable, mismo precedente que `PhotoCompressCall` en
`photo_service.dart:29-36`).** Archivo nuevo `lib/features/leaks/data/draft_store.dart`:

```dart
abstract class DraftStore {
  Future<LeakDraftSnapshot?> read();
  Future<void> write(LeakDraftSnapshot snapshot);
  Future<void> clear();
}
```

- `FileDraftStore`: JSON versionado en `getApplicationSupportDirectory()/report_draft.json`, escritura
  **atómica** (`.tmp` + `rename`).
- `InMemoryDraftStore` para tests (sin filesystem, sin `path_provider`).
- `final draftStoreProvider = Provider<DraftStore>(...)`, sustituible en tests igual que
  `photoServiceProvider` (`photo_service.dart:153`).

**R4.2 · Qué se persiste** (snapshot con `schemaVersion: 1` y `savedAt`, derivado del estado real de
`leak_report_controller.dart:25-92`):

| Campo | Persistir | Motivo |
|---|---|---|
| `currentStep`, `location` (lat/lng/source/accuracy) | sí | es el trabajo del usuario |
| `municipalityId`, `sectorId`, `description` | sí | idem |
| `photos`: `id`, `compressedPath` (**durable**, ver R4.3), `mimeType`, `sizeBytes`, `width`, `height`, `originalPath` | sí | idem |
| `message`, `outcome`, `submitState`, `suggestionLoading` | **no** | transitorios |
| `locationSuggestion`, `suggestedMunicipalityId`, `suggestedSectorId` | **no** | se recalculan; persistirlos los dejaría desalineados con el GPS nuevo |

**R4.3 · Las fotos tienen que sobrevivir al cache.** Hoy el JPEG comprimido se escribe junto al archivo
elegido (`'${path}_gota.jpg'`, `photo_service.dart:110`) y el picker entrega rutas dentro del **cache** de
la app, que el sistema puede reclamar. Al persistir, el archivo comprimido se **copia** a un directorio
durable (`.../report_draft_photos/`) y el snapshot guarda **esa** ruta. Al restaurar se verifica
`exists()`: una foto que ya no está se descarta del borrador **y se informa**, no se silencia. En
`clear()` se borran los archivos huérfanos del directorio.

**R4.4 · Cuándo se guarda** (lo crítico, no negociable):

- **Antes de abrir el picker** (`addPhoto` → `service.pickAndPrepare`, `leak_report_controller.dart:295`).
- Tras cada mutación del borrador: `selectMunicipality`, `selectSector`, `setDescription`, `removePhoto`,
  `addPhoto` exitoso, y al fijar ubicación (GPS o manual).
- Al **cerrar el flujo**: `clear()` en envío exitoso (`ReportCreated`), en `useExistingReport()` y en
  descarte explícito del usuario. Nunca queda basura tras un envío.
- Se permite debounce **solo** si la medición en device muestra coste, y **nunca** sobre el guardado
  pre-picker.

**R4.5 · Restauración.** En `LeakReportController.build()`: leer el snapshot, validar `schemaVersion` y
**TTL**; si es válido, arrancar con ese estado. JSON corrupto o versión desconocida → estado vacío, **sin
excepción**, y purga del archivo.

- **TTL = 24 h** (decidido; el dueño puede cambiarlo en el gate).
- **UX decidida:** banner discreto en el asistente con el texto **«Recuperamos tu reporte sin enviar»** y
  una acción **«Descartar»**. Nada de reanudar en silencio: el usuario debe ver y poder descartar lo
  restaurado.

**R4.6 · Recuperar la captura perdida** (esto es lo que devuelve la foto que se estaba tomando). En
Android, cuando el proceso muere con el picker en primer plano, `image_picker` deja la captura en disco y
`ImagePicker.retrieveLostData()` la entrega al próximo arranque:

- Envolver la llamada en una costura inyectable (`LostDataCall`) para poder testear el camino **sin
  device**, igual que el pase de compresión.
- Al encontrar lost data: `prepareFromFile(...)` → añadir al borrador **respetando el tope de 2** →
  persistir.
- **Verificar la semántica real en el código/README del plugin instalado antes de asumirla** (qué devuelve
  con varias fotos, qué pasa en iOS, si el archivo es reutilizable o solo un buffer) y **citar en el
  reporte qué leíste**. Si la verificación contradice este diseño, se anota y se ajusta: no se implementa a
  ciegas.
- Lo mismo vale para `path_provider`: **se declara como dependencia directa en `pubspec.yaml`** (decidido;
  ya está resuelto en `pubspec.lock` como transitiva, así que no entra ningún paquete nuevo) y hay que
  correr `flutter pub get`.

**Archivos previstos de R4:** `draft_store.dart` y `draft_photo_store.dart` (nuevos);
`leak_report_controller.dart` (hooks de guardado/restauración/limpieza); `photo_service.dart` (costura de
lost data, **sin** tocar el pipeline de resolución/calidad del prompt 7); `leak_report_screen.dart` (banner
de reanudación + Descartar); `pubspec.yaml` (`path_provider`).

**Tests de R4 (mutation control obligatorio, uno por uno; store en memoria; prohibido reimplementar la
lógica de producción dentro del test):**

| # | Test | Mutación que debe hacerlo fallar |
|---|---|---|
| 1 | mutar el borrador (foto + datos) → el store recibe un snapshot con esos campos | no llamar a `write` |
| 2 | `build()` con snapshot válido → borrador y paso restaurados | ignorar el snapshot |
| 3 | snapshot corrupto / `schemaVersion` desconocido → estado vacío, sin excepción | propagar la excepción |
| 4 | `addPhoto` persiste **antes** de invocar el picker | mover el guardado después del picker |
| 5 | envío exitoso / `useExistingReport` → `clear()` | no limpiar |
| 6 | TTL vencido → no restaura y purga | ignorar el TTL |
| 7 | foto restaurada cuyo archivo ya no existe → se descarta del borrador | asumir que existe |
| 8 | lost data presente → se añade al borrador y respeta el tope de 2 | ignorar lost data |

**Declaración honesta de límites de R4:** el kill lo decide el sistema; no se puede garantizar por test
que no vuelva a ocurrir. Lo verificable es que el borrador **sobrevive** y que la captura se recupera. La
medición de huella base (PSS en frío, tras el mapa y con la cámara abierta) se hace **antes** de proponer
cualquier cambio en MapLibre: `app_shell.dart:81` mantiene las pestañas en un `IndexedStack`, así que el
mapa **no** se desmonta a propósito (retirarlo sería regresión del hallazgo 1 del mapa). Si la medición
muestra que el mapa no es el peso dominante, esa parte se documenta y se cierra sin código.

## 5. Fuera de alcance (enumérelo también en tu reporte)

- **No tocar:** mapa (`map_screen.dart`, `gota_map_view.dart`, `map_providers.dart`), Home (salvo C1 de
  R5), Agua (salvo C2 de R5), FCM/push, notificaciones y preferencias (eso es otra tanda: prompt 6),
  GPS/D2 como arquitectura, `goToNext`, `selectMunicipality`/`selectSector`, los helpers del botón
  «Continuar» (`_buildContinueCallback` / `_continueWithEffectiveSelection`), el pipeline de calidad de
  foto del prompt 7, RPC `create_leak_report`, RLS, Storage security, migraciones, `system_config`, el
  esquema de datos y el package `com.gota.app`.
- **Prohibido:** `npx supabase db push` (en cualquier forma); `git push`; `git stash`; cambiar de rama;
  tocar worktrees ajenos (`.claude/worktrees/agent-a429749783d7a8538` y los de la tanda anterior);
  `--no-verify`; borrar o marcar `skip` tests existentes; imprimir secretos (anon key, JWT, service-role,
  tokens, FCM): siempre `[REDACTED]`.
- **A1/A2** (bajar `system_config.photo_limits.max_count` a 2 en local y en cloud) es una decisión de datos
  del dueño, con su propia aprobación y solo vía `npx supabase db query --linked -f <archivo.sql>`.
  **No es trabajo del agente.**
- **No crear infraestructura de tests nueva** ni duplicar dobles existentes.

## 6. Entorno: trampas ya pagadas (no las redescubras)

1. `flutter build apk` muere con `ERROR: JAVA_HOME is set to an invalid directory: …jdk-17.0.20.101-hotspot`.
   Solución sin tocar el sistema: `export JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'`
   y verificar `"$JAVA_HOME/bin/java" -version`.
2. Un build **fallido deja el APK viejo en su ruta**: `ls -la` engaña. Exigir **mtime nuevo + sha256**.
3. `versionName` no distingue builds (`1.0.0+1` no cambia). Para probar que el device corre el build nuevo:
   `adb pull` del `pm path` + **sha256 contra el APK compilado**.
4. `adb pull` a `/tmp` falla en este host: usar un directorio propio del scratch.
5. Las pantallas Flutter **no siempre aparecen en `uiautomator dump`** (los tiles de foto, por ejemplo):
   localizar los controles por **análisis de píxeles** del PNG, no por estimación visual.
6. Selector de fotos de Android: «Done» está en la barra inferior (≈ `(950, 2126)` en 1080x2340). En el
   visor de Samsung, confirmar la captura es `OK` ≈ `(784, 2103)`.
7. Coordenadas útiles del flujo: tab **Reportar** ≈ `(540, 2092)`, «Usar mi ubicación (GPS)» ≈ `(540, 774)`,
   «Continuar» del asistente ≈ `(540 ó 787, 2092)`, tile de foto con 0 fotos ≈ `(180, 750)` y con 1 foto
   ≈ `(500, 825)`, hoja «Tomar con la cámara» ≈ `(540, 1969)` / «Elegir de la galería» ≈ `(540, 2126)`.
8. En el paso de Datos los widgets viven en un `ListView`: lo que está fuera de pantalla **no se construye**
   (ver `§4.2`).
9. Si el device no aparece en `adb devices`, no concluyas nada: reportalo y seguí con lo que sí puedas
   verificar; nada de «PASS» sin evidencia.

## 7. Gates y validación

**Ejecuta y pega la salida real (nunca un resumen):**

```bash
flutter analyze                      # esperado: No issues found!
flutter test                         # esperado: 209 + los nuevos, todos en verde
```

**Control de mutación, uno por uno** (revertir el cambio → el test nuevo debe **fallar** → restaurar →
verde): R1, R2, R3 y los 8 de R4. Un fix sin control de mutación **no está verificado**. Prohibido
reimplementar la lógica de producción dentro del test, prohibido un test que pase en el baseline.

**Validación en device — la ejecuta el orquestador, no el agente** (el agente entrega analyze + tests +
mutaciones). Los 13 pasos del dueño, más los 3 nuevos:

1. Reporte GPS · 2. reverse-geocode · 3. municipio/sector preseleccionados · 4. «Continuar» sin tocar nada ·
5. 1 foto por cámara · 6. 1 foto por galería · 7. intentar la tercera foto · 8. cancelar cámara ·
9. cancelar galería · 10. repetir cámara/galería varias veces · 11. completar el reporte · 12. confirmar que
**no** aparece el GUID · 13. verificar que las coordenadas siguen siendo GPS truth.
**Nuevos:** 14. el orden del paso de ubicación es «dirección → coordenadas/precisión → mapa» · 15. el
borrador **sobrevive** al kill por cámara (si vuelve a ocurrir: el pid cambia pero al reabrir el asistente
el borrador está, con la foto recuperada) · 16. el banner «Recuperamos tu reporte sin enviar» aparece y
«Descartar» limpia el borrador y sus fotos.
Evidencia: capturas + líneas crudas de `logcat` (`lmkd`/`Zygote`). Si el kill **no** se reproduce en la
corrida de cierre, se dice así: no se declara PASS.

## 8. Commits

- **No commitees ni pushees nada sin autorización explícita del orquestador.** Cuando la autorice: **un**
  commit de código con los cambios de la tanda aprobada y un mensaje **nuevo** — propuesta:
  `fix(reportar): borrador persistente, orden de ubicacion y copy sin GUID`.
  **No reutilices** `fix: stabilize leak report photos and form state`: ya existe (`10e6826`).
- Los docs van en commit `docs:` aparte.
- `main` no se toca: la autorización de merge/push es del dueño.

## 9. Formato del reporte final (exactamente estos campos)

```
STATUS: <qué quedó implementado / qué no>
BASE VERIFICADA: <salida de los 4 comandos de §2>
CAMBIOS: <archivo:línea — qué, en una línea cada uno>
TANDAS Y MODELO: <qué tanda ejecutó qué motor>
ANALYZE: <salida real>
TESTS: <conteo real + salida real>
MUTACIONES: <una línea por test: revertido → ROJO / restaurado → VERDE>
TESTS EXISTENTES AJUSTADOS Y POR QUÉ: <...>
ARCHIVOS: <lista>
COMMIT: ninguno (o el hash si fue autorizado)
BLOCKER: <si hay; si no, "ninguno">
NOT VERIFIED: <lo que no pudiste probar y por qué; el device lo cubre el orquestador>
DUDAS DE INTERPRETACIÓN: <R2 y lo que hayas encontrado>
```

No narres cada tool call. No expongas claves ni rutas de credenciales. Tabla **implementado vs
verificado** con el comando que lo respalda: si algo no lo ejecutaste, va como `NOT VERIFIED`.