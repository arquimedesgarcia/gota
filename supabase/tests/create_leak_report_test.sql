-- tests/create_leak_report_test.sql — Pruebas de la RPC create_leak_report
-- y de las tablas reports/report_photos.
-- Ejecutar contra la BD con migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/create_leak_report_test.sql
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
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Test Activo',   'Nueva Esparta', true),
  ('00000000-0000-4000-8000-0000000000f3', 'Municipio Test Otro',    'Nueva Esparta', true),
  ('00000000-0000-4000-8000-0000000000f2', 'Municipio Test Inactivo','Nueva Esparta', false)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', 'Sector Test Activo',   true),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1', 'Sector Test Inactivo', false),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000f3', 'Sector Otro Municipio', true)
on conflict (id) do nothing;

-- =====================================================================
-- 1. reports: creación correcta (como dueño de tablas, valida columnas)
-- =====================================================================
do $$ begin
  insert into public.reports (created_by, municipality_id, sector_id, location, location_source, description)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    st_setsrid(st_makepoint(-63.87, 10.99), 4326)::geography,
    'GPS',
    'Tubería rota'
  );
  raise notice 'OK 1: reports inserta con estado ACTIVE por defecto';
end $$;

do $$
declare n int; begin
  select count(*) into n from public.reports where status = 'ACTIVE';
  assert n = 1, 'FALLO 1: el reporte no quedó ACTIVE';
  raise notice 'OK 1b: estado por defecto ACTIVE';
end $$;

-- =====================================================================
-- 2. reports: constraints
-- =====================================================================
-- 2a. location_source inválido rechazado
do $$ begin
  insert into public.reports (
      created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    st_setsrid(st_makepoint(0, 0), 4326)::geography,
    'DRONE');
  raise exception 'FALLO 2a: se aceptó location_source inválido';
exception when check_violation then
  raise notice 'OK 2a: location_source inválido rechazado';
end $$;

-- 2b. status inválido rechazado (estados históricos prohibidos)
do $$ begin
  insert into public.reports (
      created_by, municipality_id, sector_id, location, location_source, status)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    st_setsrid(st_makepoint(0, 0), 4326)::geography,
    'GPS', 'PENDIENTE');
  raise exception 'FALLO 2b: se aceptó status PENDIENTE';
exception when check_violation then
  raise notice 'OK 2b: status PENDIENTE (prototipo) rechazado';
end $$;

-- 2c. ACTIVE con resolved_at es inconsistente
do $$ begin
  insert into public.reports (
      created_by, municipality_id, sector_id, location,
      location_source, resolved_at)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    st_setsrid(st_makepoint(0, 0), 4326)::geography,
    'GPS', now());
  raise exception 'FALLO 2c: ACTIVE con resolved_at aceptado';
exception when check_violation then
  raise notice 'OK 2c: ACTIVE con resolved_at rechazado';
end $$;

-- 2d. relación municipio/sector: FK de sectors asegura sector válido
do $$ begin
  insert into public.reports (
      created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid, -- no existe
    st_setsrid(st_makepoint(0, 0), 4326)::geography,
    'GPS');
  raise exception 'FALLO 2d: FK de sector no aplicada';
exception when foreign_key_violation then
  raise notice 'OK 2d: sector inexistente rechazado por FK';
end $$;

-- =====================================================================
-- 3. report_photos: máximo 3 y orden
-- =====================================================================
do $$
declare
  v_report uuid;
begin
  insert into public.reports (created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    st_setsrid(st_makepoint(0, 0), 4326)::geography, 'GPS')
  returning id into v_report;

  -- 3 fotos ok
  insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
  values
    (v_report, 'report_photos/r1/1.jpg', 'image/jpeg', 1000, 1),
    (v_report, 'report_photos/r1/2.jpg', 'image/jpeg', 1000, 2),
    (v_report, 'report_photos/r1/3.jpg', 'image/jpeg', 1000, 3);
  raise notice 'OK 3: 3 fotos insertadas';

  -- 3a. una cuarta foto debe ser rechazada
  begin
    insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
    values (v_report, 'report_photos/r1/4.jpg', 'image/jpeg', 1000, 4);
    raise exception 'FALLO 3a: se insertó una cuarta foto';
  exception when others then
    if sqlerrm like '%más de 3 fotos%' then
      raise notice 'OK 3a: cuarta foto rechazada por el límite';
    else
      raise exception 'FALLO 3a: error inesperado %', sqlerrm;
    end if;
  end;

  -- 3b. sort_order duplicado rechazado
  begin
    insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order, id)
    values (v_report, 'report_photos/r1/5.jpg', 'image/jpeg', 1000, 1,
            'aaaaaaaa-0000-4000-8000-0000000000bb'::uuid);
    raise exception 'FALLO 3b: sort_order duplicado aceptado';
  exception when unique_violation then
    raise notice 'OK 3b: sort_order duplicado rechazado';
  when others then
    if sqlerrm like '%más de 3 fotos%' then
      raise notice 'OK 3b (límite aplicado antes del unique): rechazado';
    else
      raise exception 'FALLO 3b: error inesperado %', sqlerrm;
    end if;
  end;

  -- 3c. FK de report (integridad referencial)
  begin
    insert into public.report_photos (report_id, storage_path, mime_type, size_bytes, sort_order)
    values ('aaaaaaaa-0000-4000-8000-0000000000ad'::uuid,
            'report_photos/x/1.jpg', 'image/jpeg', 1000, 1);
    raise exception 'FALLO 3c: FK de report_photos no aplicada';
  exception when foreign_key_violation then
    raise notice 'OK 3c: photo con reporte inexistente rechazada';
  end;
end $$;

-- =====================================================================
-- 4. RLS: escrituras de clientes bloqueadas (server-side only)
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 4a. authenticated puede leer reports
do $$
declare n int; begin
  select count(*) into n from public.reports;
  assert n >= 1, 'FALLO 4a: authenticated no puede leer reports';
  raise notice 'OK 4a: lectura de reports permitida';
end $$;

-- 4b. authenticated NO puede insertar reports directamente
do $$ begin
  insert into public.reports (created_by, municipality_id, sector_id, location, location_source)
  values (
    (select id from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    st_setsrid(st_makepoint(0, 0), 4326)::geography,
    'GPS');
  raise exception 'FALLO 4b: INSERT directo en reports permitido (eludiría la RPC)';
exception when insufficient_privilege then
  raise notice 'OK 4b: INSERT directo bloqueado por GRANT';
end $$;

-- 4c. authenticated NO puede insertar report_photos directamente
do $$ begin
  insert into public.report_photos (report_id, storage_path, mime_type, sort_order)
  values ((select id from public.reports limit 1), 'report_photos/x.jpg', 'image/jpeg', 1);
  raise exception 'FALLO 4c: INSERT directo en report_photos permitido';
exception when insufficient_privilege then
  raise notice 'OK 4c: INSERT directo en report_photos bloqueado';
end $$;

-- 4d. privacidad: la lectura pública no expone identidad personal.
-- created_by es un UUID opaco de app_users (no un dato de contacto); el
-- usuario no ve filas de app_users ajenas (ya probado en rls_test.sql).
do $$
declare r record; begin
  select * into r from public.reports limit 1;
  assert r.created_by is not null, 'FALLO 4d: created_by ausente';
  -- Verifica que la fila del usuario ajeno sigue invisible.
  set local role authenticated;
  set local request.jwt.claims =
    '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
  assert not exists (select 1 from public.app_users limit 1)
    or (select count(*) from public.app_users) <= 1,
    'FALLO 4d: app_users filtrada';
  raise notice 'OK 4d: identidad del creador no expuesta vía app_users';
end $$;

-- 4e. anon lee reports pero no puede escribir
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$
declare n int; begin
  select count(*) into n from public.reports;
  assert n >= 1, 'FALLO 4e-1: anon no lee reports';
  begin
    insert into public.reports (created_by, municipality_id, sector_id, location, location_source)
    values ('00000000-0000-4000-8000-0000000000ad'::uuid,
            '00000000-0000-4000-8000-0000000000f1',
            '00000000-0000-4000-8000-0000000000e1',
            st_setsrid(st_makepoint(0, 0), 4326)::geography, 'GPS');
    raise exception 'FALLO 4e-2: anon insertó reports';
  exception when insufficient_privilege then
    raise notice 'OK 4e: anon lee pero no escribe';
  end;
end $$;

-- =====================================================================
-- 5. RPC create_leak_report: autenticación y validaciones
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 5a. creación correcta (posición distinta de la prueba 1 para no
-- activar la detección de duplicados)
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.98, p_longitude => -63.86,
    p_location_source => 'GPS',
    p_description => 'Fuga en la esquina',
    p_photos => jsonb_build_array(
      jsonb_build_object('storage_path','report_photos/t/1.jpg',
                         'mime_type','image/jpeg','sort_order',1,
                         'size_bytes', 10000),
      jsonb_build_object('storage_path','report_photos/t/2.jpg',
                         'mime_type','image/jpeg','sort_order',2,
                         'size_bytes', 10000)
    )
  );
  assert resp->>'status_code' = 'CREATED', 'FALLO 5a: ' || resp::text;
  assert resp->>'report_id' is not null, 'FALLO 5a-2: sin report_id';
  raise notice 'OK 5a: creación correcta → %', resp->>'status_code';
end $$;

-- 5b. sin sesión no crea (el GRANT excluye a anon: permiso denegado)
do $$
begin
  set local role anon;
  set local request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
  perform public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.99, -63.87, 'GPS', null, '[]'::jsonb);
  raise exception 'FALLO 5b: anon pudo ejecutar create_leak_report';
exception when insufficient_privilege then
  raise notice 'OK 5b: anon no puede crear reportes (permiso denegado)';
end $$;

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 5c. municipio inválido
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa'::uuid,
    '00000000-0000-4000-8000-0000000000e1',
    10.99, -63.87, 'GPS', null, '[]'::jsonb);
  assert resp->>'status_code' <> 'CREATED', 'FALLO 5c: municipio inválido aceptado';
  raise notice 'OK 5c: municipio inválido rechazado (%)', resp->>'status_code';
end $$;

-- 5d. sector de otro municipio rechazado
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e3', -- pertenece a f3
    p_latitude => 10.99, p_longitude => -63.87,
    p_location_source => 'GPS', p_description => null,
    p_photos => '[]'::jsonb);
  assert resp->>'status_code' in ('INVALID_SECTOR', 'VALIDATION_ERROR'),
    'FALLO 5d: relación cruzada aceptada: ' || resp::text;
  raise notice 'OK 5d: municipio/sector cruzados rechazados';
end $$;

-- 5e. ubicación inválida
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    999.0, -63.87, 'GPS', null, '[]'::jsonb);
  assert resp->>'status_code' = 'INVALID_LOCATION',
    'FALLO 5e: latitud 999 aceptada';
  raise notice 'OK 5e: ubicación fuera de rango rechazada';
end $$;

-- 5f. sin fotos rechazado
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.99, -63.87, 'GPS', null, '[]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 5f: sin fotos aceptado';
  raise notice 'OK 5f: reporte sin fotos rechazado';
end $$;

-- 5g. exceso de fotos rechazado (4 fotos > máximo 3)
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.99, p_longitude => -63.87,
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"a/1.jpg","mime_type":"image/jpeg","sort_order":1},
      {"storage_path":"a/2.jpg","mime_type":"image/jpeg","sort_order":2},
      {"storage_path":"a/3.jpg","mime_type":"image/jpeg","sort_order":3},
      {"storage_path":"a/4.jpg","mime_type":"image/jpeg","sort_order":4}
    ]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 5g: 4 fotos aceptadas';
  raise notice 'OK 5g: exceso de fotos rechazado';
end $$;

-- =====================================================================
-- 6. Duplicados (50 m / 48 h, ACTIVE)
-- =====================================================================
do $$
declare resp jsonb; begin
  -- Usa la misma posición que el reporte creado en 5a.
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.99, p_longitude => -63.87,
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"d/1.jpg","mime_type":"image/jpeg","sort_order":1}
    ]'::jsonb);
  assert resp->>'status_code' = 'POSSIBLE_DUPLICATE',
    'FALLO 6a: duplicado a 0 m / 0 h no detectado: ' || resp::text;
  assert jsonb_array_length(resp->'candidates') >= 1,
    'FALLO 6a-2: sin candidatos';
  assert (resp->'candidates'->0->>'distance_meters') is not null,
    'FALLO 6a-3: sin distancia';
  raise notice 'OK 6a: duplicado ≤50 m detectado con distancia';
end $$;

-- 6b. >50 m no es duplicado (usar desplazamiento ~0.001° ≈ 111 m)
do $$
declare resp jsonb; begin
  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 10.9910, p_longitude => -63.87, -- ~111 m al norte
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"nb/1.jpg","mime_type":"image/jpeg","sort_order":1}
    ]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 6b: >50 m marcado como duplicado: ' || resp::text;
  raise notice 'OK 6b: a ~111 m se creó sin duplicado';
end $$;

-- 6c. >48 h no es duplicado (reporte viejo cerca)
do $$
declare resp jsonb; begin
  -- El reporte de la prueba 4 (0,0) se envejece a 72 h (rol admin:
  -- los clientes no pueden escribir, por eso no hay GRANT de UPDATE).
  set local role postgres;
  reset request.jwt.claims;
  update public.reports
  set created_at = now() - interval '72 hours'
   where status = 'ACTIVE'
     and extensions.st_distance(location,
         extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326)::extensions.geography) < 1;
  set local role authenticated;
  set local request.jwt.claims =
    '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f1',
    p_sector_id => '00000000-0000-4000-8000-0000000000e1',
    p_latitude => 0.0, p_longitude => 0.0, -- misma posición que reporte viejo
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"old/1.jpg","mime_type":"image/jpeg","sort_order":1}
    ]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 6c: >48 h marcado como duplicado: ' || resp::text;
  raise notice 'OK 6c: reporte de hace 72 h no bloquea';
end $$;

-- 6d. RESOLVED no es duplicado
do $$
declare resp jsonb; begin
  set local role postgres;
  reset request.jwt.claims;
  insert into public.reports (created_by, municipality_id, sector_id, location, location_source, status, resolved_at)
  values (
    (select id from public.app_users where auth_user_id = '22222222-2222-4222-8222-222222222222'),
    '00000000-0000-4000-8000-0000000000f3',
    '00000000-0000-4000-8000-0000000000e3',
    extensions.st_setsrid(extensions.st_makepoint(-63.85, 10.95), 4326)::extensions.geography,
    'GPS', 'RESOLVED', now());
  set local role authenticated;
  set local request.jwt.claims =
    '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

  resp := public.create_leak_report(
    p_municipality_id => '00000000-0000-4000-8000-0000000000f3',
    p_sector_id => '00000000-0000-4000-8000-0000000000e3',
    p_latitude => 10.95, p_longitude => -63.85, -- misma posición, RESOLVED
    p_location_source => 'GPS',
    p_photos => '[
      {"storage_path":"res/1.jpg","mime_type":"image/jpeg","sort_order":1}
    ]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 6d: RESOLVED marcado como duplicado: ' || resp::text;
  raise notice 'OK 6d: reporte RESOLVED no bloquea';
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

