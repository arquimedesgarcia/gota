# PROMPT 11 — DELEGACIÓN · MAPA (Tanda B del prompt 10) + CIERRE DEL PILOTO

> Spec autocontenido: quien lo reciba no ve el chat, ni el prompt 10, ni el traspaso. Todo está aquí.
> Responde solo con el formato de `§10`, y lee el **Anexo `§11`** antes de cerrar: es la lista de lo que
> queda pendiente y no es trabajo de esta tanda.

## 0. Rol, gate de arranque y política de modelos

Eres el agente codificador de Gota. Implementas con tests reales y **no reportas como verificado nada que
no hayas ejecutado**. Antes de tocar código:

1. Corre los comandos de `§2` y confirma base y estado (incluido el aviso del **worktree obsoleto**).
2. Propón con `clarify`: (a) plan, (b) quién ejecuta y **qué modelo**, (c) la confirmación de `B5` (umbral
   de bounds) y `B6` (`clearBounds`).
3. **No ejecutes nada** (ni `flutter`, ni `git` de escritura, ni builds) hasta la aprobación del dueño.

Política de motores (instrucción explícita del dueño: *«no uses Sonnet para test, para test usa un modelo
gratuito o muy barato»*):

| Tarea | Motor |
|---|---|
| Tests, copy, cambios mecánicos | gratis o lo más barato: `opencode run --model opencode/ling-3.0-flash-fin-free` ($0, probado), Copilot `gpt-5-mini` por cuota, Ollama local (`qwen3-coder-instruct-128k`) |
| Diagnóstico y refactor con criterio | Sonnet |
| Arquitectura y dictámenes | Opus |
| Verificación mecánica (analyze/test/mutación/adb/git) | el orquestador (Hermes), no un agente |

Esta tanda es **una sola**: el mapa. Es un refactor con criterio sobre el ciclo de vida del `Widget` y el
viewport → **Sonnet**. Los tests que acompañan van con el mismo motor (es el mismo contrato), pero
**ningún test escrito cuenta como entregado sin su control de mutación**, y si el motor pago falla en
escribirlos bien, el reintento va con un modelo gratuito.

## 1. Dónde estamos (verificado por el orquestador, no por el agente)

- `main` @ `fb55dfe` = `origin/main`. **Nada pendiente de push.**
- **Suite verde 221/221** (`flutter test` corrido por el orquestador sobre `main`).
- **La Tanda A del prompt 10 está HECHA**: los 5 fallos de Home/Agua reparados, la constante muerta
  `WaterCopy.summaryTitle` eliminada, y **11 tests nuevos** (`test/features/leaks/leak_report_copy_test.dart`
  → R1/R2/R3; `test/features/leaks/leak_report_draft_test.dart` → T4-1…T4-8 del borrador persistente).
- **El prompt del dueño «ajustes finales Home y Agua» ya está aplicado en el código**: los textos
  `'Resumen de hoy'` y `WaterCopy.summaryTitle` no se renderizan y la suite lo fija. **No se re-ejecuta.**
  Lo único que falta de ese prompt es la **verificación física**, que nunca se hizo (ver `§8`).
- **El mapa sigue sin tocar.** Estado exacto del código: `map_screen.dart:77-98` (la rama `loading:`
  reemplaza todo el subárbol), `_calculateSectorCenter()` (`:475`) alimentando la cámara vía `:499/:504`,
  y `setBounds` comparando `double` con igualdad exacta (`map_providers.dart:45-58`).

### Aviso crítico: hay un worktree con base OBSOLETA

`git worktree list` muestra `D:/Proyectos/Gota/gota-p10` en la rama **`fix/prompt10-suite-y-mapa`**, con
HEAD en **`acffe6a`** — es decir, **antes** de `fb55dfe`, cuando la suite tenía los 5 tests rojos. Si
trabajás ahí sin actualizar la base:

- verás 5 fallos que ya no existen y podrías «arreglarlos» otra vez (rompiendo la historia),
- y tus tests nuevos correrían sobre una base distinta de la de `main`.

**Antes de empezar:** actualizá ese worktree a `fb55dfe` (`git merge --ff-only main` con el worktree
limpio, o recreá el worktree desde `fb55dfe`) y **reportá el comando y el `git log --oneline -1` resultante**.
Si preferís no tocar ese directorio, pedí al orquestador una rama nueva. **Prohibido** trabajar sobre
`main` directamente y **prohibido** `git push`.

## 2. Verificación obligatoria de base (pegar salida real, no resumida)

```bash
cd /d/Proyectos/Gota/v0.2
git log --oneline -3
git status --short
git branch --show-current
git worktree list
flutter analyze
flutter test
```

- **Base esperada:** `fb55dfe`. **Tests esperados: 221 en verde.** Si ves otra cosa, pará y reportalo; no
  «arregles» la base por tu cuenta.
- **Entorno:** bash MSYS, repo `D:\Proyectos\Gota\v0.2`, app Flutter Android + Supabase.
  Device físico (lo usa el orquestador): Samsung SM-A245M, Android 16, 1080x2340, serial `R58W709201M`,
  paquete `com.gota.app`, RAM 3.77 GB; `adb` =
  `C:/Users/arqui/AppData/Local/Android/Sdk/platform-tools/adb.exe`.
- Estilo de mapa: **OpenFreeMap Liberty vía `MAP_TILE_STYLE_URL`/`kMapLibreDefaultStyle`**. Sin API key.

## 3. Objetivo (el pedido del dueño, tal cual)

Durante pan/zoom el mapa **permanece montado**, la cámara se queda donde está, los tiles y los markers
siguen visibles, y **nunca** aparece «Sin fugas para mostrar» porque una consulta esté en curso. El estado
vacío se muestra **solo** cuando la consulta terminó **y** el viewport realmente no tiene fugas. La cámara
no debe volver a `initialCameraPosition` ni saltar sola. No cambiar el proveedor de mapas, ni MapLibre, ni
el backend.

## 4. Hallazgos verificados en el código (confírmalos antes de cambiar nada)

1. **El mapa se desmonta en la primera carga y tras un `invalidate`.** `map_screen.dart:77-79`: el
   `reportsAsync.when(...)` envuelve todo el cuerpo y la rama `loading:` devuelve `_MapLoadingView`, que
   **reemplaza** el subárbol → el widget nativo de MapLibre se destruye. `skipLoadingOnReload: true`
   (`:78`) conserva la rama `data:` en un *reload* con dato previo, pero **no** cuando no hay dato previo
   (primera carga, cambio de modo, o `ref.invalidate` del botón «Reintentar», `:84-88`).
2. **La cámara salta porque el centro se recalcula desde los datos.** `_MapViewContent` (`:459+`) deriva
   `_calculateSectorCenter()` del **bounding box de `leaks`** y lo pasa como `centerLat/centerLng` (`:499`,
   `:504`) → `GotaMapView.initialLat/initialLng` → `gota_map_view.dart:204-208` (`didUpdateWidget`) →
   `_animateToNewCenter` (`:212-228`). En «Mi sector», **cada refetch que cambia el conjunto re-centra la
   cámara** sin que el usuario toque nada. Esa es la causa identificada del «salto».
3. **El estado vacío ya está condicionado** (`:111-113`): overlay solo si
   `reports.isEmpty && !reportsAsync.isLoading`. **Consérvalo.**
4. **`_isMySectorWithoutSelection`** (`:39-41`, `:92-94`) devuelve `_MapEmptyView` **a propósito**: es la
   vista de guía «Configura tu sector», sin mapa montado, y hay un test que la fija
   (`map_screen_test.dart:532-536`). **No la cambies.**
5. **`setBounds` compara bordes con igualdad exacta de `double`** (`map_providers.dart:45-58`): un temblor
   mínimo de la región visible genera una consulta nueva. No hay debounce ni umbral.
6. **`clearBounds()` no tiene llamadores** (`map_providers.dart:63-71`; el `grep` solo encuentra la
   definición y el flag `clearBounds` en `map_filter.dart:83-96`).
7. `trackCameraPosition: false` e `initialCameraPosition` se aplican **solo al crear** el mapa
   (`gota_map_view.dart:306-317`): la cámara no se reinicia sola; el reinicio real viene de remontar el
   widget (hallazgo 1) o de la animación del hallazgo 2.

## 5. Contrato

**B1 · El mapa queda montado en modo Mapa, siempre.** Reestructurar `MapScreen.build` para que, con
`filterState.viewMode == MapViewMode.map`, el subárbol del mapa (`_MapViewContent` → `GotaMapView`) se
construya **fuera** del `when`, y carga / error / vacío pasen a ser **overlays** sobre él.

- En modo **Lista** se conserva el comportamiento actual (los estados reemplazan: no hay mapa montado).
- **Se conservan las claves** (`mapLoadingStateKey`, `mapErrorStateKey`, `mapEmptyStateKey`,
  `gotaMapContainerKey`): en modo mapa, durante la carga deben estar presentes **las dos** —
  `mapLoadingStateKey` (el test `map_screen_test.dart:218` la afirma) **y** `gotaMapContainerKey`.
- El error mantiene su botón «Reintentar» pulsable; el overlay de carga no debe bloquear gestos.

**B2 · La cámara solo se mueve por acción explícita del usuario.** Ningún cambio de datos puede moverla.

- El centro derivado de `leaks` deja de alimentar la cámara en cada refetch: se calcula **una vez por
  selección de sector** y se mantiene estable mientras el sector no cambie.
- Alternativa aceptable si resulta más simple y verificable: una «intención de cámara» estable en
  `_MapViewContent` (`filterType` + `selectedSectorId` + acción explícita de «Mi ubicación») y pasar a
  `GotaMapView` el centro derivado de **esa** intención, no del contenido de `leaks`.
- El botón «Mi ubicación» (`_LocateButton`, `mapLocationActionProvider`) **sí** mueve la cámara: se
  conserva.
- **No cambies la firma `MapWidgetBuilder`** (`gota_map_view.dart:50-58`): 4 tests la inyectan
  (`map_screen_test.dart:138,170,212,483`). Por defecto **prohibido**; si fuera imprescindible, enumerá y
  actualizá cada uso con justificación.

**B3 · Markers preservados durante el refetch.** Con dato previo, la rama `data:` sigue mostrando los
reportes anteriores hasta que llegue la respuesta nueva (`skipLoadingOnReload: true`): **no lo quites** y
agregá un test que lo fije (dato previo + refetch en curso → markers anteriores presentes y **sin** overlay
de vacío).

**B4 · Respuestas fuera de orden.** Antes de afirmar nada, **leé la implementación instalada de Riverpod**
(`riverpod-3.4.3/lib/src/...`: `FutureProvider`, `AsyncValue`) y **citá en el reporte qué leíste**. Fijá
por test lo que esa implementación garantice, con un repository de latencia controlada: consulta lenta
primero + consulta rápida después → el estado final corresponde a la segunda. Si lo que observás contradice
lo que ibas a asumir, **eso es un hallazgo**: reportalo, no lo maquilles.

**B5 · Umbral de bounds (confirmar en el gate).** `setBounds` no debería disparar consulta nueva por un
temblor por debajo de un umbral. Propuesta: tolerancia (`≈ 1e-5` grados, del orden de ~1 m). **No** un
temporizador/debounce: la cadencia real de `onCameraIdle` es dato de dispositivo y no se calibra desde el
escritorio. **Antes de implementarlo**, escribí un test que cuente las llamadas al repository (pan → 1
consulta; `onCameraIdle` repetido con la misma región → ninguna nueva). Si la medición no justifica el
umbral, **documentá y cerrá sin código**, y decilo.

**B6 · `clearBounds` sin llamadores.** Decidí y justificá **una**: (a) eliminarlo junto con el flag
`clearBounds` de `MapFilterState.copyWith` si nada lo usa, o (b) conservarlo con un comentario que explique
por qué sigue vivo. No lo dejes sin decir nada.

## 6. Tests obligatorios (con control de mutación, uno por uno)

- `data([])` en modo mapa → `gotaMapContainerKey` **y** `mapEmptyStateKey` presentes a la vez.
- carga en modo mapa → `gotaMapContainerKey` **y** `mapLoadingStateKey` presentes a la vez (con el código
  actual el mapa no está: **ese es el control de mutación de B1**).
- «Mi sector» sin selección → vista de guía, `gotaMapContainerKey` **ausente** (no rompas
  `map_screen_test.dart:532-536`).
- refetch con dato previo → markers anteriores presentes y **sin** overlay de vacío.
- B2: en «Mi sector», un refetch que cambia los datos **no** cambia el centro pasado al mapa.
- B5: conteo real de llamadas al repository, según lo que hayas medido.
- B4: respuesta fuera de orden, según lo que la implementación garantice.

Nada de mocks de MapLibre: el mapa ya se inyecta con `mapWidgetBuilderProvider`. **Evidencia obligatoria:**
una línea por test con `revertido → ROJO / restaurado → VERDE`. Un test sin esa comprobación no cuenta.

## 7. Fuera de alcance y prohibiciones

- **No tocar:** backend, RPC `create_leak_report`, RLS, Storage, migraciones, PostGIS, `system_config`,
  GPS/D2, autenticación, FCM/push, notificaciones/preferencias (otra tanda), `com.gota.app`, el contrato de
  reportes, el modelo de datos, el proveedor de mapas (MapLibre + OpenFreeMap Liberty, sin API key), los
  pasos de Ubicación/Datos de Reportar, Home y Agua (ya cerrados), y los tests existentes de la Tanda A.
- **Prohibido:** `git push`; `git stash`; cambiar de rama sin autorización; `npx supabase db push` en
  cualquier forma; tocar los worktrees ajenos (`.claude/worktrees/**`); `--no-verify`; borrar o marcar
  `skip` tests; crear infraestructura de tests nueva; duplicar dobles; imprimir secretos (anon key, JWT,
  service-role, tokens, FCM) — siempre `[REDACTED]`.
- **La suite verde no es evidencia**: el criterio es el control de mutación.

## 8. Validación física (la ejecuta el orquestador en el SM-A245M)

**Mapa — los 14 pasos del dueño:** 1. abrir Mapa · 2. esperar markers · 3. pan lento · 4. pan rápido ·
5. zoom in repetido · 6. zoom out repetido · 7. pan + zoom combinados · 8. repetir ≥20 ciclos ·
9. entrar/salir de Mapa varias veces · 10. Inicio → Mapa → Inicio → Mapa · 11. nunca aparece falsamente
«Sin fugas para mostrar» · 12. la cámara no salta · 13. los markers se actualizan tras el refetch ·
14. el mapa no se desmonta/recrea en un refetch normal.

**Reportar — los 16 pasos del prompt anterior (siguen sin verificarse):** reporte GPS · reverse-geocode ·
municipio/sector preseleccionados · «Continuar» sin tocar nada · 1 foto por cámara · 1 foto por galería ·
intentar la tercera · cancelar cámara · cancelar galería · repetir cámara/galería · completar el reporte ·
sin GUID en la confirmación · coordenadas GPS como fuente de verdad · **el orden del paso de Ubicación
(dirección → coordenadas/precisión → mapa)** · **el borrador sobrevive al kill por cámara** (el pid cambia,
pero al reabrir el asistente el borrador está, con la foto recuperada por `retrieveLostData`) ·
**el banner «Recuperamos tu reporte sin enviar» aparece y «Descartar» limpia el borrador y sus fotos**.

**Home y Agua — los 3 puntos del prompt del dueño que nunca se verificaron en device:** banner correcto ·
tarjeta con sus métricas y sin «Resumen de hoy» · Agua sin «Resumen», con registro e historial funcionando.

Evidencia: capturas + `logcat` filtrado por `MAP_NOT_READY`, `PlatformException`, `MapLibre`, `lmkd`,
`Zygote`. **Criterio de aceptación del mapa:** PASS solo si pan y zoom son fluidos, no hay flash de estado
vacío, la cámara se preserva, los markers previos sobreviven al refetch y la respuesta nueva se aplica.
**No se declara PASS porque el mapa «carga».**

## 9. Commits

- **Nada de commit ni push sin autorización explícita del orquestador.** Cuando la autorice: **un** commit
  para el mapa, propuesta de mensaje `fix(map): mantiene el mapa montado y la camara bajo control del
  usuario`; los docs, en commit `docs:` aparte. No reutilices mensajes existentes (`abc71ac`, `fb55dfe`,
  `10e6826` ya existen).

## 10. Formato del reporte final

```
STATUS: <implementado / no>
BASE VERIFICADA: <salida real de §2 + qué hiciste con el worktree obsoleto>
CAMBIOS: <archivo:línea — qué>
MODELO: <quién ejecutó>
ANALYZE: <salida real>
TESTS: <conteo real + salida real>
MUTACIONES: <una línea por test: revertido → ROJO / restaurado → VERDE>
RIVERPOD: <qué leíste y qué concluiste (B4)>
DECISIONES: <B5 y B6: qué hiciste y por qué>
ARCHIVOS: <lista>
COMMIT: ninguno (o hash si fue autorizado)
BLOCKER: <o "ninguno">
NOT VERIFIED: <lo que no pudiste probar; el device lo cubre el orquestador>
```

Tabla **implementado vs verificado** con el comando que lo respalda. Lo que no ejecutaste va como
`NOT VERIFIED`. No narres cada tool call ni expongas claves.

## 11. ANEXO — lo que sigue pendiente después de esta tanda (no es trabajo tuyo)

Para que el orquestador cierre el piloto, esto queda abierto y en este orden:

1. **Mutación de la Tanda A, reverificada.** El commit `fb55dfe` documenta explícitamente **solo** la
   mutación de R3; los controles de mutación de `T4-1…T4-8` son afirmación del agente, **no verificados por
   el orquestador**. Hay que revertir y correr cada uno antes de dar `R4` por verificado (y `R4` es el
   BLOCKER del piloto).
2. **`T4-7` revisado contra el spec.** El test se llama «foto restaurada cuyo archivo no existe se descarta
   **silenciosamente**», y el spec pedía **informar** al usuario, no silenciar. Confirmar en device si el
   usuario ve algo; si no, es una brecha de UX a decidir.
3. **T3 · prompt 6 (`_isSaving`)**: sustituir `copyWithPrevious` (API `@internal` de Riverpod, hoy en
   `notification_providers.dart:69` con `// ignore: invalid_use_of_internal_member`) conservando el valor
   visible durante el guardado. Spec: `docs/PROMPT_6_IS_SAVING_2026-09-23.md`. Criterio: `grep -c
   copyWithPrevious|invalid_use_of_internal_member` en `lib/` → **0**, sin romper los 4 tests del H4.
4. **T4 · A1/A2 (límite de fotos en la base)**: `system_config.photo_limits.max_count` de 3 a 2 en local
   (Docker `supabase_db_gota`, `psql` con `SELECT` antes y después) y en el **cloud piloto**
   (`eghphmugrrbvbvodhasq`) **solo** con `npx supabase db query --linked -f <archivo.sql>`, con aprobación
   explícita del dueño. **Prohibido `npx supabase db push`**.
5. **T6 · higiene**: podar los cinco worktrees de `.claude/worktrees/*` (`tanda1-fotos`, `tanda1-mapa`,
   `tanda1-sector`, `tanda2-continuar`, `tanda2-tests-free`), el worktree `gota-p10` cuando termine esta
   tanda, y los `PROMPT*.md` sin trackear. El único a **no** borrar sin revisar es
   `.claude/worktrees/agent-a429749783d7a8538`.
6. **F6 · veredicto del gate**: re-auditoría (analyze + tests + SQL + E2E crítico + smoke en device) y
   veredicto `READY FOR CONTROLLED PILOT`. Hoy el gate sigue **BLOCKER = 1** (memoria/cámara) hasta que la
   corrida de device demuestre que el borrador sobrevive al kill.
7. **APK del piloto**: reconstruir desde el commit verificado y **probar con sha256** que el device corre
   ese build (el `versionName` no cambia). No distribuir antes del veredicto F6.