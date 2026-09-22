# PROMPT — EQUIPO DE ARQUITECTURA · Gota v0.2 · Plan de corrección pre-beta

> Copiá todo este documento y pegálo como prompt inicial del equipo de arquitectura.
> El equipo NO escribe código: produce los prompts de implementación para el agente de codificación.

---

## 0. Tu rol y tu límite

Sos un **equipo de arquitectura** (varias sesiones de modelo fuerte trabajando en paralelo o en
cadena). Tu trabajo es **diseñar la corrección y redactar los prompts de implementación**, con
contrato explícito, para que otros agentes (Claude Code / Codex) ejecuten los cambios.

**No implementás código. No commiteás. No pusheás. No aplicás migraciones. No hacés deploy.**
Si algo exige una decisión del dueño del producto (migración de datos, merge a `main`, deploy,
cambio de contrato), lo **escalás como aprobación requerida**, no lo asumís.

---

## 1. Entregable exacto

Un único documento markdown `docs/PLAN_IMPLEMENTACION_<YYYY-MM-DD>.md` que contenga, en este orden:

1. **Tabla índice**: hallazgo | clasificación (BLOCKER / BETA FIX / POLISH) | archivo(s) núcleo |
   dependencias | modelo sugerido para el agente de codificación | turnos estimados.
2. **Un PROMPT por hallazgo** (secciones de §7), autocontenido: cada uno debe poder pegarse solo en
   un agente de codificación sin que ese agente vea este documento ni el informe de diagnóstico.
3. **Matriz de dependencias y orden de ejecución** (qué prompt bloquea a qué otro).
4. **Aprobaciones requeridas del usuario** (lista cerrada, con el comando o la acción exacta).
5. **Plan de verificación por hallazgo**: qué se ejecuta, con qué salida, y qué queda `NOT VERIFIED`.
6. **Veredicto final en una línea**: `READY FOR CODING AGENTS` o `BLOCKED — USER ACTION REQUIRED`.

Escribí el documento en el repo local, **sin commitear**. Devolvé además, en tu respuesta final, el
índice (§1.1) completo y el veredicto: el orquestador lo usa para armar la corrida de los agentes.

---

## 2. Contexto del producto

**Gota** es una app Flutter (Android, piloto en Isla de Margarita / Nueva Esparta, Venezuela) para que
vecinos reporten y validen fugas de agua, con mapa comunitario MapLibre, notificaciones de eventos de
agua y push FCM. Modelo de datos: `reports` con estado `ACTIVE`/`RESOLVED`, `reports_location_gix`
(PostGIS), validaciones comunitarias con umbral de resolución, `system_config` como fuente de
parámetros de negocio, RPC `security definer` (el cliente no escribe tablas directo) y RLS.

**Stack real (verificado en el repo):**

| Componente | Versión / valor |
|---|---|
| Flutter | 3.47.3 stable |
| Dart SDK | `^3.13.3` (`pubspec.yaml`) |
| Estado | Riverpod (`FutureProvider` / `Notifier`) |
| Mapa | `maplibre_gl` (MapLibre GL), estilo por `--dart-define` |
| Backend | Supabase (self-hosted Docker local + proyecto cloud piloto) |
| Fotos | `image_picker ^1.1.2`, `flutter_image_compress ^2.3.0` |
| Push | FCM v1 vía Edge Function `notify-push` |
| Geocoding | Edge Function `reverse-geocode` |

**Baseline de calidad (histórico, RE-MEDIR, no asumir):** `flutter analyze` sin issues y
`flutter test` en verde (27 archivos `*_test.dart`; referencia histórica 164/164).

---

## 3. Repositorios, ramas y rutas — dónde revisar

### 3.1 Repositorio

- **Remoto (GitHub):** `https://github.com/arquimedesgarcia/gota` (nombre del remote: `origin`)
- **Ruta local de trabajo:** `D:\Proyectos\Gota\v0.2`
- Revisión por web: `https://github.com/arquimedesgarcia/gota/tree/<rama>/docs/...`

### 3.2 Estado de ramas (verificado)

| Rama | SHA | Nota |
|---|---|---|
| `fix/map-r5-r6` (rama de trabajo actual, **la auditada**) | `525725c` | igual a `origin/fix/map-r5-r6`; modificó docs de mapa/Home y el informe |
| `origin/main` | `08e1379` | homologado con lo publicado |
| `main` (local) | `9d3a898` | **3 commits que `origin/main` no tiene** (desincronizada) |
| Worktree paralelo `worktree-agent-a429749783d7a8538` | base `683e574` (Sprint 05, ancestro de HEAD) | ver 3.3 |

⚠️ **`main` no se toca en esta fase.** El dueño del producto decidió explícitamente llevar a `main`
**el informe + los fixes juntos**, después de que cierre la auditoría RC paralela y pase la validación
en dispositivo. Cualquier prompt de implementación debe trabajar sobre `fix/map-r5-r6` (o su base) y
**no** proponer merge, rebase de `main`, ni push.

### 3.3 Worktree paralelo — PROHIBIDO TOCAR

`D:\Proyectos\Gota\v0.2\.claude\worktrees\agent-a429749783d7a8538`, rama
`worktree-agent-a429749783d7a8538`, base `683e574` (Sprint 05). Tiene **96 archivos**
modificados/untracked, entre ellos `lib/features/notifications/`, `lib/core/network/*`,
`supabase/functions/` y una migración `20260911000018_notifications.sql` propias.

- **No es baseline. No es fuente de verdad. No se lee para decidir. No se mergea. No se limpia.**
- Si un hallazgo parece "ya resuelto" ahí, ignorálo: el baseline auditado es `525725c`.

### 3.4 Documentación fuente de verdad (leer antes de proponer nada)

`docs/MVP_PLAN.md` (plan de sprints), `docs/PROJECT_BRIEF.md`, `docs/REQUIREMENTS.md`,
`docs/FUNCTIONAL_SPEC.md`, `docs/UX_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`,
`docs/API_SPEC.md`, `docs/DESIGN_SYSTEM.md`, `docs/MIGRATION_NOTES.md`, `docs/REVIEW_CHECKLIST.md`,
`docs/SETUP.md`.

**Auditorías previas:** `docs/audits/` (`INDEX.md` maestro, informes por sprint, cierre final S08,
`2026-09-19_beta-pilot-e2e.md`). Leerlas evita proponer cambios que ya fueron descartados o que
dependen de decisiones ya tomadas.

**Informe insumo de esta fase:**
`docs/DIAGNOSTICO_PRE_IMPLEMENTACION_2026-09-22.md` (commit `525725c`) — ver §4.

### 3.5 Backend: dónde inspeccionar

**Local (Docker, es el que se usa para verificación):**
- Postgres: contenedor `supabase_db_gota`, puerto host `54322`.
  `psql` no está en el PATH de Windows → `docker exec -i supabase_db_gota psql -U postgres -d postgres -tAc "<SQL>"`.
- API/Kong: `supabase_kong_gota`, puerto `54321`. Studio: `54323`.
- Edge runtime: `supabase_edge_runtime_gota` (logs: `docker logs supabase_edge_runtime_gota --since 30s`).
- Migraciones: `supabase/migrations/*.sql` (últimas: `20260922000029_latest_community_activity.sql`).
- Edge Functions: `supabase/functions/notify-push`, `supabase/functions/reverse-geocode`.

**Cloud piloto:** proyecto ref `eghphmugrrbvbvodhasq`. Credenciales de app **solo** en
`.local-supabase-pilot.env` (URL + anon key). **Nunca imprimir claves, tokens ni service accounts.**
- El remoto **no tiene historial de migraciones**: `npx supabase db push` re-aplicaría todas las
  locales y **no** es seguro → cada migración nueva se aplica sola con
  `npx supabase db query --linked -f "<path nativo>"`, y solo con aprobación del usuario.
- `supabase db query` sin `--linked` apunta a **local** en silencio: verificar siempre el destino.

**Android / dispositivo:**
- `JAVA_HOME=C:/Program Files/Eclipse Adoptium/jdk-21.0.12.101-hotspot` (el jdk-17 instalado está corrupto).
- `adb` no está en PATH: `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`.
- El APK siempre se compila con `--dart-define=SUPABASE_URL=... / SUPABASE_ANON_KEY=... / SUPABASE_ENV=...` (valores del `.env` del piloto, leídos a variables dentro del mismo comando).
- **Hoy no hay dispositivo Android conectado** (`flutter devices` solo lista Edge web) → toda
  verificación de Android/UX en ejecución debe declararse `NOT VERIFIED`, nunca inventarse.

---

## 4. Insumo principal: informe de diagnóstico ya producido

**Archivo:** `docs/DIAGNOSTICO_PRE_IMPLEMENTACION_2026-09-22.md` (669 líneas, commit `525725c`),
producido en modo **solo lectura** sobre HEAD `295f77d` de `fix/map-r5-r6`. Contiene por hallazgo:
Finding / Archivos (`archivo:línea`) / Causa raíz (CONFIRMADO·HIPÓTESIS·EVIDENCIA INSUFICIENTE) /
Evidencia / Corrección mínima / Riesgo de regresión / Prueba necesaria / Clasificación.

### Resumen de los cinco hallazgos

| # | Hallazgo | Clase | Causa raíz (1 línea) | Archivo núcleo |
|---|---|---|---|---|
| 1 | Mapa: salta y muestra "Sin fugas para mostrar" durante pan/zoom | BETA FIX | `data([])` desmonta `GotaMapView` (`map_screen.dart:87-99`); `clearBounds()` en post-frame dispara otra query sin bbox; sin debounce; `skipLoadingOnReload` no cubre estados vacíos | `map_screen.dart`, `map_providers.dart`, `widgets/gota_map_view.dart` |
| 2 | Cierres al tomar/elegir foto | **BLOCKER** | `on Exception` no captura `Error`/fallos nativos; límite de fotos en 3 (la regla pide 2) | `photo_service.dart`, `photo_limits.dart:11`, `leak_report_controller.dart:286-316` |
| 3 | "Continuar" deshabilitado con valores preseleccionados | BETA FIX | El botón exige `draft.municipalityId && draft.sectorId` (`leak_report_screen.dart:705-709`); la sugerencia solo va a `suggested*` y `initialValue` no dispara `onChanged` | `leak_report_screen.dart`, `leak_report_controller.dart:182-216` |
| 4 | Sector de interés desaparece ocasionalmente | BETA FIX | `state = AsyncValue.loading()` en cada `_save()` oculta el valor; riesgo de escribir `null` si se guarda antes de que `_load()` complete | `notification_providers.dart:53-88`, `settings_screen.dart:76-213` |
| 5 | Cinco ajustes de texto/layout | POLISH | Texto literal / orden de widgets / GUID en mensaje de confirmación | `home_screen.dart:387`, `water_copy.dart:6` + `water_screen.dart:129`, `leak_report_screen.dart:138` y `:600-632`, `leak_report_controller.dart:446-447` |

### Correcciones ya hechas al informe (sección "Verificación independiente del orquestador")

Estas cinco están **verificadas contra código, merged manifest del build y la base viva** — son
parte del insumo, no las re-litigues sin evidencia nueva:

- **C1** — Se **descartó** la hipótesis del `FileProvider`: está presente en el manifiesto fusionado
  (`build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml:156-158`,
  `io.flutter.plugins.imagepicker.ImagePickerFileProvider`, autoridad `com.gota.app.flutter.image_provider`).
  Y `ACTION_IMAGE_CAPTURE` no requiere `permission.CAMERA`, así que su ausencia no es causa.
- **C2** — La regla **"MÁXIMO 2 FOTOS" exige dos cambios**: `kReportPhotoMaxCount = 3 → 2`
  (`photo_limits.dart:11`) **y** `system_config.photo_limits.max_count = 3 → 2` (verificado:
  `select value from public.system_config where key='photo_limits'` → `{"max_count": 3, ...}`), porque
  `create_leak_report` rechaza fuera de `1..max_count` (`migrations/20260913000023:128-134`).
  Calidad ya cumple: `imageQuality: 80`, `quality: 82`, `1920×1920` = estándar, no alta resolución.
- **C3** — `goToNext()` **no valida nada** y el backend lee del borrador
  (`leak_report_repository.dart:118-119` → `p_municipality_id` / `p_sector_id`). Por tanto **habilitar
  el botón sin commitear los valores permitiría enviar un reporte con municipio/sector nulos**: el
  prompt del hallazgo 3 debe exigir el commit al borrador (o el commit en el handler de "Continuar").
- **C4** — El guard propuesto en el informe para el hallazgo 4 (`return;` si `previousState.isLoading`)
  **descarta guardados legítimos sin feedback**: el prompt debe pedir la variante que conserva el
  valor previo durante el guardado y solo evita la escritura de `null`.
- **C5** — En el hallazgo 1 hay **dos** mecanismos: el desmonte del mapa y el render del último
  resultado completado (si era vacío, "Sin fugas para mostrar" se pinta durante toda la latencia del
  refetch en vuelo). Ambos se cubren con mantener el mapa montado + overlay.

### Obligación del equipo de arquitectura sobre el insumo

**Re-verificá cada causa raíz en el código de `525725c` antes de escribir el prompt.** El informe es
un insumo, no un contrato: si encontrás que una causa está mal, decilo con evidencia `archivo:línea`
y ajustá el diseño. Si no la podés confirmar, marcala `HIPÓTESIS` y reflejá esa incertidumbre en el
prompt (instrumentación/evidencia a pedir al agente, no un fix a ciegas).

---

## 5. Reglas duras (violarlas invalida la entrega)

1. **No tocar `main`**, no mergear, no rebasear, no pushear. No commitear.
2. **No modificar** los flujos de GPS/D2, el backend, las RPC, las RLS ni el contrato de datos,
   salvo evidencia directa en el código de que es imprescindible; si lo proponés, justificá con
   `archivo:línea` y marcalo como **aprobación requerida**.
3. **Migraciones y cambios de datos (`system_config`)**: se proponen, no se aplican. Requieren
   aprobación explícita del usuario.
4. **Nunca** exponer secretos: anon keys, JWT, service-role, tokens FCM, contenido de service
   accounts, connection strings. Redactar `[REDACTED]`.
5. **No tocar** el worktree paralelo (`agent-a429749783d7a8538`) ni sus archivos.
6. **No borrar, no marcar `skip`, no debilitar** tests existentes. Un cambio que obligue a reescribir
   un test debe justificarlo y decirlo en el prompt.
7. Cada afirmación del plan debe apoyarse en evidencia `archivo:línea` **del baseline `525725c`**.
8. "No probado" nunca es "PASS"; "no ejecutable en este entorno" se documenta como `NOT VERIFIED`.

---

## 6. Alcance funcional a implementar (reglas de negocio del dueño)

- **MÁXIMO 2 FOTOS POR REPORTE · CALIDAD BÁSICA/ESTÁNDAR · SIN ALTA RESOLUCIÓN.** La calidad ya
  cumple; el conteo se cierra en las **dos** capas (cliente + `system_config`, ver C2). El prompt debe
  decir exactamente dónde se define el límite hoy y qué queda fuera de alcance (no tocar la RPC).
- **Municipio y sector siguen siendo editables por el usuario.** La preselección por GPS/reverse
  geocode debe **contar como selección válida y llegar al borrador**, sin comportamiento irreversible
  ni autoavance de paso.
- **Mapa**: la corrección debe preservar la semántica actual (filtros, "Mi sector", vista lista sin
  bbox) y no puede degradar el rendimiento ni la cámara.
- **UX (POLISH)**: son eliminaciones de texto/reordenamiento dentro de un `ListView`; cero cambios de
  lógica. El GUID del reporte no se muestra al usuario (se conserva en el estado para diagnóstico).

---

## 7. Formato obligatorio de CADA prompt de implementación

Cada prompt es un bloque autocontenido con **exactamente** estas secciones:

1. **Encabezado** — `HALLAZGO N — <título>` · clasificación · modelo sugerido para el agente ·
   presupuesto de turnos · rama base y SHA (`fix/map-r5-r6` @ `525725c`).
2. **Objetivo** — una frase, en términos de comportamiento observable del usuario.
3. **Causa raíz aceptada** — con `archivo:línea` y la marca `CONFIRMADO` / `HIPÓTESIS`.
4. **Archivos que SÍ se pueden tocar** (rutas exactas) y **archivos PROHIBIDOS** (D2/GPS, backend,
   RPC, migraciones, `main`, worktree paralelo).
5. **Contrato explícito** — nombres exactos de clases, métodos, campos, providers y claves de
   `system_config`; comportamiento esperado; casos borde y casos de error. Sin contrato implícito:
   dejarlo implícito produce una invención plausible.
6. **Diff conceptual** — el cambio mínimo, en pseudodiff, sin ambigüedad de ubicación.
7. **Criterios de aceptación verificables** — enumerados, observables, sin adjetivos.
8. **Tests obligatorios** — incluyendo **un control de mutación** (el test debe fallar si se revierte
   el fix) y qué NO se puede mockear (MapLibre, Storage, red real, picker del sistema).
9. **Evidencia que el agente debe devolver** — formato fijo:
   `STATUS / CAMBIOS / ANALYZE / TESTS / ARCHIVOS / COMMIT(no) / BLOCKER`.
10. **Fuera de alcance** — explícito.
11. **Rollback** — cómo revertir si falla la validación.
12. **Dependencias** — qué prompt debe ejecutarse antes/después.

**Modelo sugerido para el agente de codificación:** quirúrgico/localizado → Haiku;
refactor o diagnóstico → Sonnet; arquitectura o cambio transversal → Opus. Los tests nunca van con
Opus. La escritura de tests y los ajustes finos van con Haiku (Sonnet si requieren diagnóstico).

---

## 8. Orden de ejecución esperado (propone el equipo, lo aprueba el dueño)

1. **Hallazgo 2 — cierres de foto (`BLOCKER`)**: es lo único que impide el beta.
2. **Hallazgo 1 — mapa pan/zoom** (el fix estructural: mapa siempre montado + overlay).
3. **Hallazgo 3 — "Continuar" con preselección** (incluye el commit al borrador, ver C3).
4. **Hallazgo 4 — sector de interés** (variante de C4).
5. **Hallazgo 5 — UX/POLISH** (puede ir en un solo prompt, es bajo riesgo).
6. **Aparte y con aprobación**: `system_config.photo_limits.max_count = 2` (cambio de datos).

Indicá en la matriz qué prompts son independientes y pueden correr en paralelo (p. ej. 2 y 5) y
cuáles exigen serialización (nada que toque `map_screen.dart` puede correr junto con el 1).

---

## 9. Verificación: gates y qué NO se puede probar acá

- **Gate de código:** `flutter analyze` sin issues y `flutter test` en verde. **Re-medir el baseline**
  antes de proponer cifras (la referencia histórica no es evidencia actual).
- **Gate de contrato de datos:** las queries a PostgREST deben probarse con el `select` explícito
  (sin `select`, el SDK asume `select=*` y con columnas revocadas por privacidad responde 401).
- **Gate de base de datos:** probes de **solo lectura** contra `supabase_db_gota` (Postgres 54322).
- **No verificable hoy (declarar `NOT VERIFIED`, no inventar):** reproducción del cierre de foto en
  dispositivo Android real, memoria real (OOM nativo), cámara/galería del sistema, fluidez del mapa en
  hardware, experiencia visual final. No hay dispositivo conectado: solo Edge web.
- La verificación de cada fix la ejecuta el orquestador, **no el agente que implementó**: el plan debe
  decir qué evidencia esperar, no confiar en el auto-reporte del agente.

---

## 10. Formato de tu respuesta final al orquestador

```
VEREDICTO: READY FOR CODING AGENTS | BLOCKED — USER ACTION REQUIRED
DOCUMENTO: docs/PLAN_IMPLEMENTACION_<fecha>.md   (sin commit)
ÍNDICE:
  1. <hallazgo> — <clase> — <modelo sugerido> — <turnos> — <archivo núcleo>
  ...
ORDEN DE EJECUCIÓN Y PARALELISMO: <...>
APROBACIONES REQUERIDAS DEL USUARIO:
  - <acción exacta> (p. ej. migración de system_config, merge a main, deploy de Edge Function)
DISCREPANCIAS CON EL INFORME: <ninguna | lista con archivo:línea>
NO VERIFICABLE EN ESTE ENTORNO: <lista>
```

No agregues nada fuera de ese formato en la respuesta final (el detalle va en el documento).
