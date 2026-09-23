# GOTA — Prompt de traspaso (sesión nueva y limpia)

> Pegar este bloque completo como primer mensaje de la sesión nueva. Sustituye a cualquier contexto previo:
> todo lo necesario está enlazado abajo. Léelo primero, luego propón plan y modelo (gate del usuario) antes de ejecutar.

---

## 0. Rol y regla de arranque

Eres el agente que **continúa** dos sesiones que ya cerraron su ciclo (`20260922_165743_831c3a` = auditoría RC final; `20260922_182616_bceedf` = diagnóstico + plan de implementación). No repitas su trabajo: su salida está en el repositorio.

**Antes de ejecutar cualquier cosa, propón con `clarify`:** (a) el plan de ejecución, (b) quién ejecuta y **qué modelo** (gate del usuario: quirúrgico → Haiku, diagnóstico/refactor → Sonnet, arquitectura/complejo → Opus; 'Hermes directo sin CLI agent' cuando no haga falta razonamiento) y (c) si hay push/merge/deploy, pedir aprobación explícita. Reinspecciona `git log`/`git status` para confirmar la base antes de proponer.

## 1. Proyecto y entorno

- **Gota**: app Flutter (Android) + Supabase para reportar fugas de agua y eventos de agua. Piloto controlado inminente (Isla de Margarita).
- **Repo local:** `D:\Proyectos\Gota\v0.2` (bash MSYS; psql no está en PATH → usar `docker exec -i supabase_db_gota psql -U postgres -d postgres`).
- **Rama de trabajo:** `fix/map-r5-r6` (adelante de `main`). Ojo: existe un worktree `worktree-agent-a429749783d7a8538` de sesiones previas.
- **Stack local:** Docker Supabase self-hosted (`supabase_db_gota` :54322, `supabase_kong_gota` :54321, `supabase_edge_runtime_gota`). El edge-runtime local **no emite logs** (caído/mudo): las edge functions se validan en cloud.
- **Cloud piloto:** proyecto Supabase `eghphmugrrbvbvodhasq` (`SUPABASE_ENV=pilot`), credenciales en `.local-supabase-pilot.env` (**nunca imprimir claves**).
- **Dispositivo físico de QA:** Samsung SM-A245M, Android 16, serial `R58W709201M`, 1080x2340 @450 dpi, paquete `com.gota.app`. `adb` en `C:\Users\arqui\AppData\Local\Android\Sdk\platform-tools\adb.exe`.
- **Docs fuente de verdad:** `docs/FUNCTIONAL_SPEC.md`, `docs/UX_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/API_SPEC.md`, `docs/REVIEW_CHECKLIST.md`; auditorías en `docs/audits/` + `INDEX.md`.

## 2. Estado exacto al cierre (léelo, no lo re-derives)

**Auditoría RC final — veredicto `NOT READY`** (informe: `docs/audits/2026-09-22_final_rc_pilot_readiness.md`):

- BLOCKER 0 verificados (1 declarado por el diagnóstico y **no reproducido**: cierre al tomar/elegir foto), **BETA FIX 4**, **REGRESSION 0**, 5 POLISH, 3 INFO.
- Gates de código en verde sobre la rama: `flutter analyze` limpio · `flutter test` **189/189** · SQL suites **9/9** · E2E **6/6** · seguridad (RLS/Storage privado/RPC-only/rate limit) sin regresión · FCM recibido en el device.
- Device smoke PASS en: Home (banner, Resumen de hoy, 3 acciones, Actividad reciente), reporte de fuga real persistido, GPS como fuente geométrica, agua (Llegó/Se fue + historial + Home), mapa (basemap Liberty, zoom/pan, leyenda, markers), ciclo de comunidad sin resolución prematura, FCM (bandeja + recepción en logcat).
- **Lo que bloquea el piloto:** no existe artefacto de build con el Home objetivo — el `app-release.apk` (20-sep) **no** contiene el Home nuevo (verificado en `libapp.so`) y `main` sirve el Home anterior; el Home nuevo + migración `20260922000029` viven solo en `fix/map-r5-r6`.
- **BETA FIX abiertos:** (1) el mapa **desmonta** MapLibre si un refetch devuelve lista vacía (`map_screen.dart:87-98` → `_MapEmptyView`; reproducido en device 506 438 → 3 146 px); (2) APK release obsoleto; (3) Home de piloto no mergeado a `main`; (4) refetch de viewport sin debounce (declarado, no medido).
- **Pendiente de verificación en device:** FCM con la app **cerrada** (notificación de sistema, no solo bandeja), cierre de foto con cámara/galería, filtro con resultado vacío sin desmonte, "Continuar" habilitado con preselección.
- Residuo declarado: datos de prueba escritos en el piloto con autorización del usuario (1 reporte, 2 eventos de agua, 2 notificaciones, 1 `notification_preferences`) + 3 anónimos del Docker local (suites E2E). **No eliminar sin service-role y aprobación.**

**Diagnóstico pre-implementación + plan** (documentos del repositorio):

- `docs/DIAGNOSTICO_PRE_IMPLEMENTACION_2026-09-22.md` — diagnóstico de los 5 hallazgos (mapa, fotos, Continuar deshabilitado, sector de interés, ajustes UX), con causa raíz, corrección mínima y clasificación.
- `docs/PLAN_IMPLEMENTACION_2026-09-22.md` — **plan canónico** (952 líneas): 5 prompts autocontenidos (1 fotos, 2 mapa, 3 Continuar, 4 sector de interés, 5 UX), contrato y archivos permitidos/prohibidos por prompt, criterios de aceptación, tests con control de mutación, rollback, matriz de conflictos y aprobaciones **A1–A6** pendientes.
- `docs/PROMPT_EQUIPO_ARQUITECTURA_2026-09-22.md` — contexto para equipo de arquitectura.
- `docs/audits/pre-implementation.md` — borrador v1 **superado** por el plan canónico; no usarlo como fuente.

**Estrategia de tandas del plan:** tanda 1 = prompts **2 (mapa) ∥ 1 (fotos) ∥ 4 (sector de interés)** en worktrees separados; después **3 (Continuar)**; después **5 (UX)**. El prompt 5 toca `leak_report_controller.dart` (compartido con 1 y 3) y el 3 depende de 1: respetar el orden.

**Aprobaciones A1–A6 pendientes** (detalle y comandos exactos en el plan):

- **A1** `system_config.photo_limits.max_count 3 → 2` en **local** (la autoridad del límite es `create_leak_report`).
- **A2** lo mismo en el **cloud piloto**, **solo** con `npx supabase db query --linked -f <archivo.sql>` — **prohibido `npx supabase db push`** (el remoto no tiene historial de migraciones).
- **A3** `fix/map-r5-r6 → main` + rebuild del **APK release** con los `--dart-define` de piloto (desbloquea el gate de build).
- **A4** reconectar el dispositivo físico (habilita reproducir/descartar el cierre de foto y medir `onCameraIdle`).
- **A5** medir la cadencia real de `onCameraIdle` en device antes de decidir cualquier debounce (no inventar el intervalo).
- **A6** limpieza de datos de prueba (requiere service-role; no bloquea los prompts).

## 3. Secuencia única acordada (no hay otra)

| Fase | Qué | Quién |
|---|---|---|
| F0 | Documentos asegurados: informe RC + `INDEX.md` + diagnóstico + plan ya commiteados y pusheados en `fix/map-r5-r6`. Árbol limpio. | hecho |
| F1 | Implementar tanda 1 (**prompt 2 ∥ 1 ∥ 4**), luego **3**, luego **5**, con los prompts del plan canónico. | agente de codificación (modelo por prompt) |
| F2 | A1 (local) y A2 (cloud piloto) del límite de fotos. | agente, con aprobación |
| F3 | A3: merge a `main` + push. | aprobación explícita del usuario |
| F4 | Build **release** desde la rama (dart-define de piloto + `google-services.json`) e instalación en el device. | agente |
| F5 | Smoke en device de los 4 puntos abiertos: (a) foto cámara/galería → ¿reproduce el cierre?, (b) filtro con resultado vacío → el mapa **no** se desmonta, (c) FCM con la app **cerrada** (notificación de sistema), (d) "Continuar" habilitado con preselección. | verificación independiente |
| F6 | Re-auditoría: `flutter analyze` / `flutter test` / SQL / E2E + veredicto final + `INDEX.md`. | verificación independiente |

**No distribuir ningún APK antes de F6.**

## 4. Reglas duras

1. **Nunca imprimir secretos** (anon key, JWT, service-role, tokens, connection strings, FCM): redactar `[REDACTED]`; enmascarar cualquier `.env` (`sed 's/=.*/=<hidden>/'`).
2. **No cambiar** backend/RPC/contrato de datos/RLS/migraciones salvo evidencia directa de que es imprescindible; si aplica, justificar con `archivo:línea`.
3. **No crear infraestructura de tests nueva** ni borrar/marcar `skip` tests existentes.
4. **Un informe por cambio**, con evidencia real (`archivo:línea`, salida de comandos). "No probado" **nunca** es PASS; lo no verificable en este entorno se marca `NOT VERIFIED`.
5. **No commitear ni pushear** nada que no se haya acordado; los docs van en commits `docs-only` separados de los cambios de código.
6. Clasificar todo hallazgo como `BLOCKER` / `BETA FIX` / `POLISH` / `REGRESSION` / `PASS`.
7. **Gate de piloto:** `READY FOR CONTROLLED PILOT` solo si BLOCKER = 0, BETA FIX = 0, REGRESSION = 0, E2E crítico PASS, smoke en device PASS, `flutter analyze` PASS, `flutter test` PASS, FCM real en device PASS, GPS/reporte PASS y mapa PASS.

## 5. Primeras acciones que espero de ti (en este orden)

1. Leer (solo lectura) `git log --oneline -6`, `git status -sb`, y los 3 documentos del repositorio citados en §2.
2. Confirmar en el plan canónico el contrato del **prompt 2 (mapa)** — es el de mayor respaldo empírico (desmonte reproducido en device) — y proponer con `clarify`: modelo, executor, y si arranca tanda 1 completa o solo el prompt 2.
3. Verificar disponibilidad del device (`adb devices -l`); si está conectado, avisar que habilita A4/A5.
4. Elegir el orden de los pasos de código según §3 y **no** lanzar código sin aprobación.

**Formato de tu primera respuesta:** `STATUS` · `BASE (SHA)` · `DOCS LEÍDOS` · `PLAN PROPUESTO (fases + executor + modelo)` · `APROBACIONES PENDIENTES (A1–A6)` · `BLOQUEOS` · `PREGUNTA (clarify con opciones, la recomendada primero)`.