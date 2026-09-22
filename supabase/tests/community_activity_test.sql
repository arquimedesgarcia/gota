-- tests/community_activity_test.sql — Pruebas de la tarjeta "Actividad
-- reciente" del Home (RPC `public.get_latest_community_activity`, migración
-- 20260922000029).
--
-- Ejecutar contra una BD Supabase con las migraciones aplicadas:
--   docker exec -i supabase_db_gota psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 < supabase/tests/community_activity_test.sql
--
-- Todo corre en una transacción que se revierte al terminar: no deja datos.
-- La RPC es GLOBAL (sin filtro de sector) y devuelve 0 o 1 fila, así que la
-- prueba parte de un universo de `reports` vacío (truncate revertido en el
-- rollback) para que las aserciones sobre "el evento más reciente" sean
-- deterministas.

begin;
set role postgres;
reset request.jwt.claims;

-- Universo controlado: la RPC mira TODOS los reports; se aísla vaciándolos.
truncate table public.reports cascade;

-- =====================================================================
-- 0. Base sin fallas → 0 filas
-- =====================================================================
do $$
declare n int; begin
  select count(*) into n from public.get_latest_community_activity();
  assert n = 0, 'FALLO 0: base vacía debería devolver 0 filas, dio ' || n;
  raise notice 'OK 0: base vacía → 0 filas';
end $$;

-- =====================================================================
-- Preparación de identidades y catálogo
-- =====================================================================
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'creator@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'val1@gota.test'),
  ('33333333-3333-4333-8333-333333333333', 'val2@gota.test'),
  ('44444444-4444-4444-8444-444444444444', 'val3@gota.test')
on conflict (id) do nothing;

insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Actividad', 'Nueva Esparta', true)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000f1', 'Sector Actividad', true)
on conflict (id) do nothing;

-- =====================================================================
-- 1. Una falla reportada → REPORTED con at = created_at
-- =====================================================================
do $$
declare v_creator uuid; begin
  select id into v_creator from public.app_users
   where auth_user_id = '11111111-1111-4111-8111-111111111111';

  insert into public.reports (id, created_by, municipality_id, sector_id,
                              location, location_source, description,
                              created_at)
  values ('00000000-0000-4000-8000-00000000a001', v_creator,
          '00000000-0000-4000-8000-0000000000f1',
          '00000000-0000-4000-8000-0000000000e1',
          extensions.st_setsrid(extensions.st_makepoint(-63.87, 10.99), 4326)::extensions.geography,
          'GPS', 'Fuga de pruebas de actividad',
          timestamptz '2026-09-01 10:00:00+00');
  raise notice 'OK 1-setup: R1 reportada';
end $$;

do $$
declare r record; begin
  select * into r from public.get_latest_community_activity();
  assert r.activity_type = 'REPORTED',
    'FALLO 1: se esperaba REPORTED, dio ' || coalesce(r.activity_type, '<null>');
  assert r.report_id = '00000000-0000-4000-8000-00000000a001',
    'FALLO 1-2: report_id inesperado';
  assert r.at = timestamptz '2026-09-01 10:00:00+00',
    'FALLO 1-3: at debe ser created_at, dio ' || r.at;
  assert r.status = 'ACTIVE', 'FALLO 1-4: status actual debe ser ACTIVE';
  raise notice 'OK 1: falla reportada → REPORTED, at = created_at';
end $$;

-- =====================================================================
-- 2. 1ª y 2ª validación con umbral 3 → sigue REPORTED
--    (prueba explícita: la validación individual NO genera evento)
-- =====================================================================
do $$
declare v1 uuid; v2 uuid; begin
  select id into v1 from public.app_users
   where auth_user_id = '22222222-2222-4222-8222-222222222222';
  select id into v2 from public.app_users
   where auth_user_id = '33333333-3333-4333-8333-333333333333';

  insert into public.report_validations (report_id, user_id, created_at) values
    ('00000000-0000-4000-8000-00000000a001', v1, timestamptz '2026-09-02 08:00:00+00'),
    ('00000000-0000-4000-8000-00000000a001', v2, timestamptz '2026-09-02 09:00:00+00');
  update public.reports set validation_count = 2
   where id = '00000000-0000-4000-8000-00000000a001';
  raise notice 'OK 2-setup: 2 validaciones (umbral 3 sin cruzar)';
end $$;

do $$
declare r record; begin
  select * into r from public.get_latest_community_activity();
  assert r.activity_type = 'REPORTED',
    'FALLO 2: con 2/3 validaciones NO debe haber evento VALIDATED, dio '
    || coalesce(r.activity_type, '<null>');
  assert r.at = timestamptz '2026-09-01 10:00:00+00',
    'FALLO 2-2: at debe seguir siendo el created_at del reporte';
  raise notice 'OK 2: 1ª y 2ª validación no producen evento (sigue REPORTED)';
end $$;

-- =====================================================================
-- 3. 3ª validación (cruza el umbral) → VALIDATED con at = created_at de esa
--    3ª validación exactamente
-- =====================================================================
do $$
declare v3 uuid; begin
  select id into v3 from public.app_users
   where auth_user_id = '44444444-4444-4444-8444-444444444444';

  insert into public.report_validations (report_id, user_id, created_at) values
    ('00000000-0000-4000-8000-00000000a001', v3, timestamptz '2026-09-02 10:00:00+00');
  update public.reports set validation_count = 3
   where id = '00000000-0000-4000-8000-00000000a001';
  raise notice 'OK 3-setup: 3ª validación (cruza el umbral)';
end $$;

do $$
declare r record; begin
  select * into r from public.get_latest_community_activity();
  assert r.activity_type = 'VALIDATED',
    'FALLO 3: la 3ª validación debe producir VALIDATED, dio '
    || coalesce(r.activity_type, '<null>');
  assert r.at = timestamptz '2026-09-02 10:00:00+00',
    'FALLO 3-2: at debe ser EXACTAMENTE el created_at de la 3ª validación, dio '
    || r.at;
  assert r.report_id = '00000000-0000-4000-8000-00000000a001',
    'FALLO 3-3: report_id inesperado';
  raise notice 'OK 3: 3ª validación → VALIDATED, at = created_at de la N-ésima';
end $$;

-- =====================================================================
-- 4. Resolución posterior → RESOLVED con at = resolved_at
-- =====================================================================
do $$ begin
  update public.reports
     set status = 'RESOLVED', resolved_at = timestamptz '2026-09-03 12:00:00+00',
         resolution_confirmation_count = 3
   where id = '00000000-0000-4000-8000-00000000a001';
  raise notice 'OK 4-setup: R1 resuelta';
end $$;

do $$
declare r record; begin
  select * into r from public.get_latest_community_activity();
  assert r.activity_type = 'RESOLVED',
    'FALLO 4: se esperaba RESOLVED, dio ' || coalesce(r.activity_type, '<null>');
  assert r.at = timestamptz '2026-09-03 12:00:00+00',
    'FALLO 4-2: at debe ser resolved_at, dio ' || r.at;
  assert r.status = 'RESOLVED', 'FALLO 4-3: status actual debe ser RESOLVED';
  raise notice 'OK 4: resolución → RESOLVED, at = resolved_at';
end $$;

-- =====================================================================
-- 5. Umbral configurable: con threshold = 2 el VALIDATED se adelanta a la 2ª
--    validación (demuestra que el umbral sale de system_config).
-- =====================================================================
-- Escenario aislado: R2 solo con validaciones (sin resolver) y creada antigua
-- para que su propio REPORTED no gane. Se limpia el universo primero.
do $$
declare v_creator uuid; v1 uuid; v2 uuid; v3 uuid; begin
  delete from public.reports;  -- cascada a validaciones/confirmaciones

  select id into v_creator from public.app_users
   where auth_user_id = '11111111-1111-4111-8111-111111111111';
  select id into v1 from public.app_users
   where auth_user_id = '22222222-2222-4222-8222-222222222222';
  select id into v2 from public.app_users
   where auth_user_id = '33333333-3333-4333-8333-333333333333';
  select id into v3 from public.app_users
   where auth_user_id = '44444444-4444-4444-8444-444444444444';

  insert into public.reports (id, created_by, municipality_id, sector_id,
                              location, location_source, validation_count,
                              created_at)
  values ('00000000-0000-4000-8000-00000000a002', v_creator,
          '00000000-0000-4000-8000-0000000000f1',
          '00000000-0000-4000-8000-0000000000e1',
          extensions.st_setsrid(extensions.st_makepoint(-63.88, 10.98), 4326)::extensions.geography,
          'GPS', 3, timestamptz '2026-01-01 00:00:00+00');

  insert into public.report_validations (report_id, user_id, created_at) values
    ('00000000-0000-4000-8000-00000000a002', v1, timestamptz '2026-05-01 00:00:00+00'),
    ('00000000-0000-4000-8000-00000000a002', v2, timestamptz '2026-05-02 00:00:00+00'),
    ('00000000-0000-4000-8000-00000000a002', v3, timestamptz '2026-05-03 00:00:00+00');
  raise notice 'OK 5-setup: R2 con 3 validaciones';
end $$;

-- Con umbral 3 (por defecto): VALIDATED en la 3ª validación.
do $$
declare r record; begin
  select * into r from public.get_latest_community_activity();
  assert r.activity_type = 'VALIDATED' and r.at = timestamptz '2026-05-03 00:00:00+00',
    'FALLO 5a: con umbral 3 el VALIDATED debe caer en la 3ª validación, dio '
    || coalesce(r.activity_type, '<null>') || ' @ ' || coalesce(r.at::text, '<null>');
  raise notice 'OK 5a: umbral 3 → VALIDATED en la 3ª validación';
end $$;

-- Cambiar el umbral a 2 dentro del test: el VALIDATED se adelanta a la 2ª.
do $$
declare r record; begin
  update public.system_config
     set value = jsonb_set(value, '{threshold}', '2'::jsonb)
   where key = 'validation';

  select * into r from public.get_latest_community_activity();
  assert r.activity_type = 'VALIDATED' and r.at = timestamptz '2026-05-02 00:00:00+00',
    'FALLO 5b: con umbral 2 el VALIDATED debe adelantarse a la 2ª validación, dio '
    || coalesce(r.activity_type, '<null>') || ' @ ' || coalesce(r.at::text, '<null>');

  -- Restaurar el umbral del piloto.
  update public.system_config
     set value = jsonb_set(value, '{threshold}', '3'::jsonb)
   where key = 'validation';
  raise notice 'OK 5b: umbral 2 → el VALIDATED se adelanta a la 2ª validación';
end $$;

-- =====================================================================
-- 6. Determinismo: dos fallas con el mismo `at` devuelven siempre la misma
--    fila (desempate estable por report_id).
-- =====================================================================
do $$
declare v_creator uuid; begin
  select id into v_creator from public.app_users
   where auth_user_id = '11111111-1111-4111-8111-111111111111';

  -- Dos REPORTED con idéntico created_at, y más recientes que el VALIDATED
  -- de R2, así que empatan como el evento más reciente.
  insert into public.reports (id, created_by, municipality_id, sector_id,
                              location, location_source, created_at) values
    ('00000000-0000-4000-8000-00000000a003', v_creator,
     '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
     extensions.st_setsrid(extensions.st_makepoint(-63.80, 10.90), 4326)::extensions.geography,
     'GPS', timestamptz '2026-06-01 00:00:00+00'),
    ('00000000-0000-4000-8000-00000000a004', v_creator,
     '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e1',
     extensions.st_setsrid(extensions.st_makepoint(-63.81, 10.91), 4326)::extensions.geography,
     'GPS', timestamptz '2026-06-01 00:00:00+00');
  raise notice 'OK 6-setup: R3 y R4 con el mismo created_at';
end $$;

do $$
declare id1 uuid; id2 uuid; begin
  select report_id into id1 from public.get_latest_community_activity();
  select report_id into id2 from public.get_latest_community_activity();
  assert id1 = id2,
    'FALLO 6: llamadas repetidas devuelven filas distintas (' || id1 || ' vs ' || id2 || ')';
  assert id1 = '00000000-0000-4000-8000-00000000a003',
    'FALLO 6-2: el desempate debe ser el report_id menor, dio ' || id1;
  raise notice 'OK 6: empate de at determinista (misma fila en cada llamada)';
end $$;

-- =====================================================================
-- 7. El DTO no expone ninguna columna de identidad (REQ-100).
-- =====================================================================
do $$
declare j jsonb; begin
  select row_to_json(t)::jsonb into j
    from public.get_latest_community_activity() t;
  assert j is not null, 'FALLO 7: no hay fila para inspeccionar el DTO';
  assert not (j ? 'created_by'), 'FALLO 7-2: el DTO expone created_by';
  assert not (j ? 'user_id'),    'FALLO 7-3: el DTO expone user_id';
  assert not (j ? 'email'),      'FALLO 7-4: el DTO expone email';
  assert not (j ? 'phone'),      'FALLO 7-5: el DTO expone phone';
  assert not (j ? 'storage_path'), 'FALLO 7-6: el DTO expone storage_path';
  -- Y sí trae lo que la fila del listado necesita.
  assert (j ? 'sector_name') and (j ? 'municipality_name'),
    'FALLO 7-7: faltan columnas de lugar en el DTO';
  raise notice 'OK 7: el DTO no expone ninguna identidad';
end $$;

-- =====================================================================
-- 8. Permisos: anon y authenticated ejecutan la RPC; no pueden usar
--    validation_threshold() ni leer report_validations.
-- =====================================================================
-- 8a. anon ejecuta la RPC (lectura pública, igual que get_map_reports).
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$
declare n int; begin
  select count(*) into n from public.get_latest_community_activity();
  raise notice 'OK 8a: anon ejecuta la RPC (% fila/s)', n;
exception when insufficient_privilege then
  raise exception 'FALLO 8a: anon no pudo ejecutar la RPC';
end $$;

-- 8b. anon NO puede ejecutar la función interna validation_threshold().
do $$ begin
  perform public.validation_threshold();
  raise exception 'FALLO 8b: anon ejecutó validation_threshold()';
exception when insufficient_privilege then
  raise notice 'OK 8b: anon no puede ejecutar validation_threshold()';
end $$;

-- 8c. authenticated ejecuta la RPC.
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
do $$
declare n int; begin
  select count(*) into n from public.get_latest_community_activity();
  raise notice 'OK 8c: authenticated ejecuta la RPC (% fila/s)', n;
exception when insufficient_privilege then
  raise exception 'FALLO 8c: authenticated no pudo ejecutar la RPC';
end $$;

-- 8d. authenticated NO puede ejecutar validation_threshold() (función interna).
do $$ begin
  perform public.validation_threshold();
  raise exception 'FALLO 8d: authenticated ejecutó validation_threshold()';
exception when insufficient_privilege then
  raise notice 'OK 8d: authenticated no puede ejecutar validation_threshold()';
end $$;

-- 8e. authenticated NO puede leer report_validations (la RPC es la única vía).
do $$ begin
  perform count(*) from public.report_validations;
  raise exception 'FALLO 8e: authenticated leyó report_validations';
exception when insufficient_privilege then
  raise notice 'OK 8e: report_validations no es legible por el cliente';
end $$;

-- =====================================================================
-- Limpieza: la transacción completa se revierte.
-- =====================================================================
reset role;
reset request.jwt.claims;
rollback;
do $$ begin
  raise notice 'Todas las pruebas de get_latest_community_activity pasaron.';
end $$;
