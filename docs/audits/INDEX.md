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
| 08 | Stabilization (regresión, rate limiting, concurrencia, UX de errores, higiene E2E, release Android) | 🔴 BLOCKED (2 IMPORTANTES + UX/APK no ejecutados) | [2026-09-14_sprint08_stabilization.md](2026-09-14_sprint08_stabilization.md) |

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
- **Sprint 08 (Stabilization)** — el núcleo pasa: rate limiting de las 5 operaciones
  (límite exacto, siguiente llamada, aislamiento por usuario, sin bypass ni llamada directa
  a los helpers, rechazo sin efectos de negocio, ventana/reset), concurrencia real
  (8 simultáneas contra límite 3; 6 confirmaciones y 6 validaciones concurrentes con
  `resolved_at` íntegro y sin doble resolución), RLS/privilegios y contratos de error.
  Suites SQL 8/8, E2E 64 PASS/0 FAIL, `flutter analyze` 0 issues, `flutter test` 123/123,
  migraciones 26/26 aplicadas.
- **AUD-S08-01 (IMPORTANTE):** `water_events` tiene grant de tabla a `anon`/`authenticated`,
  así que la clave anon pública lee `created_by` (identidad pseudónima del autor). `reports`
  sí está protegido con grants por columna.
- **AUD-S08-02 (IMPORTANTE):** `public.temp` existe en la instancia local con DML abierto a
  `anon` y RLS desactivada; no está en las migraciones del repo (residuo del volumen Docker).
  Si existiera en el Supabase desplegado, sería BLOQUEANTE.
- **AUD-S08-03/04/05/06/07/08 (MENORES):** funciones `test_*` ejecutables por `anon`;
  `system_config` con RLS desactivada; los 401/403 de PostgREST filtran nombres de objetos;
  los E2E no limpian sus usuarios anónimos ni filas de tracking/auditoría; el cleanup ante
  interrupción no quedó probado; y `flutter build apk` no es reproducible en
  `D:\Proyectos\Gota\v0.2` (mismo árbol compila OK desde una copia en temp).
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
