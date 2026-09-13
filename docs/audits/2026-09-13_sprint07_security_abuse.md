# Auditoría Sprint 07 — Security & Abuse Hardening

- **Fecha:** 2026-09-13 (UTC-4)
- **Commit auditado:** `631fa46` (feat: implement Sprint 07 — Security & Abuse Hardening)
- **Modo:** SOLO LECTURA sobre el código + pruebas de abuso ejecutadas contra la BD. Sin mutaciones de producción.
- **Instancia evaluada:** Supabase self-hosted Docker, `localhost:54322` (PostgreSQL 17).
- **Veredicto:** 🔴 **BLOCKED** (1 defecto crítico, 1 deuda de test baja).

## Resumen ejecutivo

Un agente de QA independiente evaluó la implementación de Sprint 07 intentando
romper las garantías de seguridad y negocio (no solo el happy path). Se construyó
un harness que simula fielmente a un cliente autenticado:

```sql
SET ROLE authenticated;
SET request.jwt.claim.sub = '<auth.users.id>';
```

Esto es **exactamente** como `auth.uid()` resuelve el usuario dentro de las RPC
`SECURITY DEFINER`. Toda afirmación se lee de vuelta desde PostgreSQL
(contadores `rate_limit_tracking`, conteo de filas, estados de `reports`).

**Resultado:** 34 casos independientes ejecutados; 31 PASS, 3 FAIL (de los cuales
1 es un defecto crítico real y 2 falsos positivos descartados tras verificación
aislada). La suite de regresión existente (`rls_test`, `validate_resolve_leak_test`,
`water_events_test`) pasa; `notifications_test` falla solo por un test desactualizado.

## Cobertura de pruebas

### Rate Limiting (boundary + aislamiento + concurrencia)
- Las 5 operaciones limitadas (`create_leak_report`=3, `validate_leak`=20,
  `confirm_leak_resolution`=10, `register_water_event`=5, `validate_water_event`=20)
  respetan el límite exacto: `N` permitidos, `N+1` → `RATE_LIMIT_EXCEEDED`. ✅
- Ventana fija de 1 hora (`date_trunc('hour', now())`); no hay contadores
  permanentes ni reinicio artificial por request. ✅
- Aislamiento entre operaciones: agotar `create_leak_report` no bloquea
  `validate_leak` ni las otras. ✅
- Aislamiento entre usuarios: el usuario A agotando su presupuesto NO afecta al
  presupuesto del usuario B (cuando se usa la RPC correcta). ✅
- **Concurrencia:** race con contador=19 y 3 requests simultáneos → máximo 1
  adicional aceptado (`VALIDATED / RATE_LIMIT_EXCEEDED / RATE_LIMIT_EXCEEDED`,
  counter=22). El upsert atómico bajo UNIQUE evita la condición de carrera. ✅

### Notification Preferences (seguridad)
- INSERT/UPDATE directo desde el cliente → **DENIED** (`revoke insert, update`
  en migración `20260913000022`). ✅
- Aislamiento A↔B: A ve 0 filas de las preferencias de B (RLS correcta). ✅
- RPC `save_notification_preferences` valida sector inexistente/inactivo
  (`NOT_FOUND`), conserva el sector en OFF, acepta `sector NULL`. ✅

### Usuario bloqueado
- RPC `save_notification_preferences` y `create_leak_report` → `FORBIDDEN`. ✅
- Escritura directa a `notification_preferences` → DENIED (sin privilegio). ✅

### Audit Events
- INSERT/UPDATE/DELETE por `authenticated` → DENIED. El cliente no puede
  falsificar/modificar/borrar auditoría. ✅

### Water Events (regresión)
- `anon` no puede `register_water_event` → DENIED. ✅
- `event_time` en el futuro, tipo inválido, sector inválido → rechazados. ✅
- Auto-validación (`created_by` = validador) → `FORBIDDEN`; cross-user → `VALIDATED`. ✅
- Idempotencia de notificación: 1 notification por evento (UNIQUE user_id+event). ✅

### Resolución de fugas (regresión)
- 1 usuario → no resuelto; 2 usuarios → no resuelto; 3er usuario → `RESOLVED`. ✅
- Mismo usuario confirmando 2 veces → `DUPLICATE_ACTION` (sin doble conteo). ✅
- **Nota informativa (prexistente, NO de S07):** `confirm_leak_resolution` nunca
  excluyó al creador; un creador puede confirmar su propia resolución. Es diseño
  documentado en la migración `20260911000013` §2 ("cualquier usuario"), no una
  regresión introducida por Sprint 07.

## Defectos

### DEF-01 — CRÍTICO
- **Severity:** CRITICAL
- **Area:** Rate Limiting / SECURITY DEFINER / abuso de parámetros
- **Test:** Abuso de parámetro en helpers de rate-limit concedidos a `authenticated`
- **Expected:** las funciones internas de rate-limit NO son alcanzables directamente
  por un cliente con un `user_id` ajeno; cada usuario solo consume su propio
  presupuesto.
- **Observed:** Usuario A (authenticated) llama
  `check_rate_limit_inline(<app_user_id_B>, 'create_leak_report')` 6 veces → el
  contador de **B** sube a 6 mientras A queda en 0. Lo mismo con `check_rate_limit`
  (contador de B=11). A además recibe en claro `count`/`limit`/`reset_at` de B
  (info-leak de la actividad de un tercero).
- **Reproduction:**
  1. Crear `auth.users` A y B; obtener sus `app_users.id`.
  2. Conectar como `authenticated` con `sub=A`.
  3. `SELECT public.check_rate_limit_inline(<id_B>, 'create_leak_report');` repetido.
  4. Como dueño: `SELECT count FROM rate_limit_tracking WHERE user_id=<B>;` → 6.
- **Evidence:** `information_schema.routine_privileges` muestra
  `authenticated:EXECUTE` para ambas funciones. Migración `20260913000021`
  (líns. 161-162) y `20260913000024` (líns. 69-70) hacen
  `grant execute on function ... to authenticated`. Ambas son `SECURITY DEFINER`,
  así que se ejecutan como dueño (postgres) e insertan la fila con el `p_user_id`
  que le pasan, **sin verificar que sea el llamante**.
- **Impacto:** cualquier usuario autenticado puede **agotar el presupuesto de
  rate-limit de otra persona** (DoS de las 5 operaciones críticas) y **leer los
  contadores ajenos**. Cumple el criterio de BLOCK `SECURITY DEFINER permite
  escalada de privilegios / abuso de parámetros`.
- **Remediación mínima:**
  ```sql
  revoke execute on function public.check_rate_limit(uuid, text) from authenticated;
  revoke execute on function public.check_rate_limit_inline(uuid, text) from authenticated;
  -- Las RPC las invocan internamente como SECURITY DEFINER; basta con
  -- postgres/service_role. No se necesita concederlas al cliente.
  ```

### DEF-02 — LOW (deuda de test, no funcional)
- **Severity:** LOW
- **Area:** Regresión de suite / `notification_preferences`
- **Test:** `notifications_test.sql` bloque 5e (A intenta `UPDATE` directo a las
  preferencias de C)
- **Expected (test original):** el UPDATE del cliente se filtra por RLS a 0 filas y
  el test continúa.
- **Observed:** `permission denied for table notification_preferences` (42501).
  Motivo: Sprint 07 (migración `20260913000022`) revocó `INSERT,UPDATE` a
  `authenticated`; el test 5e no envuelve el UPDATE en
  `exception when insufficient_privilege`. El **comportamiento de seguridad es
  correcto (y más estricto)**: el cliente no puede tocar la tabla. Solo el test
  está desactualizado.
- **Remediación:** envolver el `UPDATE` del bloque 5e en
  `exception when insufficient_privilege` (como ya hacen los bloques 4e/5a/5b/5d).

## Falsos positivos descartados (transparencia)

1. **"A ve la fila de B en SELECT de `notification_preferences`":** primer reporte
   del harness marcó SELECT_B como permitido. Una prueba aislada mínima demostró
   que RLS aísla correctamente (A ve 0 filas de B); era un artefacto del harness,
   no un defecto.
2. **"creator confirm own → FORBIDDEN" en resolución:** es diseño preexistente
   (migración `20260911000013` §2), no una regresión de S07. Reclasificado como
   nota informativa.

## Discrepancia de entorno (debe corregirse antes del deploy)

El estado vivo de `localhost:54322` tenía migraciones solo hasta `00019`; Sprint 07
(`00020`–`00024`) **no estaba desplegado** (se detectó un apply parcial con un
`check_rate_limit_inline` huérfano y `create_leak_report`/`check_rate_limit`
ausentes). Para esta auditoría se aplicaron las migraciones canónicas del repositorio
para evaluar el código real. **Acción requerida:** `supabase db push` (o aplicar
`00020`–`00024`) en la instancia objetivo antes de liberar S07.

## Veredicto

🔴 **BLOCKED.** DEF-01 expone funciones `SECURITY DEFINER` con `p_user_id` externo a
`authenticated`, permitiendo consumo del presupuesto de rate-limit ajeno (DoS) e
info-leak — criterio de BLOCK directo. Una vez aplicado el `revoke execute`, S07
queda en condiciones de READY (el resto de controles — RLS, usuario bloqueado,
auditoría, concurrencia atómica, boundary de las 5 operaciones, aislamiento, Water
Events, resolución — pasó).
