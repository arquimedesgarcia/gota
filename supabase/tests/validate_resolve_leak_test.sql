-- tests/validate_resolve_leak_test.sql — Pruebas de Sprint 03:
-- validación comunitaria y resolución (RPC `validate_leak`,
-- `confirm_leak_resolution`, `get_leak_report_detail`) y de las tablas
-- `report_validations` / `resolution_confirmations` (constraints, RLS y
-- protección de los campos críticos de `reports`).
--
-- Ejecutar contra una BD Supabase con las migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/tests/validate_resolve_leak_test.sql
--   (con Supabase local: docker exec -i supabase_db_gota psql -U postgres \
--     -d postgres -v ON_ERROR_STOP=1 < supabase/tests/validate_resolve_leak_test.sql)
--
-- Todo corre en una transacción que se revierte al terminar: el script no
-- deja datos en la base.
--
-- Concurrencia real: no puede simularse dentro de una única sesión SQL. La
-- prueba de concurrencia con dos/más sesiones paralelas vive en
-- `supabase/tests/community_concurrency_e2e.sh`. Este archivo demuestra la
-- parte estática de la invariante: UNIQUE (report_id, user_id) + fila
-- bloqueada (`for update`) + una sola transacción por operación.

begin;
set role postgres;
reset request.jwt.claims;

-- =====================================================================
-- Preparación
-- =====================================================================
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'creator@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'valb@gota.test'),
  ('33333333-3333-4333-8333-333333333333', 'valc@gota.test'),
  ('44444444-4444-4444-8444-444444444444', 'vald@gota.test'),
  ('55555555-5555-4555-8555-555555555555', 'blocked@gota.test'),
  ('66666666-6666-4666-8666-666666666666', 'vale@gota.test')
on conflict (id) do nothing;

update public.app_users set is_blocked = true
 where auth_user_id = '55555555-5555-4555-8555-555555555555';

insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Sprint 03', 'Nueva Esparta', true)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', 'Sector Sprint 03', true)
on conflict (id) do nothing;

-- Reportes de trabajo (se insertan como administrador de BD; la creación
-- por cliente ya está cubierta por create_leak_report_test.sql).
do $$
declare
  v_creator uuid;
begin
  select id into v_creator from public.app_users
   where auth_user_id = '11111111-1111-4111-8111-111111111111';

  -- R1: ACTIVE del creador A (validaciones).
  insert into public.reports (id, created_by, municipality_id, sector_id,
                              location, location_source, description)
  values ('00000000-0000-4000-8000-0000000000a1', v_creator,
          '00000000-0000-4000-8000-0000000000f1',
          '00000000-0000-4000-8000-0000000000e1',
          extensions.st_setsrid(extensions.st_makepoint(-63.87, 10.99), 4326)::extensions.geography,
          'GPS', 'Fuga de pruebas de validación');

  -- R2: ACTIVE del creador A (resolución con 3 identidades).
  insert into public.reports (id, created_by, municipality_id, sector_id,
                              location, location_source)
  values ('00000000-0000-4000-8000-0000000000a2', v_creator,
          '00000000-0000-4000-8000-0000000000f1',
          '00000000-0000-4000-8000-0000000000e1',
          extensions.st_setsrid(extensions.st_makepoint(-63.88, 10.98), 4326)::extensions.geography,
          'MANUAL');

  -- R3: ya RESOLVED (estados incompatibles).
  insert into public.reports (id, created_by, municipality_id, sector_id,
                              location, location_source, status, resolved_at)
  values ('00000000-0000-4000-8000-0000000000a3', v_creator,
          '00000000-0000-4000-8000-0000000000f1',
          '00000000-0000-4000-8000-0000000000e1',
          extensions.st_setsrid(extensions.st_makepoint(-63.89, 10.97), 4326)::extensions.geography,
          'GPS', 'RESOLVED', now());

  -- R4: ACTIVE del creador B (para probar que el creador sí puede
  -- confirmar resolución, decisión documentada en MIGRATION_NOTES).
  insert into public.reports (id, created_by, municipality_id, sector_id,
                              location, location_source)
  select '00000000-0000-4000-8000-0000000000a4', u.id,
         '00000000-0000-4000-8000-0000000000f1',
         '00000000-0000-4000-8000-0000000000e1',
         extensions.st_setsrid(extensions.st_makepoint(-63.90, 10.96), 4326)::extensions.geography,
         'GPS'
    from public.app_users u
   where u.auth_user_id = '22222222-2222-4222-8222-222222222222';

  raise notice 'OK 0: datos de prueba listos';
end $$;

-- =====================================================================
-- 1. Tablas y constraints (la autoridad real contra duplicados)
-- =====================================================================
do $$
declare n int; begin
  select count(*) into n from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public'
     and c.relname in ('report_validations', 'resolution_confirmations')
     and c.relrowsecurity = true;
  assert n = 2, 'FALLO 1a: RLS no está habilitada en las tablas de acciones';
  raise notice 'OK 1a: RLS habilitada en report_validations y resolution_confirmations';
end $$;

do $$
declare n int; begin
  select count(*) into n
    from pg_constraint
   where conname in ('report_validations_unique_user',
                     'resolution_confirmations_unique_user')
     and contype = 'u';
  assert n = 2, 'FALLO 1b: faltan los UNIQUE (report_id, user_id)';
  raise notice 'OK 1b: UNIQUE (report_id, user_id) en ambas tablas';
end $$;

-- 1c. La unicidad la aplica la base, no Flutter: insertando directo como
-- administrador se rechaza el segundo registro idéntico.
do $$
declare v_user uuid; begin
  select id into v_user from public.app_users
   where auth_user_id = '22222222-2222-4222-8222-222222222222';

  insert into public.report_validations (report_id, user_id)
  values ('00000000-0000-4000-8000-0000000000a1', v_user);

  begin
    insert into public.report_validations (report_id, user_id)
    values ('00000000-0000-4000-8000-0000000000a1', v_user);
    raise exception 'FALLO 1c: la base aceptó una validación duplicada';
  exception when unique_violation then
    raise notice 'OK 1c: UNIQUE rechaza la segunda validación de la misma identidad';
  end;

  delete from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000a1';
end $$;

-- =====================================================================
-- 2. RLS: el cliente no toca tablas de acciones ni campos críticos
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';

do $$ begin
  perform count(*) from public.report_validations;
  raise exception 'FALLO 2a: authenticated puede leer report_validations';
exception when insufficient_privilege then
  raise notice 'OK 2a: lectura directa de report_validations bloqueada';
end $$;

do $$ begin
  perform count(*) from public.resolution_confirmations;
  raise exception 'FALLO 2b: authenticated puede leer resolution_confirmations';
exception when insufficient_privilege then
  raise notice 'OK 2b: lectura directa de resolution_confirmations bloqueada';
end $$;

do $$ begin
  insert into public.report_validations (report_id, user_id)
  values ('00000000-0000-4000-8000-0000000000a1',
          (select id from public.app_users
            where auth_user_id = '22222222-2222-4222-8222-222222222222'));
  raise exception 'FALLO 2c: INSERT directo en report_validations permitido';
exception when insufficient_privilege then
  raise notice 'OK 2c: INSERT directo en report_validations bloqueado';
end $$;

do $$ begin
  insert into public.resolution_confirmations (report_id, user_id)
  values ('00000000-0000-4000-8000-0000000000a2',
          (select id from public.app_users
            where auth_user_id = '22222222-2222-4222-8222-222222222222'));
  raise exception 'FALLO 2d: INSERT directo en resolution_confirmations permitido';
exception when insufficient_privilege then
  raise notice 'OK 2d: INSERT directo en resolution_confirmations bloqueado';
end $$;

do $$ begin
  delete from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000a1';
  raise exception 'FALLO 2e: DELETE directo en report_validations permitido';
exception when insufficient_privilege then
  raise notice 'OK 2e: DELETE directo bloqueado (no se puede alterar el resultado)';
end $$;

do $$ begin
  update public.reports set validation_count = 99
   where id = '00000000-0000-4000-8000-0000000000a1';
  raise exception 'FALLO 2f: el cliente modificó validation_count';
exception when insufficient_privilege then
  raise notice 'OK 2f: validation_count no es modificable por el cliente';
end $$;

do $$ begin
  update public.reports set resolution_confirmation_count = 3
   where id = '00000000-0000-4000-8000-0000000000a2';
  raise exception 'FALLO 2g: el cliente modificó resolution_confirmation_count';
exception when insufficient_privilege then
  raise notice 'OK 2g: resolution_confirmation_count no es modificable por el cliente';
end $$;

do $$ begin
  update public.reports
     set status = 'RESOLVED', resolved_at = now()
   where id = '00000000-0000-4000-8000-0000000000a2';
  raise exception 'FALLO 2h: el cliente modificó status/resolved_at';
exception when insufficient_privilege then
  raise notice 'OK 2h: status y resolved_at no son modificables por el cliente';
end $$;

do $$ begin
  update public.reports set resolved_at = now()
   where id = '00000000-0000-4000-8000-0000000000a2';
  raise exception 'FALLO 2i: el cliente modificó resolved_at';
exception when insufficient_privilege then
  raise notice 'OK 2i: resolved_at no es modificable por el cliente';
end $$;

-- 2j. anon no puede ejecutar las RPC (sin GRANT).
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$ begin
  perform public.validate_leak('00000000-0000-4000-8000-0000000000a1');
  raise exception 'FALLO 2j: anon pudo ejecutar validate_leak';
exception when insufficient_privilege then
  raise notice 'OK 2j: anon no puede validar (permiso denegado)';
end $$;

do $$ begin
  perform public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a2');
  raise exception 'FALLO 2k: anon pudo ejecutar confirm_leak_resolution';
exception when insufficient_privilege then
  raise notice 'OK 2k: anon no puede confirmar resolución (permiso denegado)';
end $$;

-- =====================================================================
-- 3. RPC validate_leak
-- =====================================================================
-- 3a. Sesión authenticated sin usuario válido → UNAUTHORIZED.
set role authenticated;
set request.jwt.claims = '{"role": "authenticated", "aud": "authenticated"}';
do $$ begin
  assert (public.validate_leak('00000000-0000-4000-8000-0000000000a1'))->>'status_code'
    = 'UNAUTHORIZED',
    'FALLO 3a: sin identidad se validó la fuga';
  raise notice 'OK 3a: sin identidad → UNAUTHORIZED';
end $$;

-- 3b. Usuario B valida la fuga R1 de A (REQ-040).
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
do $$
declare resp jsonb; v_count int; v_rows int; begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'VALIDATED', 'FALLO 3b: ' || resp::text;

  -- Las tablas de acciones no son legibles por el cliente: la verificación
  -- de la consistencia se hace como administrador de BD.
  set local role postgres;
  select validation_count into v_count from public.reports
   where id = '00000000-0000-4000-8000-0000000000a1';
  select count(*) into v_rows from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;

  assert v_count = 1, 'FALLO 3b-2: contador esperado 1, obtenido ' || v_count;
  assert v_rows = 1, 'FALLO 3b-3: validaciones persistidas esperadas 1';
  assert (resp->>'threshold')::int = 3, 'FALLO 3b-4: umbral distinto de 3';
  raise notice 'OK 3b: validación registrada y contador consistente (1)';
end $$;

do $$
declare n int; begin
  set local role postgres;
  select count(*) into n from public.audit_events
   where event_type = 'REPORT_VALIDATED'
     and entity_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert n = 1, 'FALLO 3b-5: auditoría de validación ausente';
  raise notice 'OK 3b-5: audit_events registra REPORT_VALIDATED';
end $$;

-- 3c. Segunda validación del mismo usuario → DUPLICATE_ACTION sin efectos
-- (REQ-042: ni contador ni registro nuevo).
do $$
declare resp jsonb; v_count int; v_rows int; begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'DUPLICATE_ACTION',
    'FALLO 3c: segunda validación no fue DUPLICATE_ACTION: ' || resp::text;
  assert resp->>'already_validated' = 'true',
    'FALLO 3c-2: la respuesta no marca already_validated';
  assert resp->>'message' is not null, 'FALLO 3c-3: sin mensaje para el usuario';

  set local role postgres;
  select validation_count into v_count from public.reports
   where id = '00000000-0000-4000-8000-0000000000a1';
  select count(*) into v_rows from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert v_count = 1, 'FALLO 3c-4: el contador se incrementó dos veces';
  assert v_rows = 1, 'FALLO 3c-5: se creó un segundo registro';
  raise notice 'OK 3c: segunda validación no incrementa el contador';
end $$;

-- 3d. El creador no puede validar su propia fuga (REQ-041).
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare resp jsonb; v_count int; begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'FORBIDDEN',
    'FALLO 3d: el creador pudo validar su fuga: ' || resp::text;
  assert resp->>'message' like '%propio reporte%',
    'FALLO 3d-2: mensaje inesperado: ' || (resp->>'message');

  set local role postgres;
  select validation_count into v_count from public.reports
   where id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert v_count = 1, 'FALLO 3d-3: el intento del creador alteró el contador';
  raise notice 'OK 3d: el creador no valida su propio reporte';
end $$;

-- 3e. Usuario bloqueado (REQ-090) → FORBIDDEN, sin registro.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "55555555-5555-4555-8555-555555555555", "aud": "authenticated"}';
do $$
declare resp jsonb; v_rows int; begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'FORBIDDEN',
    'FALLO 3e: un usuario bloqueado pudo validar: ' || resp::text;
  assert resp->>'message' like '%bloqueado%',
    'FALLO 3e-2: mensaje inesperado: ' || (resp->>'message');

  set local role postgres;
  select count(*) into v_rows from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert v_rows = 1, 'FALLO 3e-3: el usuario bloqueado dejó registro';
  raise notice 'OK 3e: usuario bloqueado no puede validar';
end $$;

-- 3f. Reporte inexistente → NOT_FOUND.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "33333333-3333-4333-8333-333333333333", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.validate_leak('aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid);
  assert resp->>'status_code' = 'NOT_FOUND',
    'FALLO 3f: reporte inexistente no devolvió NOT_FOUND: ' || resp::text;
  raise notice 'OK 3f: reporte inexistente → NOT_FOUND';
end $$;

-- 3g. Reporte RESOLVED → REPORT_ALREADY_RESOLVED, sin registro.
do $$
declare resp jsonb; v_rows int; begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000a3');
  assert resp->>'status_code' = 'REPORT_ALREADY_RESOLVED',
    'FALLO 3g: se validó una fuga resuelta: ' || resp::text;

  set local role postgres;
  select count(*) into v_rows from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000a3';
  set local role authenticated;
  assert v_rows = 0, 'FALLO 3g-2: se persistió una validación sobre RESOLVED';
  raise notice 'OK 3g: una fuga RESOLVED no acepta validaciones';
end $$;

-- 3h. Otra identidad (C) valida la misma fuga: el contador sube a 2.
do $$
declare resp jsonb; v_count int; begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'VALIDATED', 'FALLO 3h: ' || resp::text;

  select validation_count into v_count from public.reports
   where id = '00000000-0000-4000-8000-0000000000a1';
  assert v_count = 2, 'FALLO 3h-2: contador esperado 2, obtenido ' || v_count;
  raise notice 'OK 3h: identidades distintas suman validaciones (2)';
end $$;

-- =====================================================================
-- 4. RPC confirm_leak_resolution (umbral 3, REQ-053)
-- =====================================================================
-- La lectura directa de system_config es interna (migración 00027, AUD-S08-04:
-- el cliente ya no tiene grant; solo el owner/postgres lee la tabla).
set local role postgres;
do $$
declare v jsonb; begin
  select value into v from public.system_config where key = 'resolution';
  assert (v->>'threshold')::int = 3,
    'FALLO 4-0: el umbral configurado no es 3: ' || v::text;
  raise notice 'OK 4-0: umbral de resolución configurado = 3';
end $$;
set local role authenticated;

-- 4a. Sin identidad → UNAUTHORIZED.
set request.jwt.claims = '{"role": "authenticated", "aud": "authenticated"}';
do $$ begin
  assert (public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a2'))->>'status_code'
    = 'UNAUTHORIZED', 'FALLO 4a: sin identidad se confirmó resolución';
  raise notice 'OK 4a: sin identidad → UNAUTHORIZED';
end $$;

-- 4b. Confirmación 1 (B) → CONFIRMED, sigue ACTIVE.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
do $$
declare resp jsonb; v record; begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a2');
  assert resp->>'status_code' = 'CONFIRMED',
    'FALLO 4b: primera confirmación inesperada: ' || resp::text;
  assert (resp->>'resolution_confirmation_count')::int = 1,
    'FALLO 4b-2: contador de confirmaciones distinto de 1';

  select status, resolved_at into v from public.reports
   where id = '00000000-0000-4000-8000-0000000000a2';
  assert v.status = 'ACTIVE', 'FALLO 4b-3: el estado cambió antes del umbral';
  assert v.resolved_at is null, 'FALLO 4b-4: resolved_at no debe existir aún';
  raise notice 'OK 4b: 1/3 confirmaciones → ACTIVE';
end $$;

-- 4c. Repetir la misma identidad → DUPLICATE_ACTION sin efectos.
do $$
declare resp jsonb; v_count int; v_rows int; begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a2');
  assert resp->>'status_code' = 'DUPLICATE_ACTION',
    'FALLO 4c: confirmación duplicada no detectada: ' || resp::text;

  set local role postgres;
  select resolution_confirmation_count into v_count from public.reports
   where id = '00000000-0000-4000-8000-0000000000a2';
  select count(*) into v_rows from public.resolution_confirmations
   where report_id = '00000000-0000-4000-8000-0000000000a2';
  set local role authenticated;
  assert v_count = 1, 'FALLO 4c-2: contador incorrecto tras duplicado';
  assert v_rows = 1, 'FALLO 4c-3: se persistió una confirmación duplicada';
  raise notice 'OK 4c: una identidad no confirma dos veces (REQ-052)';
end $$;

-- 4d. Confirmación 2 (C) → sigue ACTIVE.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "33333333-3333-4333-8333-333333333333", "aud": "authenticated"}';
do $$
declare resp jsonb; v_status text; begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a2');
  assert resp->>'status_code' = 'CONFIRMED', 'FALLO 4d: ' || resp::text;
  assert (resp->>'resolution_confirmation_count')::int = 2,
    'FALLO 4d-2: contador distinto de 2';

  select status into v_status from public.reports
   where id = '00000000-0000-4000-8000-0000000000a2';
  assert v_status = 'ACTIVE', 'FALLO 4d-3: resolvió con 2 identidades';
  raise notice 'OK 4d: 2/3 confirmaciones → ACTIVE';
end $$;

-- 4e. Confirmación 3 (D) → RESOLVED + resolved_at.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "44444444-4444-4444-8444-444444444444", "aud": "authenticated"}';
do $$
declare resp jsonb; v record; v_rows int; begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a2');
  assert resp->>'status_code' = 'RESOLVED',
    'FALLO 4e: la tercera identidad no resolvió la fuga: ' || resp::text;
  assert (resp->>'resolution_confirmation_count')::int = 3,
    'FALLO 4e-2: contador distinto de 3 (umbral)';
  assert resp->>'resolved_at' is not null,
    'FALLO 4e-3: resolved_at no se estableció';

  set local role postgres;
  select status, resolved_at into v from public.reports
   where id = '00000000-0000-4000-8000-0000000000a2';
  select count(*) into v_rows from public.resolution_confirmations
   where report_id = '00000000-0000-4000-8000-0000000000a2';
  set local role authenticated;
  assert v.status = 'RESOLVED', 'FALLO 4e-4: el estado no quedó RESOLVED';
  assert v.resolved_at is not null, 'FALLO 4e-5: resolved_at vacío';
  assert v_rows = 3, 'FALLO 4e-6: confirmaciones persistidas distintas de 3';
  raise notice 'OK 4e: 3/3 identidades → RESOLVED con resolved_at';
end $$;

do $$
declare n int; begin
  set local role postgres;
  select count(*) into n from public.audit_events
   where event_type = 'REPORT_RESOLVED'
     and entity_id = '00000000-0000-4000-8000-0000000000a2';
  assert n = 1, 'FALLO 4e-7: auditoría REPORT_RESOLVED ausente';
  select count(*) into n from public.audit_events
   where event_type = 'RESOLUTION_CONFIRMED'
     and entity_id = '00000000-0000-4000-8000-0000000000a2';
  assert n = 3, 'FALLO 4e-8: auditoría RESOLUTION_CONFIRMED incompleta';
  set local role authenticated;
  raise notice 'OK 4e-7: auditoría de confirmaciones y resolución presente';
end $$;

-- 4f. Cuarta identidad sobre un reporte resuelto → REPORT_ALREADY_RESOLVED
-- y el estado nunca vuelve a ACTIVE.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "66666666-6666-4666-8666-666666666666", "aud": "authenticated"}';
do $$
declare resp jsonb; v_status text; v_resolved timestamptz; begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a2');
  assert resp->>'status_code' = 'REPORT_ALREADY_RESOLVED',
    'FALLO 4f: un reporte resuelto aceptó otra confirmación: ' || resp::text;

  set local role postgres;
  select status, resolved_at into v_status, v_resolved
    from public.reports where id = '00000000-0000-4000-8000-0000000000a2';
  set local role authenticated;
  assert v_status = 'RESOLVED', 'FALLO 4f-2: el estado cambió desde RESOLVED';
  assert v_resolved is not null, 'FALLO 4f-3: resolved_at se perdió';
  raise notice 'OK 4f: RESOLVED no vuelve a ACTIVE ni acepta más acciones';
end $$;

-- 4g. Usuario bloqueado → FORBIDDEN.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "55555555-5555-4555-8555-555555555555", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a4');
  assert resp->>'status_code' = 'FORBIDDEN',
    'FALLO 4g: un usuario bloqueado confirmó resolución: ' || resp::text;
  raise notice 'OK 4g: usuario bloqueado no puede confirmar resolución';
end $$;

-- 4h. Reporte inexistente → NOT_FOUND (identidad no bloqueada).
set request.jwt.claims =
  '{"role": "authenticated", "sub": "66666666-6666-4666-8666-666666666666", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.confirm_leak_resolution('aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid);
  assert resp->>'status_code' = 'NOT_FOUND',
    'FALLO 4h: reporte inexistente no devolvió NOT_FOUND: ' || resp::text;
  raise notice 'OK 4h: reporte inexistente → NOT_FOUND';
end $$;

-- 4i. El creador sí puede confirmar la resolución de su propia fuga
-- (decisión documentada sobre la ambigüedad de REQ-051).
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a4');
  assert resp->>'status_code' = 'CONFIRMED',
    'FALLO 4i: el creador no pudo confirmar resolución: ' || resp::text;
  raise notice 'OK 4i: el creador puede confirmar resolución (una vez)';
end $$;

-- 4j. Umbral configurable: con threshold = 2 la segunda identidad distinta
-- resuelve (demuestra que el valor no está hard-codeado dentro de la función).
set request.jwt.claims =
  '{"role": "authenticated", "sub": "33333333-3333-4333-8333-333333333333", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  set local role postgres;
  update public.system_config
     set value = jsonb_set(value, '{threshold}', '2'::jsonb)
   where key = 'resolution';
  set local role authenticated;

  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000a4');
  assert resp->>'status_code' = 'RESOLVED',
    'FALLO 4j: el umbral configurado (2) no se aplicó: ' || resp::text;

  set local role postgres;
  update public.system_config
     set value = jsonb_set(value, '{threshold}', '3'::jsonb)
   where key = 'resolution';
  raise notice 'OK 4j: el umbral sale de system_config (no hard-codeado)';
end $$;

-- =====================================================================
-- 5. RPC get_leak_report_detail (estado propio para la UI)
-- =====================================================================
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.get_leak_report_detail('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'OK', 'FALLO 5a: ' || resp::text;
  assert resp->>'is_creator' = 'false', 'FALLO 5a-2: is_creator incorrecto';
  assert resp->>'already_validated' = 'true',
    'FALLO 5a-3: no refleja que B ya validó';
  assert resp->>'already_confirmed' = 'false',
    'FALLO 5a-4: already_confirmed incorrecto';
  assert (resp->>'validation_count')::int = 2, 'FALLO 5a-5: contador incorrecto';
  assert (resp->>'threshold')::int = 3, 'FALLO 5a-6: umbral incorrecto';
  assert resp->>'sector_name' = 'Sector Sprint 03',
    'FALLO 5a-7: sector no resuelto';
  raise notice 'OK 5a: detalle con estado del usuario actual';
end $$;

do $$
declare resp jsonb; begin
  resp := public.get_leak_report_detail('00000000-0000-4000-8000-0000000000a4');
  assert resp->>'is_creator' = 'true',
    'FALLO 5b: is_creator falso para el creador';
  raise notice 'OK 5b: el detalle identifica al creador';
end $$;

do $$
declare resp jsonb; begin
  resp := public.get_leak_report_detail('aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid);
  assert resp->>'status_code' = 'NOT_FOUND', 'FALLO 5c: ' || resp::text;
  raise notice 'OK 5c: detalle de reporte inexistente → NOT_FOUND';
end $$;

set request.jwt.claims = '{"role": "authenticated", "aud": "authenticated"}';
do $$ begin
  assert (public.get_leak_report_detail('00000000-0000-4000-8000-0000000000a1'))->>'status_code'
    = 'UNAUTHORIZED', 'FALLO 5d: sin identidad se leyó el detalle';
  raise notice 'OK 5d: sin identidad → UNAUTHORIZED';
end $$;

-- =====================================================================
-- 6. Invariante global: contadores == registros persistidos
-- =====================================================================
set role postgres;
do $$
declare r record; begin
  for r in
    select rep.id,
           rep.validation_count,
           rep.resolution_confirmation_count,
           rep.status,
           rep.resolved_at,
           (select count(*) from public.report_validations v
             where v.report_id = rep.id) as v_rows,
           (select count(*) from public.resolution_confirmations c
             where c.report_id = rep.id) as c_rows
      from public.reports rep
     where rep.id in ('00000000-0000-4000-8000-0000000000a1',
                      '00000000-0000-4000-8000-0000000000a2',
                      '00000000-0000-4000-8000-0000000000a3',
                      '00000000-0000-4000-8000-0000000000a4')
  loop
    assert r.validation_count = r.v_rows,
      format('FALLO 6: validation_count (%s) != validaciones (%s) en %s',
             r.validation_count, r.v_rows, r.id);
    assert r.resolution_confirmation_count = r.c_rows,
      format('FALLO 6: resolution_confirmation_count (%s) != confirmaciones (%s) en %s',
             r.resolution_confirmation_count, r.c_rows, r.id);
    assert (r.status = 'RESOLVED') = (r.resolved_at is not null),
      format('FALLO 6: estado/resolved_at incoherentes en %s', r.id);
  end loop;
  raise notice 'OK 6: contadores y registros consistentes en todos los reportes';
end $$;

-- =====================================================================
-- Limpieza: la transacción completa se revierte.
-- =====================================================================
reset role;
reset request.jwt.claims;
rollback;
do $$ begin
  raise notice 'Todas las pruebas de validate_leak/confirm_leak_resolution pasaron.';
end $$;
