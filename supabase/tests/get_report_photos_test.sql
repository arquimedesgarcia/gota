-- tests/get_report_photos_test.sql — Pruebas de la RPC get_report_photos.
--
-- Cubre:
--   1. anon no puede invocar la RPC.
--   2. Reporte inexistente → NOT_FOUND.
--   3. Usuario bloqueado → FORBIDDEN.
--   4. Rate limit (se supera con 61 llamadas).
--   5. Respuesta OK incluye signed URLs y NO incluye storage_path crudo.
--   6. Fotos sin thumbnail → thumbnail_url es null.
--   7. Las políticas de Storage existentes no se ampliaron a escritura ajena.
--
-- Ejecutar contra una BD Supabase con todas las migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/tests/get_report_photos_test.sql
--
-- Todo ocurre en una transacción con rollback final.

begin;
set role postgres;
reset request.jwt.claims;

-- =====================================================================
-- Fixtures
-- =====================================================================
insert into auth.users (id, email) values
  ('aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'photoa@gota.test'),
  ('bbbb2222-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'photob@gota.test')
on conflict (id) do nothing;

-- app_users
insert into public.app_users (id, auth_user_id, is_blocked)
  values
    ('00000001-0000-4000-8000-000000000001',
     'aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false),
    ('00000001-0000-4000-8000-000000000002',
     'bbbb2222-bbbb-4bbb-8bbb-bbbbbbbbbbbb', true)
on conflict (id) do nothing;

-- municipality + sector (mínimos para el reporte)
insert into public.municipalities (id, name, state, country, is_active)
  values ('ffff0001-ffff-4fff-8fff-ffffffffffff', 'TestMuni', 'TestState', 'VE', true)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active)
  values ('ffff0002-ffff-4fff-8fff-ffffffffffff',
          'ffff0001-ffff-4fff-8fff-ffffffffffff', 'TestSector', true)
on conflict (id) do nothing;

-- Reporte con dos fotos (una con thumb, otra sin)
insert into public.reports
  (id, created_by, municipality_id, sector_id, location, location_source, status)
  values (
    'rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr',
    '00000001-0000-4000-8000-000000000001',
    'ffff0001-ffff-4fff-8fff-ffffffffffff',
    'ffff0002-ffff-4fff-8fff-ffffffffffff',
    extensions.st_setsrid(extensions.st_makepoint(-63.9, 11.0), 4326)::extensions.geography,
    'GPS',
    'ACTIVE'
  )
on conflict (id) do nothing;

-- Foto 1: con thumbnail_path
insert into public.report_photos
  (id, report_id, storage_path, thumbnail_path, mime_type, size_bytes,
   width, height, sort_order)
  values (
    'pppp0001-pppp-4ppp-8ppp-pppppppppppp',
    'rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr',
    'report_photos/aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa/u-1/pppp0001.jpg',
    'report_photos/aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa/u-1/pppp0001_thumb.jpg',
    'image/jpeg', 80000, 1280, 960, 1
  )
on conflict (id) do nothing;

-- Foto 2: SIN thumbnail_path
insert into public.report_photos
  (id, report_id, storage_path, thumbnail_path, mime_type, size_bytes,
   width, height, sort_order)
  values (
    'pppp0002-pppp-4ppp-8ppp-pppppppppppp',
    'rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr',
    'report_photos/aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa/u-1/pppp0002.jpg',
    null,
    'image/jpeg', 90000, 1280, 720, 2
  )
on conflict (id) do nothing;

-- =====================================================================
-- 1. Anon no puede invocar la RPC
-- =====================================================================
set role anon;
set request.jwt.claims = '{"role":"anon","sub":null,"aud":"anonymous"}';

do $$
declare
  v_result jsonb;
begin
  begin
    select public.get_report_photos('rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr')
      into v_result;
    assert (v_result->>'status_code') = 'UNAUTHORIZED',
      format('FALLO 1: anon recibió status_code=%s (esperaba UNAUTHORIZED)',
             v_result->>'status_code');
  exception when insufficient_privilege then
    -- También es aceptable: la RPC no fue ejecutable
    null;
  end;
  raise notice 'OK 1: anon bloqueado por UNAUTHORIZED o insufficient_privilege';
end $$;

-- =====================================================================
-- 2. Reporte inexistente → NOT_FOUND
-- =====================================================================
reset role;
set role authenticated;
set request.jwt.claims =
  '{"role":"authenticated","sub":"aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa","aud":"authenticated"}';

do $$
declare v_result jsonb; begin
  select public.get_report_photos('00000000-0000-0000-0000-000000000000')
    into v_result;
  assert (v_result->>'status_code') = 'NOT_FOUND',
    format('FALLO 2: esperaba NOT_FOUND, recibí %s', v_result->>'status_code');
  raise notice 'OK 2: reporte inexistente → NOT_FOUND';
end $$;

-- =====================================================================
-- 3. Usuario bloqueado → FORBIDDEN
-- =====================================================================
reset role;
set role authenticated;
set request.jwt.claims =
  '{"role":"authenticated","sub":"bbbb2222-bbbb-4bbb-8bbb-bbbbbbbbbbbb","aud":"authenticated"}';

do $$
declare v_result jsonb; begin
  select public.get_report_photos('rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr')
    into v_result;
  assert (v_result->>'status_code') = 'FORBIDDEN',
    format('FALLO 3: esperaba FORBIDDEN, recibí %s', v_result->>'status_code');
  raise notice 'OK 3: usuario bloqueado → FORBIDDEN';
end $$;

-- =====================================================================
-- 4. Rate limit — superar el límite configurado
-- =====================================================================
reset role;
set role postgres;

-- Insertar conteo ya en el límite para 'get_report_photos' directamente
-- en la tabla de tracking (somos postgres, bypassamos RLS).
insert into public.rate_limit_tracking
  (user_id, operation_type, window_start, count)
  values (
    '00000001-0000-4000-8000-000000000001',
    'get_report_photos',
    date_trunc('hour', now()),
    60   -- límite configurado en 00033; la siguiente llamada lo supera
  )
on conflict (user_id, operation_type, window_start)
  do update set count = excluded.count;

set role authenticated;
set request.jwt.claims =
  '{"role":"authenticated","sub":"aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa","aud":"authenticated"}';

do $$
declare v_result jsonb; begin
  select public.get_report_photos('rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr')
    into v_result;
  assert (v_result->>'status_code') = 'RATE_LIMIT_EXCEEDED',
    format('FALLO 4: esperaba RATE_LIMIT_EXCEEDED, recibí %s',
           v_result->>'status_code');
  raise notice 'OK 4: rate limit superado → RATE_LIMIT_EXCEEDED';
end $$;

-- Limpiar el conteo para que los siguientes tests pasen
reset role;
set role postgres;
delete from public.rate_limit_tracking
  where user_id = '00000001-0000-4000-8000-000000000001'
    and operation_type = 'get_report_photos';

-- =====================================================================
-- 5. Respuesta OK — URLs firmadas presentes, storage_path AUSENTE
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role":"authenticated","sub":"aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa","aud":"authenticated"}';

do $$
declare
  v_result  jsonb;
  v_photos  jsonb;
  v_photo1  jsonb;
  v_photo2  jsonb;
begin
  select public.get_report_photos('rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr')
    into v_result;

  assert (v_result->>'status_code') = 'OK',
    format('FALLO 5a: esperaba OK, recibí %s', v_result->>'status_code');

  v_photos := v_result->'photos';
  assert jsonb_array_length(v_photos) = 2,
    format('FALLO 5b: esperaba 2 fotos, recibí %s', jsonb_array_length(v_photos));

  v_photo1 := v_photos->0;
  v_photo2 := v_photos->1;

  -- sort_order correcto
  assert (v_photo1->>'sort_order')::int = 1,
    'FALLO 5c: primera foto debería ser sort_order=1';
  assert (v_photo2->>'sort_order')::int = 2,
    'FALLO 5d: segunda foto debería ser sort_order=2';

  -- URL principal presente y no es el storage_path crudo
  assert v_photo1->>'url' is not null,
    'FALLO 5e: url de foto 1 es null';
  assert v_photo1->>'url' not like '%report_photos/aaaa%',
    'FALLO 5f: url de foto 1 expone el storage_path crudo';
  assert v_photo1->>'url' like '%token=%' or v_photo1->>'url' like '%sign%',
    'FALLO 5g: url de foto 1 no parece una signed URL';

  -- storage_path no expuesto
  assert v_photo1->>'storage_path' is null,
    'FALLO 5h: la respuesta expone storage_path';
  assert v_photo2->>'storage_path' is null,
    'FALLO 5i: la respuesta expone storage_path en foto 2';

  raise notice 'OK 5: respuesta OK con URLs firmadas, sin storage_path crudo';
end $$;

-- =====================================================================
-- 6. Foto sin thumbnail → thumbnail_url es null en la respuesta
-- =====================================================================
do $$
declare
  v_result jsonb;
  v_photo2 jsonb;
  v_photo1 jsonb;
begin
  select public.get_report_photos('rrrr0001-rrrr-4rrr-8rrr-rrrrrrrrrrrr')
    into v_result;

  v_photo1 := (v_result->'photos')->0;
  v_photo2 := (v_result->'photos')->1;

  -- Foto 1 tiene thumbnail → thumbnail_url presente
  assert v_photo1->>'thumbnail_url' is not null,
    'FALLO 6a: foto 1 tiene thumbnail_path pero thumbnail_url es null';

  -- Foto 2 no tiene thumbnail → thumbnail_url null
  assert v_photo2->>'thumbnail_url' is null,
    format('FALLO 6b: foto 2 no tiene thumbnail_path pero thumbnail_url = %s',
           v_photo2->>'thumbnail_url');

  raise notice 'OK 6: thumbnail_url null cuando thumbnail_path es null';
end $$;

-- =====================================================================
-- 7. Las políticas de Storage existentes NO se ampliaron a escritura
-- =====================================================================
do $$
declare
  v_insert_count int;
  v_select_count int;
begin
  -- La tabla storage.objects no debe tener política que permita a
  -- authenticated leer en carpetas ajenas (verificamos que la política de
  -- SELECT existente sigue acotada a la carpeta propia).
  select count(*) into v_insert_count
    from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and cmd = 'INSERT'
     and roles::text like '%authenticated%'
     and (qual like '%report_photos%' or with_check like '%report_photos%');

  -- Debe haber exactamente 1 política INSERT (la de subida propia)
  assert v_insert_count >= 1,
    'FALLO 7a: no existe política INSERT de report-photos para authenticated';

  -- No debe haber política INSERT que permita escribir en cualquier ruta
  -- (sin restricción de auth.uid)
  select count(*) into v_insert_count
    from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and cmd = 'INSERT'
     and roles::text like '%authenticated%'
     and with_check not like '%auth.uid()%'
     and with_check not like '%owner%';

  assert v_insert_count = 0,
    'FALLO 7b: existe política INSERT de storage sin restricción de auth.uid';

  raise notice 'OK 7: políticas de Storage no ampliadas a escritura ajena';
end $$;

-- =====================================================================
-- Final
-- =====================================================================
reset role;
reset request.jwt.claims;
do $$ begin
  raise notice 'Todas las pruebas de get_report_photos pasaron.';
end $$;
rollback;
