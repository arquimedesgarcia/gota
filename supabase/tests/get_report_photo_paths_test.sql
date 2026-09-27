-- tests/get_report_photo_paths_test.sql — Pruebas de la RPC
-- get_report_photo_paths (migración 00034).
--
-- La firma de signed URLs ya no ocurre en SQL (storage.create_signed_url no
-- existe en Supabase); vive en la Edge Function get-report-photos. Esta RPC
-- solo hace el gating y devuelve rutas crudas, y SOLO es invocable por
-- service_role.
--
-- Cubre:
--   1. authenticated NO puede ejecutar la RPC (solo service_role).
--   2. p_auth_uid desconocido → UNAUTHORIZED.
--   3. Usuario bloqueado → FORBIDDEN.
--   4. Reporte inexistente → NOT_FOUND.
--   5. Rate limit (supera el límite configurado).
--   6. Respuesta OK con storage_path/thumbnail_path y orden por sort_order.
--   7. Foto sin thumbnail → thumbnail_path null.
--
-- Ejecutar contra una BD Supabase con todas las migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/tests/get_report_photo_paths_test.sql
--
-- Todo ocurre en una transacción con rollback final.

begin;
set role postgres;
reset request.jwt.claims;

-- =====================================================================
-- Fixtures (UUIDs dedicados; se purgan antes por si quedaron residuos)
-- =====================================================================
-- Nota: un trigger (on_auth_user_created → handle_new_user) crea la fila de
-- public.app_users automáticamente al insertar en auth.users, con un id
-- generado. Por eso NO se inserta app_users a mano; se marca el bloqueado con
-- UPDATE y se referencia app_users.id por subconsulta. El RPC recibe el
-- auth_uid (no el app_user.id), así que el id generado es irrelevante.
delete from public.reports where id = 'c0000015-0000-4000-8000-000000000e01';
delete from auth.users
  where id in ('a0000015-0000-4000-8000-000000000a01',
               'b0000015-0000-4000-8000-000000000b02');
delete from public.sectors        where id = 'f0000015-0000-4000-8000-000000000f02';
delete from public.municipalities where id = 'f0000015-0000-4000-8000-000000000f01';

insert into auth.users (id, email) values
  ('a0000015-0000-4000-8000-000000000a01', 'photoa@gota.test'),
  ('b0000015-0000-4000-8000-000000000b02', 'photob@gota.test');

-- El usuario B es el bloqueado (su app_user lo crea el trigger como no
-- bloqueado; se marca aquí).
update public.app_users set is_blocked = true
  where auth_user_id = 'b0000015-0000-4000-8000-000000000b02';

insert into public.municipalities (id, name, state, country, is_active)
  values ('f0000015-0000-4000-8000-000000000f01',
          'TestMuni', 'TestState', 'VE', true);

insert into public.sectors (id, municipality_id, name, is_active)
  values ('f0000015-0000-4000-8000-000000000f02',
          'f0000015-0000-4000-8000-000000000f01', 'TestSector', true);

insert into public.reports
  (id, created_by, municipality_id, sector_id, location, location_source, status)
  values (
    'c0000015-0000-4000-8000-000000000e01',
    (select id from public.app_users
       where auth_user_id = 'a0000015-0000-4000-8000-000000000a01'),
    'f0000015-0000-4000-8000-000000000f01',
    'f0000015-0000-4000-8000-000000000f02',
    extensions.st_setsrid(extensions.st_makepoint(-63.9, 11.0), 4326)::extensions.geography,
    'GPS',
    'ACTIVE'
  );

-- Foto 1: con thumbnail_path
insert into public.report_photos
  (id, report_id, storage_path, thumbnail_path, mime_type, size_bytes,
   width, height, sort_order)
  values (
    'd0000015-0000-4000-8000-000000000d01',
    'c0000015-0000-4000-8000-000000000e01',
    'report_photos/a0000015-0000-4000-8000-000000000a01/u-1/foto1.jpg',
    'report_photos/a0000015-0000-4000-8000-000000000a01/u-1/foto1_thumb.jpg',
    'image/jpeg', 80000, 1280, 960, 1
  );

-- Foto 2: SIN thumbnail_path
insert into public.report_photos
  (id, report_id, storage_path, thumbnail_path, mime_type, size_bytes,
   width, height, sort_order)
  values (
    'd0000015-0000-4000-8000-000000000d02',
    'c0000015-0000-4000-8000-000000000e01',
    'report_photos/a0000015-0000-4000-8000-000000000a01/u-1/foto2.jpg',
    null,
    'image/jpeg', 90000, 1280, 720, 2
  );

-- =====================================================================
-- 1. authenticated NO puede ejecutar la RPC (solo service_role)
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role":"authenticated","sub":"a0000015-0000-4000-8000-000000000a01","aud":"authenticated"}';

do $$
begin
  begin
    perform public.get_report_photo_paths(
      'a0000015-0000-4000-8000-000000000a01',
      'c0000015-0000-4000-8000-000000000e01');
    raise exception 'FALLO 1: authenticated pudo ejecutar la RPC (debía ser denegado)';
  exception when insufficient_privilege then
    raise notice 'OK 1: authenticated denegado (insufficient_privilege)';
  end;
end $$;

-- A partir de aquí, la RPC se ejecuta como service_role (lo hace la Edge Function).
reset role;
set role service_role;

-- =====================================================================
-- 2. p_auth_uid desconocido → UNAUTHORIZED
-- =====================================================================
do $$
declare v_result jsonb; begin
  select public.get_report_photo_paths(
    '00000000-0000-0000-0000-000000000000',
    'c0000015-0000-4000-8000-000000000e01') into v_result;
  assert (v_result->>'status_code') = 'UNAUTHORIZED',
    format('FALLO 2: esperaba UNAUTHORIZED, recibí %s', v_result->>'status_code');
  raise notice 'OK 2: auth_uid desconocido → UNAUTHORIZED';
end $$;

-- =====================================================================
-- 3. Usuario bloqueado → FORBIDDEN
-- =====================================================================
do $$
declare v_result jsonb; begin
  select public.get_report_photo_paths(
    'b0000015-0000-4000-8000-000000000b02',
    'c0000015-0000-4000-8000-000000000e01') into v_result;
  assert (v_result->>'status_code') = 'FORBIDDEN',
    format('FALLO 3: esperaba FORBIDDEN, recibí %s', v_result->>'status_code');
  raise notice 'OK 3: usuario bloqueado → FORBIDDEN';
end $$;

-- =====================================================================
-- 4. Reporte inexistente → NOT_FOUND
-- =====================================================================
do $$
declare v_result jsonb; begin
  select public.get_report_photo_paths(
    'a0000015-0000-4000-8000-000000000a01',
    '00000000-0000-0000-0000-000000000000') into v_result;
  assert (v_result->>'status_code') = 'NOT_FOUND',
    format('FALLO 4: esperaba NOT_FOUND, recibí %s', v_result->>'status_code');
  raise notice 'OK 4: reporte inexistente → NOT_FOUND';
end $$;

-- =====================================================================
-- 5. Rate limit — superar el límite configurado
-- =====================================================================
reset role;
set role postgres;
insert into public.rate_limit_tracking
  (user_id, operation_type, window_start, count)
  values (
    (select id from public.app_users
       where auth_user_id = 'a0000015-0000-4000-8000-000000000a01'),
    'get_report_photos',
    date_trunc('hour', now()),
    60   -- límite configurado en 00033; la siguiente llamada lo supera
  )
on conflict (user_id, operation_type, window_start)
  do update set count = excluded.count;

set role service_role;
do $$
declare v_result jsonb; begin
  select public.get_report_photo_paths(
    'a0000015-0000-4000-8000-000000000a01',
    'c0000015-0000-4000-8000-000000000e01') into v_result;
  assert (v_result->>'status_code') = 'RATE_LIMIT_EXCEEDED',
    format('FALLO 5: esperaba RATE_LIMIT_EXCEEDED, recibí %s', v_result->>'status_code');
  raise notice 'OK 5: rate limit superado → RATE_LIMIT_EXCEEDED';
end $$;

reset role;
set role postgres;
delete from public.rate_limit_tracking
  where user_id = (select id from public.app_users
                     where auth_user_id = 'a0000015-0000-4000-8000-000000000a01')
    and operation_type = 'get_report_photos';

-- =====================================================================
-- 6. OK — rutas crudas presentes y ordenadas por sort_order
-- =====================================================================
set role service_role;
do $$
declare
  v_result jsonb;
  v_photos jsonb;
  v_photo1 jsonb;
  v_photo2 jsonb;
begin
  select public.get_report_photo_paths(
    'a0000015-0000-4000-8000-000000000a01',
    'c0000015-0000-4000-8000-000000000e01') into v_result;

  assert (v_result->>'status_code') = 'OK',
    format('FALLO 6a: esperaba OK, recibí %s', v_result->>'status_code');

  v_photos := v_result->'photos';
  assert jsonb_array_length(v_photos) = 2,
    format('FALLO 6b: esperaba 2 fotos, recibí %s', jsonb_array_length(v_photos));

  v_photo1 := v_photos->0;
  v_photo2 := v_photos->1;

  assert (v_photo1->>'sort_order')::int = 1,
    'FALLO 6c: primera foto debería ser sort_order=1';
  assert (v_photo2->>'sort_order')::int = 2,
    'FALLO 6d: segunda foto debería ser sort_order=2';

  assert v_photo1->>'storage_path' =
    'report_photos/a0000015-0000-4000-8000-000000000a01/u-1/foto1.jpg',
    'FALLO 6e: storage_path de la foto 1 no coincide';

  raise notice 'OK 6: respuesta OK con rutas crudas ordenadas por sort_order';
end $$;

-- =====================================================================
-- 7. Foto sin thumbnail → thumbnail_path null
-- =====================================================================
do $$
declare
  v_result jsonb;
  v_photo1 jsonb;
  v_photo2 jsonb;
begin
  select public.get_report_photo_paths(
    'a0000015-0000-4000-8000-000000000a01',
    'c0000015-0000-4000-8000-000000000e01') into v_result;

  v_photo1 := (v_result->'photos')->0;
  v_photo2 := (v_result->'photos')->1;

  assert v_photo1->>'thumbnail_path' is not null,
    'FALLO 7a: foto 1 tiene thumbnail_path pero llegó null';
  assert v_photo2->>'thumbnail_path' is null,
    format('FALLO 7b: foto 2 no tiene thumb pero thumbnail_path = %s',
           v_photo2->>'thumbnail_path');

  raise notice 'OK 7: thumbnail_path null cuando no hay miniatura';
end $$;

-- =====================================================================
-- Final
-- =====================================================================
reset role;
reset request.jwt.claims;
do $$ begin
  raise notice 'Todas las pruebas de get_report_photo_paths pasaron.';
end $$;
rollback;
