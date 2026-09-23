# Auditoría Gota — Índice maestro

- **Fecha:** 2026-09-14 (UTC-4)
- **Commit auditado:** `1491952` (chore(sprint-08): stabilization — regression tests, release readiness, error UX, E2E hygiene, docs)
- **Modo:** SOLO LECTURA sobre el código + pruebas de abuso ejecutadas contra la BD. Sin mutaciones de producción.
- **Instancia:** Supabase self-hosted Docker (stack `gota`), `localhost:54322` (PostgreSQL 17).
- **Cobertura:** Sprint 08 (Stabilization). Sprints 01–06 conservan su veredicto de `5e34092`; Sprint 07 mantiene su veredicto de `631fa46`.

## Resumen por sprint

| Sprint | Tema | Veredicto | Informe |
|--------|------|-----------|---------|
| 01 | Foundation (PostGIS, auth anónimo, app_users, RLS, conexión) | ✅ VERIFICADO | [sprint01_foundation.md](2026-09-12_sprint01_foundation.md) |
| 02 | Leak reporting (reports, fotos, storage, RPC create_leak_report) | ✅ VERIFICADO | [sprint02_leak_reporting.md](2026-09-12_sprint02_leak_reporting.md) |
| 03 | Validation & resolution (atómico, historial, privacidad) | ✅ VERIFICADO | [sprint03_validation_resolution.md](2026-09-12_sprint03_validation_resolution.md) |
| 04 | Water events (registro/validación, historial, stats descriptivas) | ✅ VERIFICADO | [sprint04_water_events.md](2026-09-12_sprint04_water_events.md) |
| 05 | Map (get_map_reports, MapLibre/OSM, filtros) | ✅ VERIFICADO | [sprint05_map.md](2026-09-12_sprint05_map.md) |
| 06 | Notifications (webhook → notify-push → FCM v1) | ✅ VERIFICADO (prueba funcional OK) | [sprint06_webhook_5e34092.md](2026-09-12_sprint06_webhook_5e34092.md) |
| 07 | Security & Abuse Hardening (rate limits, RLS preferencias, helper SECURITY DEFINER) | 🔴 BLOCKED (DEF-01 crítico) | [2026-09-13_sprint07_security_abuse.md](2026-09-13_sprint07_security_abuse.md) |
| 08 | Stabilization (regresión, rate limiting, concurrencia, UX de errores, higiene E2E, release Android) | ✅ CERRADO (re-auditoría final 2026-09-14) | [2026-09-14_sprint08_final_closure.md](2026-09-14_sprint08_final_closure.md) |
| — | **Beta/Piloto E2E (RC readiness)** @ `679eb23` | ✅ READY CON 1 CONDICIÓN (H1: `notify-push` no desplegada en cloud piloto; UX en dispositivo NOT RUN) | [2026-09-19_beta-pilot-e2e.md](2026-09-19_beta-pilot-e2e.md) |
| — | **RC final / Preparación piloto controlado** @ `fix/map-r5-r6` (`295f77d`→`525725c`) | ❌ NOT READY (4 BETA FIX; 0 REGRESSION; device smoke PASS; sin artefacto de piloto con el Home objetivo) | [2026-09-22_final_rc_pilot_readiness.md](2026-09-22_final_rc_pilot_readiness.md) |

## Estado global

**Sprints 01–06 verificados en `5e34092`. Sprint 07 evaluado en `631fa46` → BLOCKED (DEF-01 remediado en `07557a4`). Sprint 08 evaluado en `1491952` → BLOCKED.**

- Sprint 07 agrega las migraciones `00020`–`00024` (rate limiting + hardening de grants).
- **DEF-01 (CRÍTICO):** `check_rate_limit(uuid,text)` y `check_rate_limit_inline(uuid,text)`
  son `SECURITY DEFINER` y están concedidas a `authenticated` con `p_user_id` externo,
  permitiendo a cualquier usuario autenticado agotar el presupuesto de rate-limit de
  otro (DoS) y leer sus contadores. Remediación: `revoke execute ... from authenticated`.
- El resto de controles de S07 (RLS de `notification_preferences`, usuario bloqueado,
  `audit_events` cerrada, concurrencia atómica, boundary de las 5 operaciones,
  aislamiento, Water Events, resolución) pasó de forma independiente.
- **Discrepancia de entorno:** la instancia viva estaba en migración `00019`; S07 no
  estaba desplegado. Requiere `supabase db push` (aplicar `00020`–`00024`) antes de liberar.
- **Sprint 08 (Stabilization)** — re-auditado el 2026-09-14 y **CERRADO**. Ver informe
  `2026-09-14_sprint08_final_closure.md`. Bloqueadores previos verificados como corregidos en
  la instancia viva: `water_events.created_by` denegado a cliente (401/42501), `system_config`
  con RLS on (401 anon), `public.temp` y funciones `test_*` ausentes. Rate limiting (8/8 SQL,
  5/5 E2E, límites 3/20/10/5/20), concurrencia (6 confirmaciones → 1 RESOLVED; 6 validaciones →
  6 filas) e idempotencia de notifications (`UNIQUE(user_id,water_event_id)` + sonda webhook
  +1 por INSERT) pasaron. Flutter `analyze` 0 issues / `test` 123/123. Migraciones 26/26.
- **S08 — hallazgos previos (todos CERRADOS):** AUD-S08-01 `water_events.created_by` (grants por
  columna, sin `created_by`); AUD-S08-02 `public.temp` (ausente en entorno auditado);
  AUD-S08-03 `test_*` (ausentes); AUD-S08-04 `system_config` RLS (on, 401 anon).
- **S08 — menores a backlog:** AUD-S08-05 (hints de objeto en 401/403), AUD-S08-06 (E2E no
  limpian usuarios anónimos), AUD-S08-07 (cleanup ante interrupción no probado), AUD-S08-08
  (build release no reproducible en ruta del repo; OK desde temp → entorno/ruta, no producto).
- **S08 — limitaciones de entorno (NO bloquean):** FCM real en dispositivo `NOT VERIFIED`
  (sin `google-services.json` / `FCM_SERVICE_ACCOUNT_JSON`); instalación/arranque/UX en
  device/AVD `NOT VERIFIED — no device/AVD available`. Verificación estática del APK OK
  (firma v2, no debuggable, sin secretos).
- **Cobertura no ejecutada (S08):** UX en ejecución (arranque, navegación, mapa, listado,
  detalle, reportar, validar, resolver, agua, notificaciones, loading/vacíos/error/retry/
  doble tap/rate limit/pérdida de red, sesión anónima) e instalación/arranque/FCM del APK
  release: no hay dispositivo ni emulador/AVD/system-image en el entorno y `adb devices`
  está vacío. El APK sí se construyó y se verificó estáticamente (firma v2, no debuggable,
  sin `service_role` ni JWT embebidos).

## Deuda / discrepancias documentadas

- **S07/DEF-02 (LOW):** `notifications_test.sql` bloque 5e desactualizado tras el
  `revoke insert, update` de `20260913000022`; el test debe envolver el UPDATE en
  `exception when insufficient_privilege`. El comportamiento de seguridad es correcto.
- (Ver deuda de Sprints 01–06 en la revisión de `5e34092`.)

## Discrepancias / deuda documentada (no defectos)

- **S02/AUD-S2-03:** geofence bbox de Nueva Esparta no implementado (decisión explícita, no inventar config). Rango validado en RPC.
- **S03/S04 (MVP):** rate limiting y ventana temporal de validación → Sprint 07 (Security & abuse, REQ-091).
- **S05:** estilo de tiles MapLibre por `--dart-define` (default demo); asignar tiles de producción en build.
- **S06 (producción):** falta inyectar `FCM_SERVICE_ACCOUNT_JSON` vía `supabase secrets set` para que el push llegue al dispositivo (no tocado en validación).
- **S06:** `config.toml` comenta "trigger vía supabase_functions.http_request" pero el mecanismo real en self-hosted es la fila en `supabase_functions.hooks`; aclarar en docs.

## Próximos sprints (no iniciados, fuera de alcance)

- Sprint 09 — Pilot (métricas, feedback).

## Sprints evaluados

- Sprint 07 — Security & abuse → BLOCKED en `631fa46`; DEF-01 remediado en `07557a4`.
- Sprint 08 — Stabilization → BLOCKED en `1491952`.

## Acción necesaria global

**Sprint 08 → BLOCKED.** Antes del cierre:

1. `water_events`: sustituir el grant de tabla por grants **por columna** como en `reports`
   (`created_by` no seleccionable); exponer autoría solo vía RPC con `is_creator`.
   (AUD-S08-01)
2. `DROP TABLE public.temp;` y `DROP FUNCTION public.test_func(), public.test_simple_update(),
   public.test_get_rate_limit();` + verificar que no existan en el Supabase desplegado.
   (AUD-S08-02/03)
3. Activar RLS en `system_config` (o retirar la policy muerta y el grant a `anon`).
   (AUD-S08-04)
4. Verificación en dispositivo/emulador del APK release con defines reales y
   `google-services.json` (UX completa §7, instalación/arranque/FCM §9).
5. Excluir `build` del antivirus en la ruta del repo o documentar el workaround, y ajustar la
   afirmación de `docs/SETUP.md` sobre el build release. (AUD-S08-08)
6. Que los E2E limpien sus usuarios anónimos/filas y probar el cleanup con interrupción
   efectiva. (AUD-S08-06/07)

Para la validación de Sprints 01–06 no hay acciones pendientes; su deuda de diseño/operativa
está documentada para el salto a producción.

## RC final / piloto controlado (2026-09-22) → NOT READY

Auditoría de solo lectura sobre `fix/map-r5-r6` (HEAD `525725c`) con **dispositivo físico**
(SM-A245M, Android 16) contra el Supabase **cloud piloto**. Ver
`2026-09-22_final_rc_pilot_readiness.md`.

- **0 BLOCKER verificados** (1 declarado por el equipo sin reproducir: crash al tomar/elegir foto),
  **4 BETA FIX**, **0 REGRESSION**, 5 POLISH, 3 INFO.
- Gates de código en verde: `flutter analyze` PASS, `flutter test` 189/189, SQL 9/9, E2E 6/6,
  seguridad (RLS/Storage/RPC-only/rate limiting) sin regresión, FCM recibido en el device.
- **Bloqueo para el piloto:** no existe aún artefacto de build con el Home objetivo
  (el APK release no lo incluye; el Home nuevo + migración `…29` no están en `main`).
- Pendientes operativos listados en el informe (rama/build release, desmontaje de MapLibre con
  resultado vacío, crash de fotos, guardas y localización del stepper de agua, avisos sin sector,
  prueba FCM con app cerrada, limpieza de datos de prueba).
