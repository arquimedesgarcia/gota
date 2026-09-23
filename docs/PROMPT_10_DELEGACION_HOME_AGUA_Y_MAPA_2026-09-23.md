# PROMPT 10 — DELEGACIÓN · REPARAR HOME/AGUA (suite ROJA) + MAPA: cámara y refetch

> Spec autocontenido. El agente que lo reciba no ve el chat, ni el diagnóstico, ni los prompts
> anteriores: todo lo necesario está aquí. Responde solo con el formato de `§10`.

## 0. Rol, gate de arranque y política de modelos

Eres el agente codificador de Gota. Implementas con tests reales y **no reportas como verificado nada
que no hayas ejecutado**. Antes de tocar código:

1. Corre los comandos de `§2` y confirma base y estado.
2. Propón con `clarify`: (a) plan por tanda, (b) quién ejecuta y **qué modelo**, (c) la confirmación de
   las dos decisiones de interpretación (`A4` y `B5`).
3. **No ejecutes nada** (ni `flutter`, ni `git` de escritura, ni builds) hasta la aprobación del dueño.

Política de motores (instrucción explícita del dueño: *«no uses Sonnet para test, para test usa un
modelo gratuito o muy barato»*):

| Tarea | Motor |
|---|---|
| Tests, copy, cambios mecánicos | gratis o lo más barato: `opencode run --model opencode/ling-3.0-flash-fin-free` ($0, probado), Copilot `gpt-5-mini` por cuota, Ollama local (`qwen3-coder-instruct-128k`) |
| Diagnóstico y refactor con criterio | Sonnet |
| Arquitectura y dictámenes | Opus |
| Verificación mecánica (analyze/test/mutación/adb/git) | el orquestador (Hermes), no un agente |

Tandas de este spec:

- **Tanda A · modelo gratuito/barato** → reparar la suite roja (`A1`) y escribir los tests que faltan de
  lo ya commiteado (`A2`, `A3`). Trabajo mecánico; el orquestador verifica cada mutación.
- **Tanda B · Sonnet** → el mapa (`B1`–`B6`). Es un refactor con criterio sobre el ciclo de vida del
  `Widget` y el viewport.
- **Tanda C · orquestador** → device (`§8`) y gates (`§7`).

**Orden:** A antes que B. A toca `home_screen`/`water`/tests de leaks; B toca solo `lib/features/map/**`
y `test/features/map/**`. No comparten archivos, pero **serializadas** igual: con un solo agente, una
tanda a la vez, porque el orquestador tiene que correr analyze/test/mutación entre ambas.

## 1. Por qué existe este prompt (lo que pasó y no se dijo)

El commit **`abc71ac`** (ya pusheado a `origin/main`) aplicó el prompt del dueño de Home/Agua y, de
paso, los cambios `R1`–`R5` del prompt 9. Dejó tres cosas mal, verificadas por el orquestador:

1. **La suite quedó ROJA.** Medición real: `flutter test` → **204 pasaron, 5 fallaron**. Fallos
   exactos:
   - `test/features/home/community_summary_card_test.dart` — Caso 1, Caso 5, Caso 6 y Caso 7 (afirman
     `find.text('Resumen de hoy')`; el texto ya no se renderiza).
   - `test/features/water/water_screen_test.dart:85` — afirma
     `find.text(WaterCopy.summaryTitle)` (`:85`); el título ya no se renderiza.
2. **Quedó código muerto:** `WaterCopy.summaryTitle` (`lib/features/water/presentation/water_copy.dart:6`)
   ya no lo usa nadie en `lib/` (verificado con `grep`).
3. **No se escribió ni un test de `R1`–`R4`.** El commit solo tocó un archivo de test
   (`test/features/leaks/leak_report_flow_test.dart`, +3 líneas: un doble de `retrieveLostData`). Las 8
   pruebas de persistencia del borrador, las de la leyenda, las del orden del paso de Ubicación y la del
   GUID **no existen**. Sin control de mutación, `R4` está **implementado pero NO verificado** — y `R4` es
   el BLOCKER del piloto.

## 2. Base: verificación obligatoria (pegar salida real, no resumida)

```bash
cd /d/Proyectos/Gota/v0.2
git log --oneline -3
git status --short
git branch --show-current
flutter analyze
flutter test
```

- **Base esperada:** `abc71ac` es el último commit de código; por encima de él hay **un commit `docs:`
  local** (`docs: prompt 10 …`) que puede no estar en `origin`. Verificá con `git log --oneline -3` y
  reportá lo que veas, sin «arreglarlo».
- **Baseline de tests: 209 declaraciones, 204 en verde y 5 en rojo** (los de `§1`). El objetivo de la
  Tanda A no es «que pasen»: es que pasen **sin debilitar aserciones** (ver `§3`).
- **Rama:** trabaja en la rama que te indique el orquestador; **no** toques `main` ni hagas `git push`.
- **Entorno:** bash MSYS, repo `D:\Proyectos\Gota\v0.2`, app Flutter Android + Supabase.
  Device físico (lo usa el orquestador): Samsung SM-A245M, Android 16, 1080x2340, serial `R58W709201M`,
  `com.gota.app`, RAM 3.77 GB. `adb` = `C:/Users/arqui/AppData/Local/Android/Sdk/platform-tools/adb.exe`.

## 3. TANDA A — reparar y completar lo ya commiteado

### A1 · Devolver la suite a verde (204 → 209)

Los 5 fallos son aserciones que quedaron apuntando a textos que el propio cambio eliminó. Se corrigen
**como actualización justificada**, conservando el resto de cada test:

- `test/features/home/community_summary_card_test.dart` (líneas 192, 206, 224, 232):
  `expect(find.text('Resumen de hoy'), findsOneWidget)` → `expect(find.text('Resumen de hoy'),
  findsNothing)`. **Se conservan todas las demás aserciones de cada caso** (métricas, sector, estado del
  agua, tarjeta visible cuando la actividad es 0/0). Ningún caso se borra y ninguno se marca `skip`.
- `test/features/water/water_screen_test.dart:85`: `expect(find.text(WaterCopy.summaryTitle),
  findsOneWidget)` → `expect(find.text('Resumen'), findsNothing)`. Las demás líneas que usan `WaterCopy`
  (`:86, 106, 114`) quedan intactas.
- **Prohibido** «arreglar» la suite borrando tests, relajando aserciones de contenido, o envolviendo en
  `skip`. Si algún caso ya no tiene sentido, se reporta como `BLOCKER` con el motivo, no se borra.

### A2 · Borrar el código muerto

- Eliminar la constante `WaterCopy.summaryTitle` de `lib/features/water/presentation/water_copy.dart:6`,
  que ya no se usa en `lib/` (verificado). `historyTitle`, `stepType` y `emptyList` **se siguen usando**:
  no las toques.
- Verificar con `grep` que no queda ninguna referencia (ni en `lib/` ni en `test/`) y pegar la salida.

### A3 · Escribir los tests que faltan (con control de mutación cada uno)

Van en `test/features/leaks/`. Store en memoria, dobles existentes, **prohibido reimplementar la lógica
de producción dentro del test** y **prohibido** un test que pase también con el cambio revertido.

De `R4` (borrador persistente) — los 8:

| # | Test | Mutación que debe ponerlo en ROJO |
|---|---|---|
| 1 | mutar el borrador (foto + datos) → el store recibe un snapshot con esos campos | no llamar a `write` |
| 2 | `build()` con snapshot válido → borrador y paso restaurados | ignorar el snapshot |
| 3 | snapshot corrupto / `schemaVersion` desconocido → estado vacío, sin excepción | propagar la excepción |
| 4 | `addPhoto` persiste **antes** de invocar el picker | mover el guardado después del picker |
| 5 | envío exitoso y `useExistingReport()` → `clear()` | no limpiar |
| 6 | TTL vencido (24 h) → no restaura y purga | ignorar el TTL |
| 7 | foto restaurada cuyo archivo ya no existe → se descarta del borrador | asumir que existe |
| 8 | lost data presente → se añade al borrador y respeta el tope de 2 fotos | ignorar lost data |

De `R1`/`R2`/`R3` (ya commiteados, hoy sin test):

- **R1:** en el paso de Ubicación, `expect(find.textContaining('Usa tu GPS'), findsNothing)`.
  Mutación: devolver la leyenda → ROJO.
- **R2:** con GPS y sugerencia cargada, la dirección queda **por encima** de la tarjeta de coordenadas:
  `tester.getTopLeft(find.text('Ubicación aproximada')).dy < tester.getTopLeft(find.textContaining('Lat:')).dy`.
  Mutación: devolver el orden anterior → ROJO. **Trampa:** en el paso los widgets viven en un `ListView`;
  lo que queda fuera de pantalla no se construye → usar `tester.scrollUntilVisible(finder, 300,
  scrollable: find.byType(Scrollable).first)` o `ensureVisible` antes de medir.
- **R3:** con un repository falso que devuelve `ReportCreated(reportId: 'abc-123')`, tras `submit()` el
  `state.message` **no** contiene `'abc-123'`. Mutación: devolver el `(ID $reportId)` → ROJO.
  No tocar `test/features/leaks/leak_report_duplicate_flow_test.dart:188,270` (afirman el título
  `'Reporte enviado'`, que se conserva).

**Evidencia obligatoria:** una línea por test con `revertido → ROJO / restaurado → VERDE`. Un test sin
esa comprobación no cuenta como entregado.

### A4 · Decisión de interpretación (confirmar en el gate)

El orden del paso de **Datos** (tarjeta de dirección vs dropdowns) quedó **anulado** como requisito: el
dueño fijó que el orden pedido es el del paso de **Ubicación** (dirección → coordenadas/precisión →
mapa) y que no se duplica información. Si el dueño dice otra cosa en el gate, es un cambio nuevo y se
especifica aparte. **No reordenes el paso de Datos por iniciativa propia.**

## 4. TANDA B — MAPA: la cámara no debe moverse sola y el refetch no debe desmontar el mapa

Objetivo del dueño: durante pan/zoom el mapa permanece montado, la cámara donde está, los tiles y los
markers visibles, y **nunca** aparece «Sin fugas para mostrar» porque una consulta esté en curso. El
estado vacío solo se muestra cuando la consulta **terminó** y el viewport **realmente** no tiene fugas.

### Hallazgos verificados en el código (no los redescubras; confírmalos antes de cambiar nada)

1. **El mapa se desmonta en la primera carga y tras un `invalidate`.** `map_screen.dart:77-79`: el
   `reportsAsync.when(...)` envuelve todo el cuerpo, y la rama `loading:` devuelve `_MapLoadingView`, que
   **reemplaza** el subárbol → el widget nativo de MapLibre se destruye. Con `skipLoadingOnReload: true`
   (`:78`) un *reload* con dato previo conserva la rama `data:`, pero **no** hay dato previo en la primera
   carga, al cambiar de modo o tras `ref.invalidate` (botón «Reintentar», `:84-88`).
2. **La cámara salta porque el centro se recalcula desde los datos.** `map_screen.dart:459+`
   (`_MapViewContent`): `_calculateSectorCenter()` deriva el centro del **bounding box de `leaks`** y lo
   pasa como `centerLat/centerLng` → `GotaMapView.initialLat/initialLng` →
   `gota_map_view.dart:204-208` (`didUpdateWidget`) → `_animateToNewCenter` (`:212-228`). Es decir: en el
   filtro «Mi sector», **cada refetch que cambia el conjunto re-centra la cámara** aunque el usuario no
   haya tocado nada. Ese es el «salto» con causa identificada.
3. **El estado vacío ya está condicionado** (`map_screen.dart:111-113`): el overlay solo aparece si
   `reports.isEmpty && !reportsAsync.isLoading`. Consérvalo.
4. **`_isMySectorWithoutSelection`** (`:39-41`, `:92-94`) devuelve `_MapEmptyView` **a propósito**: es la
   vista de guía «Configura tu sector» (sin mapa montado), y hay un test que la fija
   (`map_screen_test.dart:532-536`). **No la cambies.**
5. **`setBounds` compara los bordes con igualdad exacta de `double`** (`map_providers.dart:45-58`): un
   temblor mínimo de la región visible genera una consulta nueva. No hay debounce ni umbral.
6. **`clearBounds()` quedó sin llamadores** (`map_providers.dart:63-71`; `grep` en `lib/` solo encuentra
   la definición y el flag en `map_filter.dart:83-96`).
7. `trackCameraPosition: false` y `initialCameraPosition` solo se aplican al crear el mapa
   (`gota_map_view.dart:306-317`): la cámara **no** se reinicia por sí sola; el reinicio real viene de
   remontar el widget (hallazgo 1) o de la animación del hallazgo 2.

### Contrato

**B1 · El mapa queda montado en modo Mapa, siempre.** Reestructurar `MapScreen.build` para que, cuando
`filterState.viewMode == MapViewMode.map`, el subárbol del mapa (`_MapViewContent` → `GotaMapView`) se
construya **fuera** del `when`, y los estados pasen a ser **overlays** sobre él: carga, error (con su
botón «Reintentar») y vacío. Requisitos:
- En modo **Lista** se conserva el comportamiento actual (`loading`/`error`/`empty` reemplazan, porque no
  hay mapa montado).
- Las claves existentes **se conservan** para no romper la suite: `mapLoadingStateKey`, `mapErrorStateKey`,
  `mapEmptyStateKey`, `mapRetryKey` si existe, `gotaMapContainerKey`. En modo mapa, durante la carga debe
  seguir encontrándose `mapLoadingStateKey` (el test `map_screen_test.dart:218` la afirma) **y además**
  `gotaMapContainerKey`.
- El overlay de carga/error no debe bloquear los gestos del mapa salvo el propio error, que necesita su
  botón pulsable.

**B2 · La cámara solo se mueve por acción explícita del usuario.** Ningún cambio de datos puede moverla.
- El centro derivado de `leaks` (`_calculateSectorCenter`) deja de alimentar la cámara en cada refetch: se
  calcula **una vez por selección de sector** (y se mantiene estable mientras el sector no cambie y el
  refetch no sea por cambio de filtro/modo).
- Alternativa aceptable si es más simple y verificable: introducir en `_MapViewContent` una «intención de
  cámara» estable (`filterType` + `selectedSectorId` + acción explícita de «Mi ubicación») y pasar a
  `GotaMapView` el centro derivado de **esa** intención, no del contenido de `leaks`.
- El botón «Mi ubicación» (`_LocateButton`, `mapLocationActionProvider`) **sí** mueve la cámara: ese
  camino se conserva.
- **No cambies la firma `MapWidgetBuilder`** (`gota_map_view.dart:50-58`): 4 tests la inyectan
  (`map_screen_test.dart:138,170,212,483`). Si te resulta imprescindible cambiarla, enumerá y actualizá
  cada uso con justificación; por defecto, **prohibido**.

**B3 · Marker preservados durante el refetch.** Con dato previo, la rama `data:` sigue mostrando los
reportes anteriores hasta que llegue la nueva respuesta (`skipLoadingOnReload: true` ya lo hace): **no lo
quites** y agregá un test que lo fije (dato previo + refetch en curso → los markers anteriores siguen
presentes y el overlay de vacío **no** aparece).

**B4 · Respuestas fuera de orden.** Antes de afirmar nada, **leé la implementación instalada de Riverpod**
(`riverpod-3.4.3/lib/src/...`, `FutureProvider`/`AsyncValue`) y citá en el reporte **qué leíste**. Fija
por test lo que la implementación garantice, con un repository de latencia controlada: consulta lenta
que arranca primero + consulta rápida posterior → el estado final corresponde a la segunda. Si el
comportamiento que observás contradice lo que ibas a asumir, **eso es un hallazgo**: reportalo.

**B5 · Umbral de bounds (confirmar en el gate).** `setBounds` no debe disparar una consulta nueva por un
temblor por debajo de un umbral. Propuesta: comparar con tolerancia (`≈ 1e-5` grados, del orden de ~1 m);
**no** un temporizador/debounce, porque la cadencia real de `onCameraIdle` es dato de dispositivo y no se
puede calibrar desde el escritorio. **Antes de implementarlo**, escribe un test que cuente las llamadas
al repository (pan → 1 consulta; `onCameraIdle` repetido con la misma región → ninguna nueva) y solo si el
conteo demuestra consultas de más, aplicá el umbral. Si la medición no lo justifica, **documentá y cerrá
sin código** y decilo.

**B6 · `clearBounds` sin llamadores.** Decidí y justificá **una** de estas dos: (a) eliminarlo junto con
el flag `clearBounds` de `MapFilterState.copyWith` si nada lo usa, o (b) conservarlo con un comentario que
explique por qué sigue vivo. No lo dejes como está sin decirlo.

### Tests de la Tanda B (mutation control obligatorio)

- `data([])` en modo mapa → `gotaMapContainerKey` **y** `mapEmptyStateKey` presentes a la vez.
- estado de carga en modo mapa → `gotaMapContainerKey` **y** `mapLoadingStateKey` presentes a la vez
  (con el código actual el mapa no está: ese es el control de mutación de B1).
- «Mi sector» sin selección → sigue siendo la vista de guía, `gotaMapContainerKey` **ausente**
  (no lo rompas: `map_screen_test.dart:532-536`).
- refetch con dato previo → markers anteriores presentes y **sin** overlay de vacío.
- B2: en «Mi sector», un refetch que cambia los datos **no** cambia el centro pasado al mapa.
- B5: conteo real de llamadas al repository (según lo medido).
No mocks de MapLibre: el mapa ya se inyecta con `mapWidgetBuilderProvider`.

## 5. Fuera de alcance y prohibiciones

- **No tocar:** backend, RPC `create_leak_report`, RLS, Storage, migraciones, PostGIS, `system_config`,
  GPS/D2, autenticación, FCM/push, notificaciones/preferencias (eso es otra tanda), `package com.gota.app`,
  el proveedor de mapas (**se conserva MapLibre + estilo OpenFreeMap Liberty vía
  `MAP_TILE_STYLE_URL`/`kMapLibreDefaultStyle`; sin API key**), el contrato de reportes, el modelo de
  datos, el paso de Reportar ya verificado (salvo lo de `A4`, que está anulado) y el paso de Datos.
- **Prohibido:** `git push`; `git stash`; cambiar de rama; `npx supabase db push` en cualquier forma;
  tocar worktrees ajenos (`.claude/worktrees/**`); `--no-verify`; borrar o marcar `skip` tests
  existentes; crear infraestructura de tests nueva; duplicar dobles existentes; imprimir secretos
  (anon key, JWT, service-role, tokens, FCM) — siempre `[REDACTED]`.
- **No convertir** «la suite pasa» en evidencia de nada: el criterio es el **control de mutación**.

## 6. Entorno: trampas ya pagadas

1. `flutter build apk` muere por `JAVA_HOME` apuntando a un JDK inexistente
   (`…jdk-17.0.20.101-hotspot`). Solución: `export JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'`
   y verificar `"$JAVA_HOME/bin/java" -version`.
2. Un build fallido **deja el APK viejo** en su ruta: exigir mtime nuevo + sha256.
3. `versionName` no distingue builds (`1.0.0+1`): comparar **sha256** del APK compilado contra el
   `base.apk` extraído del device (`adb pull` del `pm path`).
4. `adb pull` a `/tmp` falla en este host: usar un directorio propio del scratch.
5. Las pantallas Flutter **no siempre aparecen en `uiautomator dump`**: localizar controles por análisis de
   píxeles del PNG.
6. Selector de fotos: «Done» ≈ `(950, 2126)`; visor Samsung, confirmar captura ≈ `(784, 2103)`.
7. Coordenadas del flujo: tab Mapa en la barra inferior; «Reintentar» del error de mapa; chips de filtro en
   la barra superior; botones de zoom en `(≈1000, 150)` y `(≈1000, 210)` aproximadamente — el orquestador
   las recalcula por píxeles.
8. En los pasos con `ListView`, lo que queda fuera de pantalla no se construye.
9. Si `adb devices` sale vacío, no concluyas: reportalo y verificá lo que sí puedas.

## 7. Gates (los corre el orquestador, y también los pega el agente al entregar)

```bash
flutter analyze     # esperado: No issues found!
flutter test        # esperado: 209 en verde (5 reparados) + los tests nuevos
```

Y por cada test nuevo: revertir el cambio → **ROJO**; restaurar → **VERDE**. Sin esa evidencia, el fix
**no está verificado**. Al final del trabajo: `git status --short` real y el conteo real de tests, sin
redondear.

## 8. Validación física (la ejecuta el orquestador en el SM-A245M)

Del prompt del dueño, los 14 pasos del mapa: 1. abrir Mapa · 2. esperar markers · 3. pan lento ·
4. pan rápido · 5. zoom in repetido · 6. zoom out repetido · 7. pan + zoom combinados · 8. repetir ≥20
ciclos · 9. entrar/salir de Mapa varias veces · 10. Inicio → Mapa → Inicio → Mapa ·
11. nunca aparece falsamente «Sin fugas para mostrar» · 12. la cámara no salta · 13. los markers se
actualizan tras el refetch · 14. el mapa no se desmonta/recrea en un refetch normal.
Evidencia: capturas + `logcat` filtrado por `MAP_NOT_READY`, `PlatformException`, `MapLibre`, `lmkd`.

Además (Home/Agua, que el prompt del dueño pedía verificar y **no se verificó**): Home sin «Resumen de
hoy» con sus métricas visibles; Agua sin «Resumen» con registro e historial funcionando.

**Criterio de aceptación del mapa:** PASS solo si pan y zoom son fluidos, no hay flash de estado vacío,
la cámara se preserva, los markers previos sobreviven al refetch y la respuesta nueva se aplica. **No se
declara PASS porque el mapa «carga».**

## 9. Commits

- **Nada de commit ni push sin autorización explícita del orquestador.** Cuando la autorice:
  - Tanda A → `fix(home,agua): repara la suite tras el cambio de copy y cubre R1-R4 con tests`
    (o el mensaje que el orquestador indique).
  - Tanda B → `fix(map): mantiene el mapa montado y la camara bajo control del usuario`.
  - Los docs van en commit `docs:` aparte. `main` no se toca sin decisión del dueño.
- No reutilices mensajes de commits existentes (`abc71ac`, `10e6826` ya existen).

## 10. Formato del reporte final

```
STATUS: <implementado / no>
BASE VERIFICADA: <salida real de §2>
CAMBIOS: <archivo:línea — qué>
TANDA Y MODELO: <quién ejecutó qué>
ANALYZE: <salida real>
TESTS: <conteo real + salida real>
MUTACIONES: <una línea por test: revertido → ROJO / restaurado → VERDE>
RIVERPOD: <qué leíste de la implementación instalada y qué concluiste (B4)>
DECISIONES: <B5 y B6: qué hiciste y por qué>
ARCHIVOS: <lista>
COMMIT: ninguno (o hash si fue autorizado)
BLOCKER: <o "ninguno">
NOT VERIFIED: <lo que no pudiste probar; el device lo cubre el orquestador>
```

Tabla **implementado vs verificado** con el comando que lo respalda. Si algo no lo ejecutaste, va como
`NOT VERIFIED`. No narres cada tool call y no expongas claves.