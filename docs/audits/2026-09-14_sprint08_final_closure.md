# Auditoría final de cierre — Sprint 08 (Release Gate)

- **Fecha:** 2026-09-14 (UTC-4)
- **Commit auditado:** `1491952` (+ correcciones aplicadas en la instancia viva desde entonces)
- **Modo:** SOLO LECTURA. Cero mutaciones de esquema/código. El único write de prueba
  ejecutado fue un `INSERT`/`DELETE` de una fila `notifications` con `title='AUDIT_PROBE_S08'`
  plenamente revertido (confirmado: 0 filas residuales). Ningún fix implementado.
- **Instancia:** Supabase self-hosted Docker (stack `gota`), `localhost:54322`
  (PostgreSQL 17). Migraciones **26/26 aplicadas** (`supabase_migrations.schema_migrations`).
- **Rol:** QA Lead + Security Auditor independiente. No se confió en informes previos:
  se re-leyó el estado vivo de la BD, el REST (PostgREST con clave anon real) y se
  ejecutaron las suites del repositorio de nuevo.

## Veredicto

# READY / CLOSED

## Bloqueadores anteriores — cerrrados

| ID | Hallazgo previo | Verificación independiente | Resultado |
|----|-----------------|----------------------------|-----------|
| AUD-S08-01 | `water_events.created_by` expuesto vía clave anon (grants de tabla) | `GET /rest/v1/water_events?select=*` → **401**; `?select=created_by` → **401**; `SET ROLE anon` + `SELECT created_by` → **42501**; grants por columna a `anon`/`authenticated` NO incluyen `created_by` (vistos en `information_schema.column_privileges`). Proyección pública `id,event_type,...` → **200, sin `created_by`**. | CERRADO (fix confirmado) |
| AUD-S08-02 | `public.temp` con DML abierto a `anon` (RLS off) | `pg_class` no contiene `public.temp`; `POST/PATCH/DELETE /rest/v1/temp` → 404/401. | CERRADO (ausente en entorno auditado) |
| AUD-S08-03 | `test_func`, `test_simple_update`, `test_get_rate_limit` ejecutables por `anon` | `pg_proc` no contiene ninguna de las tres en `public`. | CERRADO (ausentes) |
| AUD-S08-04 | `system_config` con RLS desactivada | `relrowsecurity=true`; grants de tabla solo a `postgres`/`service_role`; `GET /rest/v1/system_config` → **401**; 0 políticas (acceso denegado por defecto). `get_rate_limit()` (SECURITY DEFINER) sigue concedido a `authenticated` y lee internamente. | CERRADO (fix confirmado) |
| DEF-01 (S07) | helpers `check_rate_limit*` con EXECUTE a `authenticated` | `routine_privileges`: `check_rate_limit`/`check_rate_limit_inline` → solo `postgres`/`service_role`. Como `authenticated`: ambos → **42501**; `rate_limit_tracking` → **42501** (no reseteable). | CERRADO |

## Pruebas ejecutadas (real, con salida)

### §4 — Suites del repositorio
- **SQL (8/8 PASS)** vía `docker exec psql -v ON_ERROR_STOP=1`:
  `rls_test`, `create_leak_report_test`, `validate_resolve_leak_test`,
  `water_events_test`, `notifications_test`, `map_reports_test`,
  `storage_report_photos_test`, `rate_limiting_test`.
  - `create_leak_report_test` bloque 11: **OK 11 — descripción >500 rechazada con `VALIDATION_ERROR`** → la regresión que mantenía BLOCKED a DEF-01 quedó resuelta.
- **E2E (5/5 PASS)** ejecutados contra la instancia viva (HTTP/RLS reales):
  `rate_limit_concurrency_e2e`, `create_leak_report_e2e`, `community_flow_e2e`,
  `storage_rls_e2e`, `community_concurrency_e2e` → **64 PASS / 0 FAIL**.
  - Concurrencia real: 3 confirmaciones paralelas → exactamente 1 `RESOLVED`,
    `resolution_confirmation_count=3`, `contador==filas==3`, sin transición repetida.
  - Rate limit concurrente: 6 sesiones → 3 `CREATED` + 3 `RATE_LIMIT_EXCEEDED`, contador==6.
- **Flutter estático:** `flutter analyze` → `No issues found!` (0); `flutter test` →
  **+123: All tests passed!** (sin regresión vs. 123 previos).

### §2 — Rate limiting (re-verificado tras cambios S08)
- Límites exactos (de `system_config.rate_limits` en vivo): `create_leak_report=3`,
  `validate_leak=20`, `confirm_leak_resolution=10`, `register_water_event=5`,
  `validate_water_event=20`.
- Siguiente operación rechazada (`limit` ok → `limit+1` = `RATE_LIMIT_EXCEEDED`).
- Aislamiento entre usuarios (bucket de B no se toca).
- Sin efectos de negocio en el rechazo (contador registra el intento; filas de negocio no).
- Reset de ventana verificado.
- **Imposibilidad de invocar helpers protegidos**: `check_rate_limit`/`check_rate_limit_inline`
  → 42501 para `authenticated`/`anon`. `get_rate_limit` legible y **no** consume presupuesto.
- `rate_limit_tracking` inaccesible por cliente (401 REST / 42501 SQL).

### §3 — Concurrencia
- Resolution: 6 confirmaciones concurrentes → 1 `RESOLVED`, contador=3, `resolved_at` íntegro,
  sin superar threshold. Idempotencia posterior → `REPORT_ALREADY_RESOLVED`.
- Validation: 6 validaciones concurrentes → 6 filas, `validation_count=6`, sin duplicación.

### §1 — Seguridad
- `water_events.created_by`: no accesible por REST anon/authenticated ni por `SELECT` directo;
  columnas públicas operativas.
- `system_config`: RLS on, sin lectura de cliente, sin escritura indebida.
- Objetos residuales `public.temp`, `test_func`, `test_simple_update`, `test_get_rate_limit`:
  **todos ABSENTES** → PASS (sin residuos del entorno en la BD auditada).

### §5 — Notificaciones / Webhook
- **Idempotencia (§5A):** `notifications` tiene `UNIQUE (user_id, water_event_id)`
  (`notifications_unique_user_event`); 0 duplicados presentes → una notification por
  `user_id + water_event_id`.
- **Webhook (§5B):** un único trigger `notifications_webhook_notify_push` (`AFTER INSERT`)
  sobre `public.notifications` → `supabase_functions.http_request(.../notify-push...)`.
  Sonda empírica: 1 `INSERT` en `notifications` → **+1 fila en `supabase_functions.hooks`**
  (delta exacto 1, de 42→43; fila de prueba eliminada, 0 residuales).
- **Sobre los "42 registros":** son el **ledger de ejecución** de `supabase_functions.http_request`,
  que hace `INSERT INTO supabase_functions.hooks (...)` en **cada** disparo del trigger
  (un `INSERT` por ejecución de webhook). 42 filas = 42 ejecuciones históricas de webhook,
  **no** 42 triggers duplicados ni 42 envíos simultáneos. Confirmado por definición de función
  y por la sonda (+1 por INSERT). Es **INFO**, no defecto, y **no requiere cambio de código**
  (concordante con la investigación previa; aquí verificada mecánicamente en vez de asumida).
- **Edge Function (§5C):** `notify-push` desplegada y consistente con la arquitectura
  (trigger → `http_request` → `net.http_post` a `/functions/v1/notify-push`).
- **FCM (§5D):** `NOT VERIFIED`. No existe dispositivo/FCM operativo en el entorno
  (sin `google-services.json`, `FCM_SERVICE_ACCOUNT_JSON` no inyectado). Limitación de
  entorno, **no** convertida en PASS.

### §6 — Android Release
- No reproducible en esta máquina desde `D:\Proyectos\Gota\v0.2` (error de incremental cache
  Kotlin, AUD-S08-08). El **mismo árbol** compiló OK desde copia en `%LOCALAPPDATA%\Temp`
  (`app-release.apk` 85 MB) → problema de **entorno/ruta**, no de producto.
- En ese artefacto (verificación estática previa de S08, reconfirmada aquí en docs):
  firma v2, **no debuggable**, minSdk 24 / targetSdk 36, sin `service_role`/JWT embebidos,
  sin cleartext, permisos coherentes.
- **Instalación/arranque/navegación/FCM en dispositivo: `NOT VERIFIED` — no device/AVD available**
  (`adb`/`emulator`/`avd` ausentes, `adb devices` vacío).

### §7 — UX / Errores
- Verificado por suites Flutter (123/123) + mapeo de códigos en
  `lib/features/leaks/domain/leak_errors.dart` y `lib/features/water/domain/water_errors.dart`
  (mensajes en español, sin SQLSTATE/stack trace/nombres internos en la capa de presentación).
- **UX en ejecución en dispositivo: NO EJECUTADA** (misma limitación de §6).

### §8 — E2E Hygiene
- Los E2E funcionan con limpieza de `auth.users` y `audit_events` (añadido en corrección).
- Usuarios anónimos históricos (iteraciones E2E) → clasificados como **TEST RESIDUE**,
  no datos funcionales activos. 0 `app_users` huérfanos.
- No se introdujeron cambios de producción; la app no usa `service_role`.
- (AUD-S08-06/07 menores: los E2E no limpian todos sus usuarios anónimos y el cleanup
  ante interrupción no quedó probado de forma efectiva → backlog, no bloquea.)

### §9 — Documentación
- `README.md` (raíz), `MVP_PLAN.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `API_SPEC.md`,
  `REVIEW_CHECKLIST.md`, `SETUP.md` revisados.
- `DATA_MODEL.md`/`API_SPEC.md` afirman correctamente que `water_events` **NO expone
  `created_by`** — concordante con el estado vivo verificado.
- `SETUP.md` ya no afirma "reproducible desde cualquier clon" (línea 86: "compila y produce
  un APK válido desde un clon limpio sin secretos"). Consistente.
- Sin inconsistencias reales que bloqueen.

## Clasificación de hallazgos

| Severidad | Hallazgo | Acción |
|-----------|----------|--------|
| INFO | 42 filas en `supabase_functions.hooks` = ledger de ejecución del webhook (1 por disparo), no duplicados ni envíos múltiples. Verificado empíricamente. | Ninguna (no requiere fix) |
| MINOR | AUD-S08-05: PostgREST filtra nombres de objetos en hints de 401/403 (`GRANT SELECT ON public.X TO ...`). Comportamiento por defecto; sin datos privados. | Backlog (no bloquea) |
| MINOR | AUD-S08-06: E2E no limpian todos sus usuarios anónimos/filas de tracking. | Backlog |
| MINOR | AUD-S08-07: cleanup ante interrupción no probado de forma efectiva. | Backlog |
| MINOR | AUD-S08-08: build release no reproducible en ruta del repo (entorno/ruta); OK desde temp. | Backlog / documentar |

## Limitaciones de entorno (no impiden declarar Sprint 08 CERRADO)

1. **FCM real en dispositivo:** `NOT VERIFIED` — sin `google-services.json` / `FCM_SERVICE_ACCOUNT_JSON`.
2. **APK en dispositivo/AVD:** `NOT VERIFIED` — no hay device/AVD/adb en el entorno.
3. **UX en ejecución:** no ejecutada (depende de 1/2).
4. **Build release desde la ruta del repo:** falla por incremental cache (entorno), no por defecto de producto.

Estas son limitaciones del **entorno de auditoría**, no defectos del producto: la lógica de
negocio, RLS, rate limiting, concurrencia, idempotencia, el webhook y la verificación estática
del APK (firma, debuggable, sin secretos) pasaron con evidencia leída de la BD/HTTP. El build
es reproducible desde una copia del árbol (mismo código), descartando un defecto de producto.

## Acción necesaria

**Ninguna para el cierre de Sprint 08.** Los menores (AUD-S08-05/06/07/08) pasan a backlog.
Previo a producción: inyectar `google-services.json` + `FCM_SERVICE_ACCOUNT_JSON` en el
despliegue y ejecutar la verificación en dispositivo (cubre §5D, §6, §7 en ejecución).
