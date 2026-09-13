# Auditoría Gota — Índice maestro

- **Fecha:** 2026-09-13 (UTC-4)
- **Commit auditado:** `631fa46` (feat: implement Sprint 07 — Security & Abuse Hardening)
- **Modo:** SOLO LECTURA sobre el código + pruebas de abuso ejecutadas contra la BD. Sin mutaciones de producción.
- **Instancia:** Supabase self-hosted Docker (stack `gota`), `localhost:54322` (PostgreSQL 17).
- **Cobertura:** Sprint 07 (Security & Abuse Hardening). Sprints 01–06 conservan su veredicto de `5e34092`.

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

## Estado global

**Sprints 01–06 verificados en `5e34092`. Sprint 07 evaluado en `631fa46` → BLOCKED.**

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

- Sprint 07 — Security & abuse (RLS revisión, rate limits, pruebas de abuso).
- Sprint 08 — Stabilization (tests, UX, rendimiento, Android release).
- Sprint 09 — Pilot (métricas, feedback).

## Acción necesaria global

**NINGUNA** para la validación actual. Los pendientes son de diseño/operativos y fueron documentados para los sprints correspondientes o para el salto a producción.
