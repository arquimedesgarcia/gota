# Revalidación DEF-01 — Sprint 07

- **Fecha:** 2026-09-13 (UTC-4)
- **Commit evaluado:** `07557a4`
- **Instancia:** Supabase local Docker, `supabase_db_gota`
- **Modo:** QA independiente; sin cambios de producción ni migraciones nuevas

## Resultado

**DEF-01 REVALIDATION: FAIL**

La remediación de acceso directo a los helpers funciona, pero la decisión final queda **BLOCKED** por una regresión en la suite existente de creación de fugas.

## Evidencia

### Acceso directo a helpers

PASS. Como `authenticated`, con identidad propia y ajena:

- `public.check_rate_limit(uuid,text)` → `permission denied`
- `public.check_rate_limit_inline(uuid,text)` → `permission denied`

`information_schema.routine_privileges` confirmó que `authenticated`, `anon` y `public` no tienen `EXECUTE`; solo permanecen `postgres` y `service_role`.

### Aislamiento entre usuarios

PASS. Una RPC válida ejecutada por A consumió únicamente el bucket de A:

- A: `validate_leak` = 1
- B: `validate_leak` = 0

### Límites y atomicidad

PASS. Límites verificados: `3/20/10/5/20` por hora para las cinco operaciones.

PASS. Prueba concurrente de seis llamadas sobre el límite 3: tres permitidas, tres rechazadas y contador persistido en 6.

### Notification preferences

PASS. Caso 5e: el `UPDATE` directo a preferencias ajenas fue rechazado por privilegios y no produjo falso positivo.

### Regresión

PASS:

- `rls_test.sql`
- `validate_resolve_leak_test.sql`
- `water_events_test.sql`
- `notifications_test.sql`
- `community_concurrency_e2e.sh`

FAIL:

- `create_leak_report_test.sql`: bloque 11-2. El caso de descripción de más de 500 caracteres recibió el mensaje de foto duplicada antes de validar el límite de descripción.

## Decisión

**BLOCKED**. DEF-01 quedó corregido y verificado, pero no se cumplen todos los criterios de aprobación mientras permanezca fallando la regresión de `create_leak_report_test.sql`.

No se realizó commit ni push de código correctivo; este archivo documenta exclusivamente la revalidación y su resultado.
