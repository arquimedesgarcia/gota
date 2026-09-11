-- tests/rls_test.sql — Pruebas de RLS para Gota (SQL plano, sin pgTAP).
-- Ejecutar contra la BD local de Supabase, por ejemplo:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_test.sql
-- Requiere que las migraciones estén aplicadas. Todo corre en una transacción
-- y se revierte al final (rollback), dejando la BD sin datos de prueba.

begin;

-- =====================================================================
-- Preparación: rol administrativo y datos de prueba (RLS no aplica al
-- dueño de las tablas; el trigger aprovisiona las filas de app_users).
-- =====================================================================
set role postgres;
reset request.jwt.claims;

-- Usuarios de auth de prueba (el trigger handle_new_user crea sus app_users).
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'usera@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'userb@gota.test')
on conflict (id) do nothing;

insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Test Activo',   'Nueva Esparta', true),
  ('00000000-0000-4000-8000-0000000000f2', 'Municipio Test Inactivo', 'Nueva Esparta', false)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', 'Sector Test Activo',   true),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1', 'Sector Test Inactivo', false)
on conflict (id) do nothing;

-- =====================================================================
-- 1. Rol anon (sin sesión)
-- =====================================================================
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';

-- 1a. Anon lee municipios activos y no ve los inactivos.
do $$
declare
  n int;
begin
  select count(*) into n from public.municipalities where is_active = true;
  assert n >= 1, 'FALLO 1a: anon no lee municipios activos';
  select count(*) into n from public.municipalities where is_active = false;
  assert n = 0, 'FALLO 1a: anon ve municipios inactivos (RLS no filtra)';
  raise notice 'OK 1a: anon lee solo municipios activos';
end $$;

-- 1b. Anon lee sectores activos y no ve los inactivos.
do $$
declare
  n int;
begin
  select count(*) into n from public.sectors where is_active = true;
  assert n >= 1, 'FALLO 1b: anon no lee sectores activos';
  select count(*) into n from public.sectors where is_active = false;
  assert n = 0, 'FALLO 1b: anon ve sectores inactivos (RLS no filtra)';
  raise notice 'OK 1b: anon lee solo sectores activos';
end $$;

-- 1c. app_users no es legible con la clave anónima: sin GRANT => permiso denegado.
do $$
begin
  perform 1 from public.app_users limit 1;
  raise exception 'FALLO 1c: anon pudo leer app_users';
exception
  when insufficient_privilege then
    raise notice 'OK 1c: anon no puede leer app_users (permiso denegado)';
end $$;

-- =====================================================================
-- 2. Rol authenticated, usuario A
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 2a. A ve su propia fila de app_users.
do $$
declare
  own_id uuid;
begin
  select id into own_id
  from public.app_users
  where auth_user_id = '11111111-1111-4111-8111-111111111111';
  assert own_id is not null, 'FALLO 2a: usuario A no ve su propia fila de app_users';
  raise notice 'OK 2a: usuario A lee su propia fila';
end $$;

-- 2b. A no puede leer la fila del usuario B.
do $$
declare
  n int;
begin
  select count(*) into n
  from public.app_users
  where auth_user_id = '22222222-2222-4222-8222-222222222222';
  assert n = 0, 'FALLO 2b: usuario A pudo leer la fila del usuario B';
  select count(*) into n from public.app_users;
  assert n = 1, format('FALLO 2b: usuario A ve %s filas en app_users (esperaba solo la suya)', n);
  raise notice 'OK 2b: usuario A no ve la fila ajena';
end $$;

-- 2c. A puede actualizar solo last_seen_at de su fila.
do $$
begin
  update public.app_users
  set last_seen_at = now()
  where auth_user_id = '11111111-1111-4111-8111-111111111111';
  assert found, 'FALLO 2c: usuario A no pudo actualizar last_seen_at';
  raise notice 'OK 2c: usuario A actualiza last_seen_at';
end $$;

-- 2d. A no puede modificar is_blocked (GRANT solo sobre last_seen_at).
do $$
begin
  update public.app_users
  set is_blocked = true
  where auth_user_id = '11111111-1111-4111-8111-111111111111';
  raise exception 'FALLO 2d: usuario A pudo modificar is_blocked';
exception
  when insufficient_privilege then
    raise notice 'OK 2d: usuario A no puede modificar is_blocked';
end $$;

-- 2e. app_users no acepta INSERT directo del cliente (AUD-S1-04: la fila
--     la crean el trigger y ensure_app_user, ambas security definer).
do $$
begin
  insert into public.app_users (auth_user_id)
  values ('11111111-1111-4111-8111-111111111111');
  raise exception 'FALLO 2e: authenticated pudo hacer INSERT directo en app_users';
exception
  when insufficient_privilege then
    raise notice 'OK 2e: authenticated no puede hacer INSERT directo en app_users (GRANT/RLS)';
end $$;

-- 2f. ensure_app_user es idempotente y devuelve la fila correcta.
--     (AUD-S1-06: la RPC ahora firma jsonb y controla sesiones sin `sub`.)
do $$
declare
  r1 jsonb;
  r2 jsonb;
begin
  select public.ensure_app_user() into r1;
  select public.ensure_app_user() into r2;
  assert r1->>'id' is not null, 'FALLO 2f: ensure_app_user devolvió null';
  assert r1->>'id' = r2->>'id', 'FALLO 2f: ensure_app_user creó o devolvió filas distintas (no idempotente)';
  assert r1->>'auth_user_id' = '11111111-1111-4111-8111-111111111111',
    'FALLO 2f: ensure_app_user devolvió la fila de otro usuario';
  raise notice 'OK 2f: ensure_app_user es idempotente';
end $$;

-- 2g. ensure_app_user sin identidad (claim sub nulo): debe devolver
--     UNAUTHORIZED controlado y NO insertar ni lanzar violación NOT NULL.
do $$
declare
  r jsonb;
  n int;
begin
  set local request.jwt.claims =
    '{"role": "authenticated", "sub": null, "aud": "authenticated"}';
  r := public.ensure_app_user();
  assert r->>'status_code' = 'UNAUTHORIZED',
    'FALLO 2g: ensure_app_user sin sub no devolvió UNAUTHORIZED';
  select count(*) into n from public.app_users
    where auth_user_id is null;
  assert n = 0, 'FALLO 2g: ensure_app_user insertó una fila sin auth_user_id';
  raise notice 'OK 2g: ensure_app_user sin sub devuelve UNAUTHORIZED controlado';
end $$;

-- =====================================================================
-- Limpieza
-- =====================================================================
reset role;
reset request.jwt.claims;

do $$
begin
  raise notice 'Todas las pruebas RLS pasaron.';
end $$;

rollback;
