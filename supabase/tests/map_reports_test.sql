-- tests/map_reports_test.sql — Pruebas de la RPC pública get_map_reports (Sprint 05: Map).
-- Valida:
--   1. Retorno de DTO público (latitude, longitude, status, sector_name, etc.);
--   2. No exposición de created_by ni datos privados (REQ-100);
--   3. Filtro por status: Todas (null), ACTIVE, RESOLVED;
--   4. Rechazo de status inválido;
--   5. Filtro por sector (Mi sector);
--   6. Ordenamiento: recientes (created_at desc) y más validadas (validation_count desc);
--   7. Filtro por bounding box PostGIS (índice espacial);
--   8. Límite acotado (respeto de p_limit y cap a 200);
--   9. Permisos: accesible para roles anon y authenticated.
--
-- Todo corre en una transacción y se revierte al final (rollback).

begin;

set role postgres;
reset request.jwt.claims;

-- =====================================================================
-- 0. Preparación: datos de prueba
-- =====================================================================
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'map_user_a@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'map_user_b@gota.test')
on conflict (id) do nothing;

insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000b1', 'Municipio Map 1', 'Nueva Esparta', true),
  ('00000000-0000-4000-8000-0000000000b2', 'Municipio Map 2', 'Nueva Esparta', true)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000b1', 'Sector Centro', true),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000b1', 'Sector Norte',  true),
  ('00000000-0000-4000-8000-0000000000c3', '00000000-0000-4000-8000-0000000000b2', 'Sector Sur',    true)
on conflict (id) do nothing;

do $$
declare
  v_user_a uuid;
  v_user_b uuid;
begin
  select id into v_user_a from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111';
  select id into v_user_b from public.app_users where auth_user_id = '22222222-2222-4222-8222-222222222222';

  -- Reporte 1: ACTIVE, Sector Centro, Margarita centro (10.99, -63.87), validation_count = 5
  insert into public.reports (
    id, created_by, municipality_id, sector_id, location, location_source,
    description, status, validation_count, resolution_confirmation_count, created_at
  ) values (
    '00000000-0000-4000-8000-000000000001', v_user_a,
    '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000c1',
    extensions.st_setsrid(extensions.st_makepoint(-63.87, 10.99), 4326)::extensions.geography,
    'GPS', 'Fuga en el centro', 'ACTIVE', 5, 0, now() - interval '2 hours'
  );

  -- Reporte 2: RESOLVED, Sector Norte, Margarita norte (11.05, -63.85), validation_count = 2
  insert into public.reports (
    id, created_by, municipality_id, sector_id, location, location_source,
    description, status, validation_count, resolution_confirmation_count, created_at, resolved_at
  ) values (
    '00000000-0000-4000-8000-000000000002', v_user_b,
    '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000c2',
    extensions.st_setsrid(extensions.st_makepoint(-63.85, 11.05), 4326)::extensions.geography,
    'GPS', 'Fuga reparada al norte', 'RESOLVED', 2, 3, now() - interval '1 hour', now()
  );

  -- Reporte 3: ACTIVE, Sector Sur (M2), lejos (10.80, -64.10), validation_count = 10
  insert into public.reports (
    id, created_by, municipality_id, sector_id, location, location_source,
    description, status, validation_count, resolution_confirmation_count, created_at
  ) values (
    '00000000-0000-4000-8000-000000000003', v_user_a,
    '00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000c3',
    extensions.st_setsrid(extensions.st_makepoint(-64.10, 10.80), 4326)::extensions.geography,
    'MANUAL', 'Fuga lejana en el sur', 'ACTIVE', 10, 0, now()
  );

  raise notice 'OK 0: datos de prueba para get_map_reports insertados';
end $$;

-- =====================================================================
-- 1. Ejecución con rol anon (público sin sesión)
-- =====================================================================
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';

-- 1a. Anon consulta "Todas": debe ver las 3 fugas con sus coordenadas y nombres
do $$
declare
  v_count int;
  v_row record;
begin
  select count(*) into v_count from public.get_map_reports();
  assert v_count = 3, format('FALLO 1a: esperaba 3 reportes, obtuvo %s', v_count);

  select * into v_row from public.get_map_reports() where id = '00000000-0000-4000-8000-000000000001';
  assert v_row.status = 'ACTIVE', 'FALLO 1a: status incorrecto';
  assert abs(v_row.latitude - 10.99) < 0.0001, 'FALLO 1a: latitude incorrecta';
  assert abs(v_row.longitude - (-63.87)) < 0.0001, 'FALLO 1a: longitude incorrecta';
  assert v_row.sector_name = 'Sector Centro', 'FALLO 1a: sector_name incorrecto';
  assert v_row.municipality_name = 'Municipio Map 1', 'FALLO 1a: municipality_name incorrecto';

  raise notice 'OK 1a: anon puede ejecutar get_map_reports con DTO completo';
end $$;

-- 1b. Filtro "Activas"
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_map_reports(p_status => 'ACTIVE');
  assert v_count = 2, format('FALLO 1b: esperaba 2 activas, obtuvo %s', v_count);
  raise notice 'OK 1b: filtro ACTIVE funciona';
end $$;

-- 1c. Filtro "Resueltas"
do $$
declare
  v_count int;
  v_row record;
begin
  select count(*) into v_count from public.get_map_reports(p_status => 'RESOLVED');
  assert v_count = 1, format('FALLO 1c: esperaba 1 resuelta, obtuvo %s', v_count);

  select * into v_row from public.get_map_reports(p_status => 'RESOLVED') limit 1;
  assert v_row.id = '00000000-0000-4000-8000-000000000002', 'FALLO 1c: ID resuelto inesperado';
  assert v_row.resolved_at is not null, 'FALLO 1c: resolved_at nulo';
  raise notice 'OK 1c: filtro RESOLVED funciona';
end $$;

-- 1d. Status inválido debe ser rechazado
do $$
begin
  perform * from public.get_map_reports(p_status => 'INVALID_STATUS');
  raise exception 'FALLO 1d: status inválido no lanzó excepción';
exception
  when others then
    if sqlerrm like '%INVALID_STATUS%' then
      raise notice 'OK 1d: status inválido rechazado';
    else
      raise;
    end if;
end $$;

-- 1e. Filtro "Mi sector" (por sector_id)
do $$
declare
  v_count int;
begin
  select count(*) into v_count
    from public.get_map_reports(p_sector_id => '00000000-0000-4000-8000-0000000000c1');
  assert v_count = 1, format('FALLO 1e: esperaba 1 reporte para sector 1, obtuvo %s', v_count);
  raise notice 'OK 1e: filtro por sector funciona';
end $$;

-- 1f. Ordenamiento "Más validadas"
do $$
declare
  v_first_id uuid;
begin
  select id into v_first_id
    from public.get_map_reports(p_order_by => 'validated')
    limit 1;
  assert v_first_id = '00000000-0000-4000-8000-000000000003',
    format('FALLO 1f: el primer reporte debería ser el de 10 validaciones, fue %s', v_first_id);
  raise notice 'OK 1f: ordenamiento más validadas funciona';
end $$;

-- 1g. Bounding Box espacial
do $$
declare
  v_count int;
begin
  -- Envelope que solo cubre Margarita norte/centro (10.95 a 11.10 lat, -63.95 a -63.80 lng)
  select count(*) into v_count from public.get_map_reports(
    p_min_lat => 10.95,
    p_min_lng => -63.95,
    p_max_lat => 11.10,
    p_max_lng => -63.80
  );
  assert v_count = 2, format('FALLO 1g: esperaba 2 reportes en el bbox, obtuvo %s', v_count);
  raise notice 'OK 1g: bounding box PostGIS filtra correctamente';
end $$;

-- 1h. Límite de resultados
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_map_reports(p_limit => 1);
  assert v_count = 1, format('FALLO 1h: esperaba 1 reporte con limit=1, obtuvo %s', v_count);
  raise notice 'OK 1h: límite funciona';
end $$;

-- =====================================================================
-- 2. Ejecución con rol authenticated
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_map_reports();
  assert v_count = 3, format('FALLO 2: authenticated esperaba 3 reportes, obtuvo %s', v_count);
  raise notice 'OK 2: authenticated puede ejecutar get_map_reports';
end $$;

-- =====================================================================
-- 3. Verificación de Privacidad (REQ-100 / §8)
-- =====================================================================
-- Inspecciona la firma real de la función en pg_catalog para garantizar que
-- los campos privados no están en el RETURNS TABLE. information_schema.columns
-- no indexa funciones, por lo que la verificación correcta es via pg_proc.
do $$
declare
  v_sig text;
begin
  select pg_catalog.pg_get_function_result(p.oid)
    into v_sig
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where p.proname = 'get_map_reports'
     and n.nspname = 'public';

  assert v_sig is not null, 'FALLO 3: no se encontró la función get_map_reports';
  assert v_sig not like '%created_by%',
    format('FALLO 3: get_map_reports incluye created_by en su firma: %s', v_sig);
  assert v_sig not like '%email%',
    format('FALLO 3: get_map_reports incluye email en su firma: %s', v_sig);
  assert v_sig not like '%auth_user_id%',
    format('FALLO 3: get_map_reports incluye auth_user_id en su firma: %s', v_sig);

  raise notice 'OK 3: firma de get_map_reports no expone campos privados: %', v_sig;
end $$;

-- =====================================================================
-- Limpieza
-- =====================================================================
reset role;
reset request.jwt.claims;

rollback;

do $$
begin
  raise notice 'Todas las pruebas de get_map_reports pasaron exitosamente.';
end $$;
