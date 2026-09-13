-- tests/create_leak_report_test.sql — Pruebas de las tablas reports /
-- report_photos, de la RLS de reportes y de la RPC create_leak_report,
-- incluyendo la validación server-side de fotografías contra
-- `storage.objects` y `system_config.photo_limits`.
--
-- Ejecutar contra una BD Supabase con las migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/create_leak_report_test.sql
--
-- Todo corre en una transacción con rollback final.

begin;
set role postgres;
reset request.jwt.claims;

-- =====================================================================
-- Preparación
-- =====================================================================
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'leaka@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'leakb@gota.test')
on conflict (id) do nothing;

insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Test Activo',    'Nueva Esparta', true),
  ('00000000-0000-4000-8000-0000000000f3', 'Municipio Test Otro',      'Nueva Esparta', true),
  ('00000000-0000-4000-8000-0000000000f2', 'Municipio Test Inactivo',  'Nueva Esparta', false)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', 'Sector Test Activo',    true),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1', 'Sector Test Inactivo',  false),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000f3', 'Sector Otro Municipio', true)
on conflict (id) do nothing;

-- Binarios simulados en Storage (en la app los sube el cliente a su
-- propia carpeta; aquí se siembran como administrador de BD).
-- Carpeta del usuario A = report_photos/11111111-....
create or replace function pg_temp.seed_photo(
  p_name text, p_owner uuid, p_mime text, p_size bigint
) returns void
language sql
as $$
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('report-photos', p_name, p_owner, p_owner::text,
          jsonb_build_object('mimetype', p_mime, 'size', p_size))
  on conflict (bucket_id, name) do update
    set metadata = excluded.metadata,
        owner = excluded.owner,
        owner_id = excluded.owner_id;
$$;

select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/ok1/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/ok2/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 20480);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/ok3/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 30720);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/png1/p1.png',
  '11111111-1111-4111-8111-111111111111', 'image/png', 5120);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/gif1/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/gif', 5120);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/big1/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg',
  10 * 1024 * 1024 + 1);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/sort1/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 1024);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/sort1/p2.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 1024);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/dup1/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 1024);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/dup2/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 1024);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/dup3/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 1024);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/dup4/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 1024);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/cfg1/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/cfg2/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/cfg3/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/desc_validation/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
-- Carpeta del usuario B (no debe poder usarse desde la sesión A).
select pg_temp.seed_photo(
  'report_photos/22222222-2222-4222-8222-222222222222/b1/p1.jpg',
  '22222222-2222-4222-8222-222222222222', 'image/jpeg', 10240);

-- =====================================================================
-- 1. reports: creación y estado por defecto
-- =====================================================================
do $$ begin
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source, description)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(-63.87, 10.99), 4326)::extensions.geography,
    'GPS', 'Tubería rota');
  raise notice 'OK 1: reports inserta con estado ACTIVE por defecto';
end $$;

do $$
declare n int; begin
  select count(*) into n from public.reports where status = 'ACTIVE';
  assert n = 1, 'FALLO 1b: el reporte no quedó ACTIVE';
  raise notice 'OK 1b: estado por defecto ACTIVE';
end $$;

-- =====================================================================
-- 2. reports: constraints de modelo
-- =====================================================================
do $$ begin
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326)::extensions.geography,
    'DRONE');
  raise exception 'FALLO 2a: se aceptó location_source inválido';
exception when check_violation then
  raise notice 'OK 2a: location_source inválido rechazado';
end $$;

do $$ begin
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source, status)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326)::extensions.geography,
    'GPS', 'PENDIENTE');
  raise exception 'FALLO 2b: se aceptó status PENDIENTE';
exception when check_violation then
  raise notice 'OK 2b: status PENDIENTE (prototipo) rechazado';
end $$;

do $$ begin
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source, resolved_at)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326)::extensions.geography,
    'GPS', now());
  raise exception 'FALLO 2c: ACTIVE con resolved_at aceptado';
exception when check_violation then
  raise notice 'OK 2c: ACTIVE con resolved_at rechazado';
end $$;

do $$ begin
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    'aaaaaaaa-0000-4000-8000-0000000000ad'::uuid,
    extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326)::extensions.geography,
    'GPS');
  raise exception 'FALLO 2d: FK de sector no aplicada';
exception when foreign_key_violation then
  raise notice 'OK 2d: sector inexistente rechazado por FK';
end $$;

-- =====================================================================
-- 3. report_photos: máximo 3, orden y FKs
-- =====================================================================
do $$
declare v_report uuid; begin
  insert into public.reports (created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326)::extensions.geography, 'GPS')
  returning id into v_report;

  insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
  values
    (v_report, 'report_photos/constraints/1.jpg', 'image/jpeg', 1000, 1),
    (v_report, 'report_photos/constraints/2.jpg', 'image/jpeg', 1000, 2),
    (v_report, 'report_photos/constraints/3.jpg', 'image/jpeg', 1000, 3);
  raise notice 'OK 3: 3 fotos insertadas';

  begin
    insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
    values (v_report, 'report_photos/constraints/4.jpg', 'image/jpeg', 1000, 4);
    raise exception 'FALLO 3a: se insertó una cuarta foto';
  exception when others then
    if sqlerrm like '%más de 3 fotos%' then
      raise notice 'OK 3a: cuarta foto rechazada por el límite';
    else
      raise exception 'FALLO 3a: error inesperado %', sqlerrm;
    end if;
  end;

  begin
    insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
    values (v_report, 'report_photos/constraints/5.jpg', 'image/jpeg', 1000, 1);
    raise exception 'FALLO 3b: sort_order duplicado aceptado';
  exception when unique_violation then
    raise notice 'OK 3b: sort_order duplicado rechazado';
  when others then
    -- AUD-S2-19: la aserción ya no acepta `when others` como éxito. El
    -- trigger de límite de fotos (enforce_report_photo_limit) se dispara
    -- ANTES de la constraint UNIQUE, así que el desenlace real es ese
    -- error de negocio; se verifica por su mensaje y cualquier otro
    -- error es un fallo de la aserción.
    if sqlerrm like '%más de 3 fotos%' then
      raise notice 'OK 3b: sort_order duplicado rechazado por el límite de fotos (mensaje verificado)';
    else
      raise exception 'FALLO 3b: error inesperado % (ni unique ni límite de fotos)', sqlerrm;
    end if;
  end;

  begin
    insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
    values ('aaaaaaaa-0000-4000-8000-0000000000ad'::uuid,
            'report_photos/x/1.jpg', 'image/jpeg', 1000, 1);
    raise exception 'FALLO 3c: FK de report_photos no aplicada';
  exception when foreign_key_violation then
    raise notice 'OK 3c: foto con reporte inexistente rechazada';
  end;
end $$;

-- =====================================================================
-- 4. RLS de reports (lectura pública, escritura solo server-side)
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

do $$
declare n int; begin
  select count(*) into n from public.reports;
  assert n >= 1, 'FALLO 4a: authenticated no puede leer reports';
  raise notice 'OK 4a: lectura de reports permitida';
end $$;

-- AUD-S2-01 / AUD-S2-02: el cliente NO lee columnas de identidad (REQ-100).
do $$ begin
  perform (select created_by from public.reports limit 1);
  raise exception 'FALLO 4a-priv: authenticated puede leer reports.created_by';
exception when insufficient_privilege then
  raise notice 'OK 4a-priv: reports.created_by no es seleccionable por authenticated';
end $$;

do $$ begin
  perform (select storage_path from public.report_photos limit 1);
  raise exception 'FALLO 4a-priv2: authenticated puede leer report_photos.storage_path';
exception when insufficient_privilege then
  raise notice 'OK 4a-priv2: report_photos (storage_path) revocado para authenticated';
end $$;


do $$ begin
  insert into public.reports (created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326)::extensions.geography, 'GPS');
  raise exception 'FALLO 4b: INSERT directo en reports permitido (eludiría la RPC)';
exception when insufficient_privilege then
  raise notice 'OK 4b: INSERT directo bloqueado por GRANT';
end $$;

do $$ begin
  insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
  values ((select id from public.reports limit 1), 'report_photos/x.jpg', 'image/jpeg', 1000, 1);
  raise exception 'FALLO 4c: INSERT directo en report_photos permitido';
exception when insufficient_privilege then
  raise notice 'OK 4c: INSERT directo en report_photos bloqueado';
end $$;

set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$
declare n int; begin
  select count(*) into n from public.reports;
  assert n >= 1, 'FALLO 4d: anon no lee reports';
  raise notice 'OK 4d: anon lee reports pero no escribe (ver 4b)';
end $$;

-- AUD-S2-01 / AUD-S2-02 (anon): idéntico al de authenticated.
do $$ begin
  perform (select created_by from public.reports limit 1);
  raise exception 'FALLO 4d-priv: anon puede leer reports.created_by';
exception when insufficient_privilege then
  raise notice 'OK 4d-priv: reports.created_by no es seleccionable por anon';
end $$;


-- =====================================================================
-- 5. RPC: sesión y validaciones de entrada
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 5a. anon no puede ejecutarla (sin GRANT).
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$ begin
  perform public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.99, -63.87, 'GPS', null, '[]'::jsonb);
  raise exception 'FALLO 5a: anon pudo ejecutar create_leak_report';
exception when insufficient_privilege then
  raise notice 'OK 5a: anon no puede crear reportes (permiso denegado)';
end $$;

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 5b. municipio inexistente
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid,
    '00000000-0000-4000-8000-0000000000e1',
    10.99, -63.87, 'GPS', null, '[]'::jsonb);
  assert resp->>'status_code' <> 'CREATED', 'FALLO 5b: municipio inválido aceptado';
  raise notice 'OK 5b: municipio inválido rechazado (%)', resp->>'status_code';
end $$;

-- 5c. sector de otro municipio
do $$ begin
  assert (public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e3',
    p_latitude => 10.99, p_longitude => -63.87,
    p_location_source => 'GPS',
    p_photos => '[]'::jsonb))->>'status_code'
    in ('INVALID_SECTOR', 'VALIDATION_ERROR'),
    'FALLO 5c: relación cruzada aceptada';
  raise notice 'OK 5c: municipio/sector cruzados rechazados';
end $$;

-- 5d. sector inactivo
do $$ begin
  assert (public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e2',
    p_latitude => 10.99, p_longitude => -63.87,
    p_location_source => 'GPS',
    p_photos => '[]'::jsonb))->>'status_code' = 'INVALID_SECTOR',
    'FALLO 5d: sector inactivo aceptado';
  raise notice 'OK 5d: sector inactivo rechazado';
end $$;

-- 5e. ubicación fuera de rango
do $$ begin
  assert (public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    999.0, -63.87, 'GPS', null, '[]'::jsonb))->>'status_code' = 'INVALID_LOCATION',
    'FALLO 5e: latitud 999 aceptada';
  raise notice 'OK 5e: ubicación fuera de rango rechazada';
end $$;

-- 5f. fuente de ubicación inválida
do $$ begin
  assert (public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.99, -63.87, 'SATELITE', null, '[]'::jsonb))->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 5f: location_source inválido aceptado';
  raise notice 'OK 5f: fuente de ubicación inválida rechazada';
end $$;

-- 5g. mínimo 1 foto
do $$ begin
  assert (public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.99, -63.87, 'GPS', null, '[]'::jsonb))->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 5g: reporte sin fotos aceptado';
  raise notice 'OK 5g: mínimo 1 foto exigido';
end $$;

-- 5h. máximo 3 fotos (4 > max_count)
do $$ begin
  assert (public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.99, p_longitude => -63.87,
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"a/1.jpg","sort_order":1},
      {"storage_path":"a/2.jpg","sort_order":2},
      {"storage_path":"a/3.jpg","sort_order":3},
      {"storage_path":"a/4.jpg","sort_order":4}
    ]'::jsonb))->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 5h: 4 fotos aceptadas';
  raise notice 'OK 5h: máximo 3 fotos exigido';
end $$;

-- =====================================================================
-- 6. RPC: validación server-side de fotografías (Storage + config)
-- =====================================================================

-- 6a. foto que no existe en Storage
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.601, p_longitude => -63.601,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/inexistente/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'STORAGE_ERROR',
    'FALLO 6a: foto inexistente aceptada: ' || resp::text;
  raise notice 'OK 6a: foto que no está en Storage rechazada';
end $$;

-- 6b. foto de la carpeta de otro usuario
do $$ begin
  assert (public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.602, p_longitude => -63.602,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/22222222-2222-4222-8222-222222222222/b1/p1.jpg","sort_order":1}]'::jsonb))->>'status_code'
    = 'VALIDATION_ERROR',
    'FALLO 6b: se aceptó una foto de otro usuario';
  raise notice 'OK 6b: foto de carpeta ajena rechazada';
end $$;

-- 6c. MIME no permitido (image/gif)
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.603, p_longitude => -63.603,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/gif1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 6c: MIME image/gif aceptado: ' || resp::text;
  assert resp->>'message' like '%Formato%',
    'FALLO 6c: mensaje de formato inesperado: ' || (resp->>'message');
  raise notice 'OK 6c: MIME no permitido rechazado';
end $$;

-- 6d. tamaño excedido (> max_bytes de photo_limits)
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.604, p_longitude => -63.604,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/big1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 6d: foto de más de max_bytes aceptada: ' || resp::text;
  assert resp->>'message' like '%10 MB%',
    'FALLO 6d: mensaje de tamaño inesperado: ' || (resp->>'message');
  raise notice 'OK 6d: tamaño excedido rechazado';
end $$;

-- 6e. orden de fotos inválido (sort_order repetido)
do $$ begin
  assert (public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.605, p_longitude => -63.605,
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/sort1/p1.jpg","sort_order":1},
      {"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/sort1/p2.jpg","sort_order":1}
    ]'::jsonb))->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 6e: sort_order duplicado aceptado';
  raise notice 'OK 6e: orden de fotos inválido rechazado';
end $$;

-- 6f. caso válido: JPEG permitido y tamaño permitido → CREATED
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.980, p_longitude => -63.860,
    p_location_source => 'GPS',
    p_description => 'Fuga en la esquina',
    p_photos => '[
      {"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/ok1/p1.jpg",
       "sort_order":1,"mime_type":"image/jpeg","size_bytes":10240,"width":1600,"height":1200}
    ]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 6f: ' || resp::text;
  assert resp->>'report_id' is not null, 'FALLO 6f-2: sin report_id';
  raise notice 'OK 6f: MIME y tamaño permitidos → CREATED';
end $$;

-- 6g. los metadatos guardados vienen de Storage, no del cliente
-- (AUD-S2-01: report_photos ya no es legible por clientes, así que esta
-- verificación de integridad corre como postgres, no como authenticated).
do $$
declare r record; begin
  set local role postgres;
  select rp.mime_type, rp.size_bytes into r
    from public.report_photos rp
   where rp.storage_path like '%/ok1/p1.jpg';
  assert r.mime_type = 'image/jpeg', 'FALLO 6g: mime_type inesperado';
  assert r.size_bytes = 10240, 'FALLO 6g: size_bytes no proviene de Storage';
  raise notice 'OK 6g: metadatos persistidos desde Storage';
end $$;

-- 6h. una foto ya asociada no se puede reutilizar
do $$ begin
  assert (public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.700, p_longitude => -63.700,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/ok1/p1.jpg","sort_order":1}]'::jsonb))->>'status_code'
    = 'VALIDATION_ERROR',
    'FALLO 6h: se reutilizó una foto ya asociada';
  raise notice 'OK 6h: foto ya asociada rechazada';
end $$;

-- =====================================================================
-- 7. Los límites salen de system_config.photo_limits (no del cliente)
-- =====================================================================
-- 7a. allowed_mime_types = solo PNG → un JPEG se rechaza
do $$
declare resp jsonb; begin
  set local role postgres;
  update public.system_config
     set value = jsonb_set(value, '{allowed_mime_types}', '["image/png"]'::jsonb)
   where key = 'photo_limits';
  set local role authenticated;

  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.900, p_longitude => -63.900,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/cfg1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 7a: la config de MIME no se aplicó: ' || resp::text;
  raise notice 'OK 7a: allowed_mime_types se aplica server-side';
end $$;

-- 7a-2. el mismo usuario con PNG sí puede crear (config respetada en ambos sentidos)
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.901, p_longitude => -63.901,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/png1/p1.png","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 7a-2: PNG permitido rechazado: ' || resp::text;
  raise notice 'OK 7a-2: MIME permitido por la config → CREATED';
end $$;

-- 7b. max_bytes = 1024 → una foto de 10 KB se rechaza
do $$
declare resp jsonb; begin
  set local role postgres;
  update public.system_config
     set value = jsonb_set(
       jsonb_set(value, '{max_bytes}', '1024'::jsonb),
       '{allowed_mime_types}', '["image/jpeg","image/png","image/webp"]'::jsonb)
   where key = 'photo_limits';
  set local role authenticated;

  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.902, p_longitude => -63.902,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/cfg2/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 7b: max_bytes de la config no se aplicó: ' || resp::text;
  raise notice 'OK 7b: max_bytes se aplica server-side';
end $$;

-- 7c. max_count = 1 → dos fotos se rechazan
do $$
declare resp jsonb; begin
  set local role postgres;
  update public.system_config
     set value = jsonb_set(
       jsonb_set(value, '{max_count}', '1'::jsonb), '{max_bytes}', '10485760'::jsonb)
   where key = 'photo_limits';
  set local role authenticated;

  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.903, p_longitude => -63.903,
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/cfg3/p1.jpg","sort_order":1},
      {"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/ok2/p1.jpg","sort_order":2}
    ]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 7c: max_count de la config no se aplicó: ' || resp::text;
  raise notice 'OK 7c: max_count se aplica server-side';
end $$;

-- 7d. límites de duplicado configurables: radio de 5 m
do $$
declare resp jsonb; begin
  set local role postgres;
  update public.system_config
     set value = jsonb_set(value, '{max_count}', '3'::jsonb)
   where key = 'photo_limits';
  update public.system_config
     set value = jsonb_set(value, '{radius_meters}', '5'::jsonb)
   where key = 'duplicate_detection';
  set local role authenticated;

  -- 10 m del reporte creado en 6f (10.980, -63.860) → fuera del radio de 5 m
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.9801, p_longitude => -63.86,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/dup1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 7d: radio configurable no aplicado: ' || resp::text;

  set local role postgres;
  update public.system_config
     set value = jsonb_set(value, '{radius_meters}', '50'::jsonb)
   where key = 'duplicate_detection';
  raise notice 'OK 7d: radius_meters es configurable (5 m no marcó duplicado)';
end $$;

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- =====================================================================
-- 8. Duplicados (50 m / 48 h, ACTIVE)
-- =====================================================================
-- Limpiar rate_limit_tracking para que los casos anteriores no afecten
-- los límites de esta sección (las pruebas de rate limiting están en otra suite).
do $$
begin
  set local role postgres;
  delete from public.rate_limit_tracking;
  set local role authenticated;
end $$;

-- Reporte base de referencia en (10.500, -63.500).
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.500, p_longitude => -63.500,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/dup2/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 8-0: no se pudo crear el reporte base: ' || resp::text;
  raise notice 'OK 8-0: reporte base creado';
end $$;

-- 8a. ≤50 m + ≤48 h → POSSIBLE_DUPLICATE (con distancia)
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.5002, p_longitude => -63.500, -- ~22 m
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/ok3/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'POSSIBLE_DUPLICATE',
    'FALLO 8a: duplicado ≤50 m no detectado: ' || resp::text;
  assert jsonb_array_length(resp->'candidates') >= 1, 'FALLO 8a-2: sin candidatos';
  assert (resp->'candidates'->0->>'distance_meters')::int <= 50,
    'FALLO 8a-3: distancia fuera del radio';
  raise notice 'OK 8a: ≤50 m + ≤48 h → POSSIBLE_DUPLICATE con distancia';
end $$;

-- 8b. el duplicado NO se crea si el usuario no confirma.
-- La verificación de persistencia corre como postgres (8b-2) porque
-- `location` y las columnas revoked ya no permiten count(*) como
-- authenticated (AUD-S2-01).
do $$
declare n int; begin
  select count(*) into n from public.reports
   where status = 'ACTIVE' and municipality_id = '00000000-0000-4000-8000-0000000000f1';
  raise notice 'OK 8b-pre: authenticated puede contar con columnas concedidas (%)', n;
end $$;

-- 8b-2. (server-side) postgres confirma que no hay un reporte a ~22 m
-- distinto del base sin confirmación.
do $$
declare n int; begin
  set local role postgres;
  select count(*) into n from public.reports
   where status = 'ACTIVE'
     and extensions.st_dwithin(location,
       extensions.st_setsrid(extensions.st_makepoint(-63.500, 10.5002), 4326)::extensions.geography,
       10);
  assert n = 0, 'FALLO 8b: se creó el reporte pese al duplicado';
  raise notice 'OK 8b: el posible duplicado no se persiste sin confirmación';
end $$;

-- 8c. REQ-025: con confirmación explícita (p_ignore_duplicate) se crea
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.5002, p_longitude => -63.500,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/ok3/p1.jpg","sort_order":1}]'::jsonb,
    p_ignore_duplicate => true);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 8c: "es otra fuga" no creó el reporte: ' || resp::text;
  raise notice 'OK 8c: "es otra fuga" crea el reporte (REQ-025)';
end $$;

-- 8d. >50 m → sin duplicado
do $$ begin
  assert (public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.5030, p_longitude => -63.500, -- ~333 m
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/dup3/p1.jpg","sort_order":1}]'::jsonb))->>'status_code'
    = 'CREATED',
    'FALLO 8d: >50 m marcado como duplicado';
  raise notice 'OK 8d: >50 m no es duplicado';
end $$;

-- 8e. >48 h → sin duplicado (reporte ACTIVE envejecido 72 h en un punto
-- aislado, para no depender de los casos anteriores)
do $$
declare resp jsonb; begin
  set local role postgres;
  delete from public.rate_limit_tracking;
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source,
     status, created_at)
  values (
    (select id from public.app_users where auth_user_id = '22222222-2222-4222-8222-222222222222'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(-63.300, 10.300), 4326)::extensions.geography,
    'GPS', 'ACTIVE', now() - interval '72 hours');
  set local role authenticated;

  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.300, p_longitude => -63.300, -- misma posición, 72 h después
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/dup4/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 8e: >48 h marcado como duplicado: ' || resp::text;
  raise notice 'OK 8e: >48 h no es duplicado';
end $$;

-- 8f. RESOLVED → sin duplicado
do $$
declare resp jsonb; begin
  set local role postgres;
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source, status, resolved_at)
  values (
    (select id from public.app_users where auth_user_id = '22222222-2222-4222-8222-222222222222'),
    '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
    extensions.st_setsrid(extensions.st_makepoint(-63.400, 10.400), 4326)::extensions.geography,
    'GPS', 'RESOLVED', now());
  set local role authenticated;

  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.400, p_longitude => -63.400,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/sort1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 8f: RESOLVED marcado como duplicado: ' || resp::text;
  raise notice 'OK 8f: RESOLVED no bloquea';
end $$;

-- 8g. auditoría mínima del reporte creado (tabla sin acceso de cliente)
do $$
declare n int; begin
  set local role postgres;
  select count(*) into n from public.audit_events
   where event_type = 'REPORT_CREATED';
  assert n >= 1, 'FALLO 8g: no se registró auditoría de creación';
  raise notice 'OK 8g: audit_events registra REPORT_CREATED (% filas)', n;
end $$;

-- =====================================================================
-- 9. AUD-S2-01/02: privacidad de columnas (REQ-100)
-- =====================================================================
-- El listado embebido que usa la app (community_flow_e2e §7) debe seguir
-- funcionando; created_by NUNCA debe ser seleccionable.
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 9a. el listado de Inicio (columnas concedidas + embeds) sigue legible.
do $$
declare n int; begin
  select count(*) into n
    from public.reports r
    left join public.sectors s on s.id = r.sector_id
    left join public.municipalities m on m.id = r.municipality_id
   where r.id is not null;
  assert n >= 1, 'FALLO 9a: el listado dejó de ser legible tras el GRANT';
  raise notice 'OK 9a: listado (id/status/contadores/created_at/… ) sigue legible';
end $$;

-- 9b. authenticated NO puede leer reports.created_by (REQ-100).
do $$ begin
  perform r.created_by from public.reports r limit 1;
  raise exception 'FALLO 9b: authenticated sigue leyendo reports.created_by';
exception when insufficient_privilege then
  raise notice 'OK 9b: reports.created_by NO es seleccionable (authenticated)';
end $$;

-- 9c. anon tampoco.
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$ begin
  perform r.created_by from public.reports r limit 1;
  raise exception 'FALLO 9c: anon sigue leyendo reports.created_by';
exception when insufficient_privilege then
  raise notice 'OK 9c: reports.created_by NO es seleccionable (anon)';
end $$;

-- 9d. authenticated NO puede leer report_photos.storage_path (AUD-S2-01:
-- la ruta contiene el auth.uid del creador).
do $$ begin
  perform rp.storage_path from public.report_photos rp limit 1;
  raise exception 'FALLO 9d: authenticated sigue leyendo report_photos.storage_path';
exception when insufficient_privilege then
  raise notice 'OK 9d: report_photos.storage_path NO es seleccionable (tabla sin grants)';
end $$;

-- 9e. la tabla completa report_photos no es legible por el cliente
-- (alternativa aceptada por la auditoría; el detalle usa photo_count por RPC).
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$ begin
  perform rp.id from public.report_photos rp limit 1;
  raise exception 'FALLO 9e: authenticated sigue leyendo report_photos';
exception when insufficient_privilege then
  raise notice 'OK 9e: report_photos sin lecturas de cliente';
end $$;

-- =====================================================================
-- 10. AUD-S2-07: el primer candidato es el MÁS CERCANO
-- =====================================================================
-- Tres reportes ACTIVE a distancias distintas dentro del radio; el
-- primero de candidates debe ser el más cercano (y del top-5 ordenado).
do $$
declare resp jsonb;
        d1 int; d2 int; d3 int;
begin
  set local role postgres;
  delete from public.rate_limit_tracking;
  -- Punto de origen del reporte nuevo: (10.200, -63.200).
  insert into public.reports
    (created_by, municipality_id, sector_id, location, location_source)
  values
    ((select id from public.app_users where auth_user_id = '22222222-2222-4222-8222-222222222222'),
     '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
     extensions.st_setsrid(extensions.st_makepoint(-63.200, 10.20040), 4326)::extensions.geography, 'GPS'),
    ((select id from public.app_users where auth_user_id = '22222222-2222-4222-8222-222222222222'),
     '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
     extensions.st_setsrid(extensions.st_makepoint(-63.200, 10.20025), 4326)::extensions.geography, 'GPS'),
    ((select id from public.app_users where auth_user_id = '22222222-2222-4222-8222-222222222222'),
     '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
     extensions.st_setsrid(extensions.st_makepoint(-63.200, 10.20010), 4326)::extensions.geography, 'GPS');
  set local role authenticated;

  -- (Punto aislado; foto no asociada previamente: dup3 quedó libre por 8d.)
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.200, p_longitude => -63.200,
    p_location_source => 'GPS',
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/sort1/p2.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'POSSIBLE_DUPLICATE',
    'FALLO 10: sin duplicados cerca: ' || resp::text;
  assert jsonb_array_length(resp->'candidates') >= 3,
    'FALLO 10-2: faltan candidatos';
  d1 := (resp->'candidates'->0->>'distance_meters')::int;
  d2 := (resp->'candidates'->1->>'distance_meters')::int;
  d3 := (resp->'candidates'->2->>'distance_meters')::int;
  assert d1 <= d2 and d2 <= d3,
    format('FALLO 10-3: candidatos sin orden por distancia: %s, %s, %s', d1, d2, d3);
  -- Cada distancia <= radio (todas caen en la subconsulta ordenada).
  assert d1 <= 50, 'FALLO 10-4: el más cercano excede el radio';
  raise notice 'OK 10: candidates ordenado por distancia (%, %, %)', d1, d2, d3;
end $$;

-- =====================================================================
-- 11. AUD-S2-10: descripción >500 → VALIDATION_ERROR (no error de check)
-- =====================================================================
do $$
declare resp jsonb;
begin
  set local role postgres;
  delete from public.rate_limit_tracking;
  set local role authenticated;
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.120, p_longitude => -63.120,
    p_location_source => 'GPS',
    p_description => repeat('x', 501),
    p_photos => '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/desc_validation/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 11: descripción larga no devolvió VALIDATION_ERROR: ' || resp::text;
  assert resp->>'message' like '%500%',
    'FALLO 11-2: mensaje sin límite de 500: ' || (resp->>'message');
  raise notice 'OK 11: descripción >500 rechazada con VALIDATION_ERROR';
end $$;

-- =====================================================================
-- Limpieza
-- =====================================================================
reset role;
reset request.jwt.claims;
do $$ begin
  raise notice 'Todas las pruebas de create_leak_report pasaron.';
end $$;
rollback;
