-- tests/water_events_test.sql — Pruebas de Sprint 04:
-- eventos de agua (RPC `register_water_event`, `validate_water_event`,
-- `get_water_event_detail`) y de las tablas `water_events` /
-- `water_event_validations` (constraints, RLS y protección de los campos
-- críticos de `water_events`).
--
-- Ejecutar contra una BD Supabase con las migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/tests/water_events_test.sql
--   (con Supabase local: docker exec -i supabase_db_gota psql -U postgres \
--     -d postgres -v ON_ERROR_STOP=1 < supabase/tests/water_events_test.sql)
--
-- Todo corre en una transacción que se revierte al terminar: el script no
-- deja datos en la base.
--
-- Concurrencia real: no puede simularse dentro de una única sesión SQL. La
-- prueba de concurrencia con sesiones paralelas vive en
-- `supabase/tests/water_events_concurrency_e2e.sh`. Este archivo demuestra
-- la parte estática de la invariante: UNIQUE (water_event_id, user_id) +
-- fila bloqueada (`for update`) + una sola transacción por operación.

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

-- Municipio y sector de trabajo (M1/S1), y un segundo municipio con su
-- sector (M2/S2) para probar la regla de pertenencia municipio/sector.
insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Sprint 04', 'Nueva Esparta', true),
  ('00000000-0000-4000-8000-0000000000f2', 'Municipio Sprint 04 B', 'Nueva Esparta', true)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', 'Sector Sprint 04', true),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f2', 'Sector Sprint 04 B', true)
on conflict (id) do nothing;

do $$ begin
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
     and c.relname in ('water_events', 'water_event_validations')
     and c.relrowsecurity = true;
  assert n = 2, 'FALLO 1a: RLS no está habilitada en water_events/water_event_validations';
  raise notice 'OK 1a: RLS habilitada en water_events y water_event_validations';
end $$;

do $$ begin
  assert exists (select 1 from pg_constraint
    where conname = 'water_event_validations_unique_user' and contype = 'u'),
    'FALLO 1b: falta UNIQUE (water_event_id, user_id)';
  raise notice 'OK 1b: UNIQUE (water_event_id, user_id) en water_event_validations';
end $$;

-- 1c. El event_type solo admite WATER_ARRIVED / WATER_LEFT, aun insertando
-- directo como administrador.
do $$ begin
  begin
    insert into public.water_events
      (created_by, municipality_id, sector_id, event_type, event_time)
    select u.id, '00000000-0000-4000-8000-0000000000f1',
           '00000000-0000-4000-8000-0000000000e1', 'WATER_PENDING', now() - interval '1 hour'
      from public.app_users u
     where u.auth_user_id = '11111111-1111-4111-8111-111111111111';
    raise exception 'FALLO 1c: la base aceptó un event_type inventado';
  exception when check_violation then
    raise notice 'OK 1c: WATER_PENDING y similares son rechazados por el check';
  end;
end $$;

-- =====================================================================
-- 2. RLS: el cliente no toca la tabla de validaciones ni campos críticos
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';

-- 2a. La lectura del historial sí es pública (REQ-076).
do $$ begin
  perform count(*) from public.water_events;
  raise notice 'OK 2a: lectura pública de water_events permitida';
end $$;

do $$ begin
  perform count(*) from public.water_event_validations;
  raise exception 'FALLO 2b: authenticated puede leer water_event_validations';
exception when insufficient_privilege then
  raise notice 'OK 2b: lectura directa de water_event_validations bloqueada';
end $$;

do $$ begin
  insert into public.water_event_validations (water_event_id, user_id)
  values ('00000000-0000-4000-8000-0000000000a1',
          (select id from public.app_users
            where auth_user_id = '22222222-2222-4222-8222-222222222222'));
  raise exception 'FALLO 2c: INSERT directo en water_event_validations permitido';
exception when insufficient_privilege then
  raise notice 'OK 2c: INSERT directo en water_event_validations bloqueado';
end $$;

do $$ begin
  delete from public.water_event_validations;
  raise exception 'FALLO 2d: DELETE directo en water_event_validations permitido';
exception when insufficient_privilege then
  raise notice 'OK 2d: DELETE directo bloqueado (no se puede alterar el resultado)';
end $$;

-- 2e-2j. Los campos críticos de water_events no son modificables por el
-- cliente: ni el contador, ni la identidad, ni tipo/hora/municipio/sector.
do $$ begin
  update public.water_events set validation_count = 99
   where id = '00000000-0000-4000-8000-0000000000a1';
  raise exception 'FALLO 2e: el cliente modificó validation_count';
exception when insufficient_privilege then
  raise notice 'OK 2e: validation_count no es modificable por el cliente';
end $$;

do $$ begin
  update public.water_events
     set created_by = (select id from public.app_users
                        where auth_user_id = '22222222-2222-4222-8222-222222222222')
   where id = '00000000-0000-4000-8000-0000000000a1';
  raise exception 'FALLO 2f: el cliente modificó created_by';
exception when insufficient_privilege then
  raise notice 'OK 2f: created_by no es modificable por el cliente';
end $$;

do $$ begin
  update public.water_events set event_type = 'WATER_LEFT'
   where id = '00000000-0000-4000-8000-0000000000a1';
  raise exception 'FALLO 2g: el cliente modificó event_type';
exception when insufficient_privilege then
  raise notice 'OK 2g: event_type no es modificable por el cliente';
end $$;

do $$ begin
  update public.water_events set event_time = now() - interval '1 day'
   where id = '00000000-0000-4000-8000-0000000000a1';
  raise exception 'FALLO 2h: el cliente modificó event_time';
exception when insufficient_privilege then
  raise notice 'OK 2h: event_time no es modificable por el cliente';
end $$;

do $$ begin
  update public.water_events
     set municipality_id = '00000000-0000-4000-8000-0000000000f2',
         sector_id = '00000000-0000-4000-8000-0000000000e2'
   where id = '00000000-0000-4000-8000-0000000000a1';
  raise exception 'FALLO 2i: el cliente modificó municipality_id/sector_id';
exception when insufficient_privilege then
  raise notice 'OK 2i: municipality_id y sector_id no son modificables por el cliente';
end $$;

do $$ begin
  insert into public.water_events
    (created_by, municipality_id, sector_id, event_type, event_time)
  values ((select id from public.app_users
            where auth_user_id = '22222222-2222-4222-8222-222222222222'),
          '00000000-0000-4000-8000-0000000000f1',
          '00000000-0000-4000-8000-0000000000e1',
          'WATER_ARRIVED', now() - interval '1 hour');
  raise exception 'FALLO 2j: INSERT directo en water_events permitido';
exception when insufficient_privilege then
  raise notice 'OK 2j: INSERT directo en water_events bloqueado (toda creación pasa por la RPC)';
end $$;

-- 2k. anon no puede ejecutar las RPC (sin GRANT).
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$ begin
  perform public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '1 hour', null);
  raise exception 'FALLO 2k: anon pudo ejecutar register_water_event';
exception when insufficient_privilege then
  raise notice 'OK 2k: anon no puede registrar eventos (permiso denegado)';
end $$;

do $$ begin
  perform public.validate_water_event('00000000-0000-4000-8000-0000000000a1');
  raise exception 'FALLO 2l: anon pudo ejecutar validate_water_event';
exception when insufficient_privilege then
  raise notice 'OK 2l: anon no puede validar eventos (permiso denegado)';
end $$;

-- =====================================================================
-- 3. RPC register_water_event (REQ-070/071/072)
-- =====================================================================
-- 3a. Sin identidad → UNAUTHORIZED.
set role authenticated;
set request.jwt.claims = '{"role": "authenticated", "aud": "authenticated"}';
do $$ begin
  assert (public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '1 hour', null))->>'status_code'
    = 'UNAUTHORIZED', 'FALLO 3a: sin identidad se registró el evento';
  raise notice 'OK 3a: sin identidad → UNAUTHORIZED';
end $$;

-- 3b. Usuario A registra WATER_ARRIVED con hora efectiva pasada y sin
-- comentario → CREATED; event_time se conserva distinto de created_at
-- (REQ-072) y created_by queda persistido.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare resp jsonb; v record; v_creator uuid; begin
  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', '2026-09-10 07:30:00+00'::timestamptz, null);
  assert resp->>'status_code' = 'CREATED', 'FALLO 3b: ' || resp::text;

  -- La fila se verifica como administrador de BD.
  set local role postgres;
  select e.* into v from public.water_events e
   where e.id = (resp->>'event_id')::uuid;
  select id into v_creator from public.app_users
   where auth_user_id = '11111111-1111-4111-8111-111111111111';
  set local role authenticated;

  assert v.event_type = 'WATER_ARRIVED', 'FALLO 3b-2: tipo no persistido';
  assert v.event_time = '2026-09-10 07:30:00+00'::timestamptz,
    'FALLO 3b-3: event_time no se conservó (REQ-072)';
  assert v.created_at <> v.event_time, 'FALLO 3b-4: created_at colapsó con event_time';
  assert v.created_at > v.event_time, 'FALLO 3b-5: created_at anterior a event_time';
  assert v.comment is null, 'FALLO 3b-6: comentario nulo no quedó nulo';
  assert v.created_by = v_creator, 'FALLO 3b-7: created_by no quedó persistido';
  assert v.validation_count = 0, 'FALLO 3b-8: contador inicial distinto de 0';
  assert v.municipality_id = '00000000-0000-4000-8000-0000000000f1',
    'FALLO 3b-9: municipality_id no persistido';
  assert v.sector_id = '00000000-0000-4000-8000-0000000000e1',
    'FALLO 3b-10: sector_id no persistido';
  raise notice 'OK 3b: WATER_ARRIVED registrado con event_time propio y created_by persistido';
end $$;

do $$
declare n int; begin
  set local role postgres;
  select count(*) into n from public.audit_events
   where event_type = 'WATER_EVENT_CREATED'
     and entity_type = 'water_event';
  set local role authenticated;
  assert n >= 1, 'FALLO 3b-11: auditoría WATER_EVENT_CREATED ausente';
  raise notice 'OK 3b-11: audit_events registra WATER_EVENT_CREATED';
end $$;

-- 3c. WATER_LEFT con comentario opcional → CREATED y comentario persistido.
do $$
declare resp jsonb; v_comment text; begin
  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_LEFT', now() - interval '2 hours', 'Se fue a media ducha.');
  assert resp->>'status_code' = 'CREATED', 'FALLO 3c: ' || resp::text;

  set local role postgres;
  select comment into v_comment from public.water_events
   where id = (resp->>'event_id')::uuid;
  set local role authenticated;
  assert v_comment = 'Se fue a media ducha.', 'FALLO 3c-2: comentario no persistido';
  raise notice 'OK 3c: WATER_LEFT con comentario opcional persistido';
end $$;

-- 3d. Comentario vacío o de solo espacios se normaliza a NULL (sigue opcional).
do $$
declare resp jsonb; v_comment text; begin
  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '3 hours', '   ');
  assert resp->>'status_code' = 'CREATED', 'FALLO 3d: ' || resp::text;
  set local role postgres;
  select comment into v_comment from public.water_events
   where id = (resp->>'event_id')::uuid;
  set local role authenticated;
  assert v_comment is null, 'FALLO 3d-2: comentario vacío no se normalizó a NULL';
  raise notice 'OK 3d: comentario vacío se guarda como NULL';
end $$;

do $$ begin
  assert (public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '3 hours',
    repeat('x', 501)))->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 3d-3: comentario de 501 caracteres fue aceptado';
  raise notice 'OK 3d-3: comentario mayor de 500 caracteres → VALIDATION_ERROR';
end $$;

-- 3e. Tipo de evento inválido → VALIDATION_ERROR (REQ-070: solo los dos).
do $$ begin
  assert (public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_STARTED', now() - interval '1 hour', null))->>'status_code'
    = 'VALIDATION_ERROR', 'FALLO 3e: WATER_STARTED fue aceptado';
  raise notice 'OK 3e: event_type fuera de la lista → VALIDATION_ERROR';
end $$;

-- 3f. Hora efectiva futura → VALIDATION_ERROR (sanidad mínima documentada).
do $$ begin
  assert (public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() + interval '2 hours', null))->>'status_code'
    = 'VALIDATION_ERROR', 'FALLO 3f: event_time futuro fue aceptado';
  raise notice 'OK 3f: event_time futuro → VALIDATION_ERROR';
end $$;

-- 3g. Hora efectiva nula → VALIDATION_ERROR.
do $$ begin
  assert (public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', null, null))->>'status_code'
    = 'VALIDATION_ERROR', 'FALLO 3g: event_time nulo fue aceptado';
  raise notice 'OK 3g: event_time nulo → VALIDATION_ERROR';
end $$;

-- 3h. Municipio inexistente → NOT_FOUND.
do $$ begin
  assert (public.register_water_event(
    'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid,
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '1 hour', null))->>'status_code'
    = 'NOT_FOUND', 'FALLO 3h: municipio inexistente no devolvió NOT_FOUND';
  raise notice 'OK 3h: municipio inexistente → NOT_FOUND';
end $$;

-- 3i. Sector inexistente → NOT_FOUND.
do $$ begin
  assert (public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid,
    'WATER_ARRIVED', now() - interval '1 hour', null))->>'status_code'
    = 'NOT_FOUND', 'FALLO 3i: sector inexistente no devolvió NOT_FOUND';
  raise notice 'OK 3i: sector inexistente → NOT_FOUND';
end $$;

-- 3j. Sector de otro municipio → INVALID_SECTOR (REQ-071, validación
-- server-side: la combinación municipio A + sector de municipio B se rechaza
-- aunque el cliente la envíe).
do $$ begin
  assert (public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e2',
    'WATER_ARRIVED', now() - interval '1 hour', null))->>'status_code'
    = 'INVALID_SECTOR', 'FALLO 3j: sector de otro municipio fue aceptado';
  raise notice 'OK 3j: sector que no pertenece al municipio → INVALID_SECTOR';
end $$;

-- 3k. Usuario bloqueado → FORBIDDEN, sin evento creado.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "55555555-5555-4555-8555-555555555555", "aud": "authenticated"}';
do $$
declare resp jsonb; v_rows int; begin
  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '1 hour', null);
  assert resp->>'status_code' = 'FORBIDDEN',
    'FALLO 3k: un usuario bloqueado registró un evento: ' || resp::text;
  assert resp->>'message' like '%bloqueado%',
    'FALLO 3k-2: mensaje inesperado: ' || (resp->>'message');

  set local role postgres;
  select count(*) into v_rows from public.audit_events
   where event_type = 'WATER_EVENT_CREATED'
     and user_id = '55555555-5555-4555-8555-555555555555';
  set local role authenticated;
  assert v_rows = 0, 'FALLO 3k-3: el usuario bloqueado dejó auditoría de creación';
  raise notice 'OK 3k: usuario bloqueado no puede registrar eventos';
end $$;

-- =====================================================================
-- 4. RPC validate_water_event (REQ-073/074/075)
-- =====================================================================
-- Preparación: evento propio del usuario A para las pruebas de validación.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_LEFT', now() - interval '30 minutes', null);
  assert resp->>'status_code' = 'CREATED', 'FALLO 4-0: ' || resp::text;
end $$;

do $$
declare v_id uuid; begin
  set local role postgres;
  select id into v_id from public.water_events
   where created_by = (select id from public.app_users
                        where auth_user_id = '11111111-1111-4111-8111-111111111111')
     and event_type = 'WATER_LEFT'
   order by created_at desc limit 1;
  -- Fija un UUID estable para el resto de la sección.
  update public.water_events set id = '00000000-0000-4000-8000-0000000000a1'
   where id = v_id;
  set local role authenticated;
  raise notice 'OK 4-0: evento de prueba fijado en %', '00000000-0000-4000-8000-0000000000a1';
end $$;

-- 4a. Sin identidad → UNAUTHORIZED.
set request.jwt.claims = '{"role": "authenticated", "aud": "authenticated"}';
do $$ begin
  assert (public.validate_water_event('00000000-0000-4000-8000-0000000000a1'))->>'status_code'
    = 'UNAUTHORIZED', 'FALLO 4a: sin identidad se validó el evento';
  raise notice 'OK 4a: sin identidad → UNAUTHORIZED';
end $$;

-- 4b. Usuario B valida el evento de A (REQ-073) → VALIDATED y contador 1.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
do $$
declare resp jsonb; v_count int; v_rows int; begin
  resp := public.validate_water_event('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'VALIDATED', 'FALLO 4b: ' || resp::text;
  assert resp->>'already_validated' = 'false', 'FALLO 4b-2: flag incorrecto';

  set local role postgres;
  select validation_count into v_count from public.water_events
   where id = '00000000-0000-4000-8000-0000000000a1';
  select count(*) into v_rows from public.water_event_validations
   where water_event_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;

  assert v_count = 1, 'FALLO 4b-3: contador esperado 1, obtenido ' || v_count;
  assert v_rows = 1, 'FALLO 4b-4: validaciones persistidas esperadas 1';
  raise notice 'OK 4b: validación registrada y contador consistente (1)';
end $$;

do $$
declare n int; begin
  set local role postgres;
  select count(*) into n from public.audit_events
   where event_type = 'WATER_EVENT_VALIDATED'
     and entity_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert n = 1, 'FALLO 4b-5: auditoría de validación ausente';
  raise notice 'OK 4b-5: audit_events registra WATER_EVENT_VALIDATED';
end $$;

-- 4c. Segunda validación del mismo usuario → DUPLICATE_ACTION sin efectos
-- (REQ-075: ni contador ni registro nuevo).
do $$
declare resp jsonb; v_count int; v_rows int; begin
  resp := public.validate_water_event('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'DUPLICATE_ACTION',
    'FALLO 4c: segunda validación no fue DUPLICATE_ACTION: ' || resp::text;
  assert resp->>'already_validated' = 'true', 'FALLO 4c-2: flag incorrecto';
  assert resp->>'message' is not null, 'FALLO 4c-3: sin mensaje para el usuario';

  set local role postgres;
  select validation_count into v_count from public.water_events
   where id = '00000000-0000-4000-8000-0000000000a1';
  select count(*) into v_rows from public.water_event_validations
   where water_event_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert v_count = 1, 'FALLO 4c-4: el contador se incrementó dos veces';
  assert v_rows = 1, 'FALLO 4c-5: se creó un segundo registro';
  raise notice 'OK 4c: una identidad no valida dos veces el mismo evento';
end $$;

-- 4d. El creador no puede validar su propio evento (REQ-074).
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare resp jsonb; v_count int; begin
  resp := public.validate_water_event('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'FORBIDDEN',
    'FALLO 4d: el creador pudo validar su evento: ' || resp::text;
  assert resp->>'message' like '%propio evento%',
    'FALLO 4d-2: mensaje inesperado: ' || (resp->>'message');

  set local role postgres;
  select validation_count into v_count from public.water_events
   where id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert v_count = 1, 'FALLO 4d-3: el intento del creador alteró el contador';
  raise notice 'OK 4d: el creador no valida su propio evento (REQ-074)';
end $$;

-- 4e. Usuario bloqueado → FORBIDDEN, sin registro.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "55555555-5555-4555-8555-555555555555", "aud": "authenticated"}';
do $$
declare resp jsonb; v_rows int; begin
  resp := public.validate_water_event('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'FORBIDDEN',
    'FALLO 4e: un usuario bloqueado pudo validar: ' || resp::text;

  set local role postgres;
  select count(*) into v_rows from public.water_event_validations
   where water_event_id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert v_rows = 1, 'FALLO 4e-2: el usuario bloqueado dejó registro';
  raise notice 'OK 4e: usuario bloqueado no puede validar';
end $$;

-- 4f. Evento inexistente → NOT_FOUND.
set request.jwt.claims =
  '{"role": "authenticated", "sub": "33333333-3333-4333-8333-333333333333", "aud": "authenticated"}';
do $$ begin
  assert (public.validate_water_event('aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid))->>'status_code'
    = 'NOT_FOUND', 'FALLO 4f: evento inexistente no devolvió NOT_FOUND';
  raise notice 'OK 4f: evento inexistente → NOT_FOUND';
end $$;

-- 4g. Otra identidad (C) valida el mismo evento: el contador sube a 2.
do $$
declare resp jsonb; v_count int; begin
  resp := public.validate_water_event('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'VALIDATED', 'FALLO 4g: ' || resp::text;

  set local role postgres;
  select validation_count into v_count from public.water_events
   where id = '00000000-0000-4000-8000-0000000000a1';
  set local role authenticated;
  assert v_count = 2, 'FALLO 4g-2: contador esperado 2, obtenido ' || v_count;
  raise notice 'OK 4g: identidades distintas suman validaciones (2)';
end $$;

-- =====================================================================
-- 5. RPC get_water_event_detail (estado propio para la UI)
-- =====================================================================
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.get_water_event_detail('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'status_code' = 'OK', 'FALLO 5a: ' || resp::text;
  assert resp->>'is_creator' = 'false', 'FALLO 5a-2: is_creator incorrecto';
  assert resp->>'already_validated' = 'true',
    'FALLO 5a-3: no refleja que B ya validó';
  assert (resp->>'validation_count')::int = 2, 'FALLO 5a-4: contador incorrecto';
  assert resp->>'sector_name' = 'Sector Sprint 04',
    'FALLO 5a-5: sector no resuelto';
  assert resp->>'municipality_name' = 'Municipio Sprint 04',
    'FALLO 5a-6: municipio no resuelto';
  assert resp->>'event_type' = 'WATER_LEFT', 'FALLO 5a-7: tipo incorrecto';
  assert not (resp ? 'created_by'),
    'FALLO 5a-8: el detalle expone created_by';
  raise notice 'OK 5a: detalle con estado del usuario actual y sin created_by';
end $$;

do $$
declare resp jsonb; begin
  resp := public.get_water_event_detail('00000000-0000-4000-8000-0000000000a1');
  -- Como A (creador).
  set local role authenticated;
  -- (la identidad se cambia en el bloque siguiente; aquí B sigue sin ser creador)
  assert resp->>'is_creator' = 'false', 'FALLO 5b: is_creator falso positivo';
  raise notice 'OK 5b: is_creator correcto para no creador';
end $$;

set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare resp jsonb; begin
  resp := public.get_water_event_detail('00000000-0000-4000-8000-0000000000a1');
  assert resp->>'is_creator' = 'true',
    'FALLO 5c: is_creator falso para el creador';
  assert resp->>'already_validated' = 'false',
    'FALLO 5c-2: el creador figura como validador';
  raise notice 'OK 5c: el detalle identifica al creador';
end $$;

set request.jwt.claims =
  '{"role": "authenticated", "sub": "33333333-3333-4333-8333-333333333333", "aud": "authenticated"}';
do $$ begin
  assert (public.get_water_event_detail('aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid))->>'status_code'
    = 'NOT_FOUND', 'FALLO 5d: ' ;
  raise notice 'OK 5d: detalle de evento inexistente → NOT_FOUND';
end $$;

set request.jwt.claims = '{"role": "authenticated", "aud": "authenticated"}';
do $$ begin
  assert (public.get_water_event_detail('00000000-0000-4000-8000-0000000000a1'))->>'status_code'
    = 'UNAUTHORIZED', 'FALLO 5e: sin identidad se leyó el detalle';
  raise notice 'OK 5e: sin identidad → UNAUTHORIZED';
end $$;

-- =====================================================================
-- 6. Invariante global: contadores == registros persistidos
-- =====================================================================
set role postgres;
do $$
declare r record; begin
  for r in
    select e.id, e.validation_count,
           (select count(*) from public.water_event_validations v
             where v.water_event_id = e.id) as v_rows
      from public.water_events e
  loop
    assert r.validation_count = r.v_rows,
      format('FALLO 6: validation_count (%s) != validaciones (%s) en %s',
             r.validation_count, r.v_rows, r.id);
  end loop;
  raise notice 'OK 6: contadores y registros consistentes en todos los eventos';
end $$;

-- =====================================================================
-- Limpieza: la transacción completa se revierte.
-- =====================================================================
reset role;
reset request.jwt.claims;
rollback;
do $$ begin
  raise notice 'Todas las pruebas de water events pasaron.';
end $$;
