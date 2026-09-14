-- tests/rate_limiting_test.sql — Pruebas de regresión de Sprint 07:
-- rate limiting server-side de las 5 operaciones críticas
-- (create_leak_report, validate_leak, confirm_leak_resolution,
-- register_water_event, validate_water_event), de la tabla
-- public.rate_limit_tracking, de los helpers check_rate_limit /
-- check_rate_limit_inline (revocados, DEF-01) y de get_rate_limit.
--
-- Ejecutar contra una BD Supabase con las migraciones aplicadas, como
-- usuario privilegiado (postgres):
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/tests/rate_limiting_test.sql
--
-- Todo corre en una transacción que se revierte al terminar: el script no
-- deja datos en la base. Las aserciones usan `assert` (fallo → ERROR y
-- salida no cero de psql con ON_ERROR_STOP, igual que las otras suites) y
-- un contador de secciones superadas imprime el resumen final.
--
-- Concurrencia real: no puede simularse dentro de una única sesión SQL;
-- vive en `supabase/tests/rate_limit_concurrency_e2e.sh`.

begin;
set role postgres;
reset request.jwt.claims;

-- Contador de secciones superadas + memoria temporal entre bloques.
create temp table rl_stats (passed int not null default 0);
insert into rl_stats values (0);
create temp table rl_ids   (label text primary key, id uuid);
create temp table rl_cfg   (value jsonb);
-- Se leen/escriben con role authenticated dentro de los bloques de prueba.
grant all on rl_stats, rl_ids, rl_cfg to authenticated;

-- =====================================================================
-- Preparación: usuarios, municipio, sectores y fotos en Storage
-- =====================================================================
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'rl_a@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'rl_b@gota.test'),
  ('33333333-3333-4333-8333-333333333333', 'rl_c@gota.test'),
  ('44444444-4444-4444-8444-444444444444', 'rl_d@gota.test'),
  ('55555555-5555-4555-8555-555555555555', 'rl_e@gota.test'),
  ('66666666-6666-4666-8666-666666666666', 'rl_f@gota.test'),
  ('77777777-7777-4777-8777-777777777777', 'rl_g@gota.test'),
  ('88888888-8888-4888-8888-888888888888', 'rl_h@gota.test')
on conflict (id) do nothing;

insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Rate Limit', 'Nueva Esparta', true)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000f1', 'Sector Rate Limit 1', true),
  ('00000000-0000-4000-8000-0000000000e2',
   '00000000-0000-4000-8000-0000000000f1', 'Sector Rate Limit 2', true)
on conflict (id) do nothing;

-- Binarios simulados en Storage (mismo patrón que create_leak_report_test).
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

-- Fotos del usuario A (creaciones y rechazos de create_leak_report).
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/rl1/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/rl2/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/rl3/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/rl4/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/rl5/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/11111111-1111-4111-8111-111111111111/rl6/p1.jpg',
  '11111111-1111-4111-8111-111111111111', 'image/jpeg', 10240);
-- Fotos de B (creación aislada), G (config = 2) y H (fallback sin config).
select pg_temp.seed_photo(
  'report_photos/22222222-2222-4222-8222-222222222222/rl1/p1.jpg',
  '22222222-2222-4222-8222-222222222222', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/22222222-2222-4222-8222-222222222222/rl2/p1.jpg',
  '22222222-2222-4222-8222-222222222222', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/77777777-7777-4777-8777-777777777777/rl1/p1.jpg',
  '77777777-7777-4777-8777-777777777777', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/77777777-7777-4777-8777-777777777777/rl2/p1.jpg',
  '77777777-7777-4777-8777-777777777777', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/77777777-7777-4777-8777-777777777777/rl3/p1.jpg',
  '77777777-7777-4777-8777-777777777777', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/88888888-8888-4888-8888-888888888888/rl1/p1.jpg',
  '88888888-8888-4888-8888-888888888888', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/88888888-8888-4888-8888-888888888888/rl2/p1.jpg',
  '88888888-8888-4888-8888-888888888888', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/88888888-8888-4888-8888-888888888888/rl3/p1.jpg',
  '88888888-8888-4888-8888-888888888888', 'image/jpeg', 10240);
select pg_temp.seed_photo(
  'report_photos/88888888-8888-4888-8888-888888888888/rl4/p1.jpg',
  '88888888-8888-4888-8888-888888888888', 'image/jpeg', 10240);

-- Reportes base (se insertan como administrador de BD; la creación por
-- cliente ya está cubierta por create_leak_report_test.sql):
--  * RB (…0b1): reporte ACTIVE de B en el Sector 2, a ~11 km de cualquier
--    otro punto usado aquí → blanco de validaciones/confirmaciones.
--  * RD (…0d1): reporte ACTIVE del usuario A, blanco de las confirmaciones
--    de D y del caso "el creador no valida su propio reporte".
insert into public.reports
  (id, created_by, municipality_id, sector_id, location, location_source, description)
select '00000000-0000-4000-8000-0000000000b1', u.id,
       '00000000-0000-4000-8000-0000000000f1',
       '00000000-0000-4000-8000-0000000000e2',
       extensions.st_setsrid(extensions.st_makepoint(-64.000, 11.000), 4326)::extensions.geography,
       'GPS', 'Reporte base para pruebas de rate limiting'
  from public.app_users u
 where u.auth_user_id = '22222222-2222-4222-8222-222222222222'
on conflict (id) do nothing;

insert into public.reports
  (id, created_by, municipality_id, sector_id, location, location_source)
select '00000000-0000-4000-8000-0000000000d1', u.id,
       '00000000-0000-4000-8000-0000000000f1',
       '00000000-0000-4000-8000-0000000000e1',
       extensions.st_setsrid(extensions.st_makepoint(-64.000, 10.070), 4326)::extensions.geography,
       'GPS'
  from public.app_users u
 where u.auth_user_id = '11111111-1111-4111-8111-111111111111'
on conflict (id) do nothing;

-- =====================================================================
-- 1. Límite exacto de create_leak_report (3/hora): 3 CREATED, la 4ª
--    RATE_LIMIT_EXCEEDED con reset_at = próxima hora, sin efectos
--    colaterales y con el contador > límite (el rechazo consume).
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

do $$
declare
  resp   jsonb;
  v_r0 int; v_p0 int; v_a0 int;
  v_r1 int; v_p1 int; v_a1 int;
  v_count int;
begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.000, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/rl1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 1a: llamada 1 no CREATED: ' || resp::text;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.010, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/rl2/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 1b: llamada 2 no CREATED: ' || resp::text;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.020, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/rl3/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 1c: llamada 3 no CREATED: ' || resp::text;

  -- Conteos previos al intento rechazado (server-side): no debe dejar nada.
  set local role postgres;
  select count(*) into v_r0 from public.reports;
  select count(*) into v_p0 from public.report_photos;
  select count(*) into v_a0 from public.audit_events;
  set local role authenticated;

  -- Llamada 4: límite exacto (3) ya consumido.
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.030, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/rl4/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 1d: la llamada 4 no fue rechazada: ' || resp::text;
  assert resp->>'reset_at' is not null, 'FALLO 1d-2: sin reset_at';
  assert (resp->>'reset_at')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    'FALLO 1d-3: reset_at no es window_start + 1h: ' || (resp->>'reset_at');

  -- Sin efectos colaterales del rechazo (reports, report_photos, audit_events).
  set local role postgres;
  select count(*) into v_r1 from public.reports;
  select count(*) into v_p1 from public.report_photos;
  select count(*) into v_a1 from public.audit_events;
  assert v_r1 = v_r0, 'FALLO 1e: el rechazo creó un reporte';
  assert v_p1 = v_p0, 'FALLO 1e-2: el rechazo creó una foto';
  assert v_a1 = v_a0, 'FALLO 1e-3: el rechazo creó auditoría';

  -- El intento rechazado igual incrementó el contador (semántica actual).
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111')
     and operation_type = 'create_leak_report'
     and window_start = date_trunc('hour', now());
  assert v_count = 4, 'FALLO 1f: contador esperado 4 (> límite 3), obtenido ' || v_count;
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 1: create_leak_report: 3 CREATED, 4ª RATE_LIMIT_EXCEEDED (reset_at ok, sin efectos, contador=4)';
end $$;

-- =====================================================================
-- 2. Aislamiento por usuario + otro intento en la misma ventana.
--    2a. A (agotado) sigue rechazado en la misma ventana.
--    2b. B, en un punto sin duplicados cercanos, sí puede crear.
-- =====================================================================
do $$
declare resp jsonb;
begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.030, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/rl5/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 2a: otro intento en la misma ventana debía rechazarse: ' || resp::text;
  raise notice 'OK 2a: otro intento en la misma ventana sigue rechazado';
end $$;

set request.jwt.claims =
  '{"role": "authenticated", "sub": "22222222-2222-4222-8222-222222222222", "aud": "authenticated"}';
do $$
declare resp jsonb;
begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e2',
    11.010, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/22222222-2222-4222-8222-222222222222/rl1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 2b: el agotamiento de A no debe afectar a B: ' || resp::text;
  update rl_stats set passed = passed + 1;
  raise notice 'OK 2b: A agotado no limita a B (aislamiento por usuario)';
end $$;

-- =====================================================================
-- 3. Orden del chequeo: descripción > 500 → VALIDATION_ERROR ANTES del
--    rate check, sin consumir presupuesto.
-- =====================================================================
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare
  resp    jsonb;
  v_count int;
begin
  set local role postgres;
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111')
     and operation_type = 'create_leak_report'
     and window_start = date_trunc('hour', now());
  assert v_count = 5, 'FALLO 3-pre: contador esperado 5, obtenido ' || v_count;
  set local role authenticated;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.030, -64.000, 'GPS', repeat('x', 501), '[]'::jsonb);
  assert resp->>'status_code' = 'VALIDATION_ERROR',
    'FALLO 3: descripción de 501 caracteres no rechazada: ' || resp::text;
  assert resp->>'message' = 'La descripción no puede superar los 500 caracteres.',
    'FALLO 3-2: mensaje inesperado: ' || (resp->>'message');

  set local role postgres;
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111')
     and operation_type = 'create_leak_report'
     and window_start = date_trunc('hour', now());
  assert v_count = 5, 'FALLO 3-3: la validación de descripción consumió presupuesto';
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 3: descripción >500 → VALIDATION_ERROR antes del rate check (sin consumo)';
end $$;

-- =====================================================================
-- 4. validate_leak sobre el propio reporte → FORBIDDEN y SIN consumir
--    presupuesto (retorno temprano previo al rate check).
-- =====================================================================
do $$
declare
  resp  jsonb;
  v_rows int;
begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000d1'); -- RD es de A
  assert resp->>'status_code' = 'FORBIDDEN',
    'FALLO 4: el creador pudo validar su propio reporte: ' || resp::text;
  assert resp->>'message' like '%propio reporte%',
    'FALLO 4-2: mensaje inesperado: ' || (resp->>'message');

  set local role postgres;
  select count(*) into v_rows from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111')
     and operation_type = 'validate_leak'
     and window_start = date_trunc('hour', now());
  assert v_rows = 0, 'FALLO 4-3: el FORBIDDEN consumió rate budget (' || v_rows || ' filas)';
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 4: validar el propio reporte → FORBIDDEN sin consumir budget';
end $$;

-- =====================================================================
-- 5. Aislamiento por operación: agotar create_leak_report NO bloquea
--    validate_leak para el mismo usuario.
-- =====================================================================
do $$
declare resp jsonb;
begin
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000b1'); -- RB es de B
  assert resp->>'status_code' = 'VALIDATED',
    'FALLO 5: validate_leak bloqueado tras agotar create_leak_report: ' || resp::text;
  assert (resp->>'validation_count')::int = 1, 'FALLO 5-2: contador inesperado';
  update rl_stats set passed = passed + 1;
  raise notice 'OK 5: agotar create_leak_report no bloquea validate_leak (mismo usuario)';
end $$;

-- =====================================================================
-- 6. Ventana nueva: expirada la ventana (window_start envejecido como
--    postgres), el mismo usuario vuelve a poder crear.
-- =====================================================================
set role postgres;
update public.rate_limit_tracking
   set window_start = now() - interval '2 hours'
 where user_id = (select id from public.app_users
                   where auth_user_id = '11111111-1111-4111-8111-111111111111')
   and operation_type = 'create_leak_report'
   and window_start = date_trunc('hour', now());

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$
declare
  resp    jsonb;
  v_count int;
begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    10.040, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/11111111-1111-4111-8111-111111111111/rl6/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED',
    'FALLO 6: con la ventana expirada debía permitirse crear: ' || resp::text;

  set local role postgres;
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111')
     and operation_type = 'create_leak_report'
     and window_start = date_trunc('hour', now());
  assert v_count = 1, 'FALLO 6-2: bucket nuevo esperado con count=1, obtenido ' || v_count;
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 6: ventana expirada → nuevo bucket (count=1) y creación permitida';
end $$;

-- =====================================================================
-- 7. Límite exacto de validate_leak (20/hora) con UNA sola validación:
--    VALIDATED + DUPLICATE_ACTION ×19 consumen presupuesto; la 21ª
--    RATE_LIMIT_EXCEEDED sin fila nueva y con contador > límite.
-- =====================================================================
set request.jwt.claims =
  '{"role": "authenticated", "sub": "33333333-3333-4333-8333-333333333333", "aud": "authenticated"}';
do $$
declare
  resp    jsonb;
  i       int;
  v_c1    int;
  v_c2    int;
  v_rows  int;
begin
  -- 1ª validación: VALIDATED (A ya validó RB en §5 → contador pasa a 2).
  resp := public.validate_leak('00000000-0000-4000-8000-0000000000b1');
  assert resp->>'status_code' = 'VALIDATED', 'FALLO 7a: ' || resp::text;
  assert (resp->>'validation_count')::int = 2, 'FALLO 7a-2: contador esperado 2';

  -- DUPLICATE_ACTION también consume presupuesto (contador +1).
  set local role postgres;
  select count into v_c1 from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '33333333-3333-4333-8333-333333333333')
     and operation_type = 'validate_leak'
     and window_start = date_trunc('hour', now());
  set local role authenticated;

  resp := public.validate_leak('00000000-0000-4000-8000-0000000000b1');
  assert resp->>'status_code' = 'DUPLICATE_ACTION', 'FALLO 7b: ' || resp::text;
  assert resp->>'already_validated' = 'true', 'FALLO 7b-2: sin already_validated';

  set local role postgres;
  select count into v_c2 from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '33333333-3333-4333-8333-333333333333')
     and operation_type = 'validate_leak'
     and window_start = date_trunc('hour', now());
  assert v_c2 = v_c1 + 1,
    format('FALLO 7b-3: DUPLICATE_ACTION no consumió budget (%s → %s)', v_c1, v_c2);
  set local role authenticated;

  -- 18 duplicados más: total 20 (límite exacto).
  for i in 1..18 loop
    resp := public.validate_leak('00000000-0000-4000-8000-0000000000b1');
    assert resp->>'status_code' = 'DUPLICATE_ACTION',
      format('FALLO 7c (iter %s): %s', i, resp::text);
  end loop;

  -- 21ª llamada: rechazada, sin fila nueva, contador > límite.
  set local role postgres;
  select count(*) into v_rows from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000b1';
  assert v_rows = 2, 'FALLO 7d-pre: validaciones de RB esperadas 2 (A y C)';
  set local role authenticated;

  resp := public.validate_leak('00000000-0000-4000-8000-0000000000b1');
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 7d: la 21ª validación no fue rechazada: ' || resp::text;
  assert (resp->>'reset_at')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    'FALLO 7d-2: reset_at inesperado: ' || (resp->>'reset_at');

  set local role postgres;
  select count into v_c2 from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '33333333-3333-4333-8333-333333333333')
     and operation_type = 'validate_leak'
     and window_start = date_trunc('hour', now());
  assert v_c2 = 21, 'FALLO 7e: contador esperado 21, obtenido ' || v_c2;
  select count(*) into v_rows from public.report_validations
   where report_id = '00000000-0000-4000-8000-0000000000b1';
  assert v_rows = 2, 'FALLO 7e-2: el rechazo persistió una validación';
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 7: validate_leak: 20 consumidas (VALIDATED y DUPLICATE_ACTION), 21ª RATE_LIMIT_EXCEEDED sin efectos';
end $$;

-- =====================================================================
-- 8. Límite exacto de confirm_leak_resolution (10/hora): CONFIRMED +
--    DUPLICATE_ACTION ×9; la 11ª RATE_LIMIT_EXCEEDED.
-- =====================================================================
set request.jwt.claims =
  '{"role": "authenticated", "sub": "44444444-4444-4444-8444-444444444444", "aud": "authenticated"}';
do $$
declare
  resp    jsonb;
  i       int;
  v_count int;
begin
  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000d1');
  assert resp->>'status_code' = 'CONFIRMED', 'FALLO 8a: ' || resp::text;
  assert (resp->>'resolution_confirmation_count')::int = 1, 'FALLO 8a-2: contador distinto de 1';

  for i in 1..9 loop
    resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000d1');
    assert resp->>'status_code' = 'DUPLICATE_ACTION',
      format('FALLO 8b (iter %s): %s', i, resp::text);
  end loop;

  resp := public.confirm_leak_resolution('00000000-0000-4000-8000-0000000000d1');
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 8c: la 11ª confirmación no fue rechazada: ' || resp::text;
  assert (resp->>'reset_at')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    'FALLO 8c-2: reset_at inesperado: ' || (resp->>'reset_at');

  set local role postgres;
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '44444444-4444-4444-8444-444444444444')
     and operation_type = 'confirm_leak_resolution'
     and window_start = date_trunc('hour', now());
  assert v_count = 11, 'FALLO 8d: contador esperado 11, obtenido ' || v_count;
  set local role authenticated;

  -- Los duplicados no incrementaron el contador de resolución del reporte.
  assert (select resolution_confirmation_count from public.reports
           where id = '00000000-0000-4000-8000-0000000000d1') = 1,
    'FALLO 8e: los duplicados incrementaron resolution_confirmation_count';

  update rl_stats set passed = passed + 1;
  raise notice 'OK 8: confirm_leak_resolution: 10 consumidas, 11ª RATE_LIMIT_EXCEEDED';
end $$;

-- =====================================================================
-- 9. Límite exacto de register_water_event (5/hora): 5 CREATED, la 6ª
--    RATE_LIMIT_EXCEEDED. El primer evento queda como blanco de §10.
-- =====================================================================
set request.jwt.claims =
  '{"role": "authenticated", "sub": "55555555-5555-4555-8555-555555555555", "aud": "authenticated"}';
do $$
declare
  resp jsonb;
begin
  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '30 minutes', null);
  assert resp->>'status_code' = 'CREATED', 'FALLO 9a: ' || resp::text;
  insert into rl_ids values ('we1', (resp->>'event_id')::uuid);

  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_LEFT', now() - interval '25 minutes', null);
  assert resp->>'status_code' = 'CREATED', 'FALLO 9b: ' || resp::text;

  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '20 minutes', null);
  assert resp->>'status_code' = 'CREATED', 'FALLO 9c: ' || resp::text;

  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_LEFT', now() - interval '15 minutes', null);
  assert resp->>'status_code' = 'CREATED', 'FALLO 9d: ' || resp::text;

  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_ARRIVED', now() - interval '10 minutes', null);
  assert resp->>'status_code' = 'CREATED', 'FALLO 9e: ' || resp::text;

  resp := public.register_water_event(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    'WATER_LEFT', now() - interval '5 minutes', null);
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 9f: la 6ª llamada no fue rechazada: ' || resp::text;
  assert (resp->>'reset_at')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    'FALLO 9f-2: reset_at inesperado: ' || (resp->>'reset_at');

  update rl_stats set passed = passed + 1;
  raise notice 'OK 9: register_water_event: 5 CREATED, 6ª RATE_LIMIT_EXCEEDED';
end $$;

-- =====================================================================
-- 10. Límite exacto de validate_water_event (20/hora): VALIDATED +
--     DUPLICATE_ACTION ×19; la 21ª RATE_LIMIT_EXCEEDED.
-- =====================================================================
set request.jwt.claims =
  '{"role": "authenticated", "sub": "66666666-6666-4666-8666-666666666666", "aud": "authenticated"}';
do $$
declare
  resp    jsonb;
  i       int;
  v_event uuid;
  v_count int;
begin
  select id into v_event from rl_ids where label = 'we1';

  resp := public.validate_water_event(v_event);
  assert resp->>'status_code' = 'VALIDATED', 'FALLO 10a: ' || resp::text;
  assert (resp->>'validation_count')::int = 1, 'FALLO 10a-2: contador distinto de 1';

  for i in 1..19 loop
    resp := public.validate_water_event(v_event);
    assert resp->>'status_code' = 'DUPLICATE_ACTION',
      format('FALLO 10b (iter %s): %s', i, resp::text);
  end loop;

  resp := public.validate_water_event(v_event);
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 10c: la 21ª validación no fue rechazada: ' || resp::text;
  assert (resp->>'reset_at')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    'FALLO 10c-2: reset_at inesperado: ' || (resp->>'reset_at');

  set local role postgres;
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '66666666-6666-4666-8666-666666666666')
     and operation_type = 'validate_water_event'
     and window_start = date_trunc('hour', now());
  assert v_count = 21, 'FALLO 10d: contador esperado 21, obtenido ' || v_count;
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 10: validate_water_event: 20 consumidas, 21ª RATE_LIMIT_EXCEEDED';
end $$;

-- =====================================================================
-- 11. Config override: create_leak_report → 2 en system_config.rate_limits
--     (límite exacto honrado; se restaura el valor 3).
-- =====================================================================
set role postgres;
update public.system_config
   set value = jsonb_set(value, '{create_leak_report}', '2'::jsonb)
 where key = 'rate_limits';

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "77777777-7777-4777-8777-777777777777", "aud": "authenticated"}';
do $$
declare
  resp    jsonb;
  v_count int;
begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    12.000, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/77777777-7777-4777-8777-777777777777/rl1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 11a (límite config=2): ' || resp::text;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    12.010, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/77777777-7777-4777-8777-777777777777/rl2/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 11b (límite config=2): ' || resp::text;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    12.020, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/77777777-7777-4777-8777-777777777777/rl3/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 11c: con config=2 la 3ª llamada debía rechazarse: ' || resp::text;
  assert (resp->>'reset_at')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    'FALLO 11c-2: reset_at inesperado: ' || (resp->>'reset_at');

  set local role postgres;
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '77777777-7777-4777-8777-777777777777')
     and operation_type = 'create_leak_report'
     and window_start = date_trunc('hour', now());
  assert v_count = 3, 'FALLO 11d: contador esperado 3 (> límite config 2)';
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 11: config override (create_leak_report=2) honrado por el RPC';
end $$;

set role postgres;
update public.system_config
   set value = jsonb_set(value, '{create_leak_report}', '3'::jsonb)
 where key = 'rate_limits';
do $$ begin
  assert (select (value->>'create_leak_report')::int from public.system_config
           where key = 'rate_limits') = 3, 'FALLO 11-restore: config no restaurada';
  raise notice 'OK 11-restore: rate_limits.create_leak_report restaurado a 3';
end $$;

-- =====================================================================
-- 12. Fallback sin fila rate_limits: límite documentado (3) aplicado;
--     la fila de config se restaura al terminar.
-- =====================================================================
set role postgres;
insert into rl_cfg
select value from public.system_config where key = 'rate_limits';
delete from public.system_config where key = 'rate_limits';
do $$ begin
  assert public.get_rate_limit('create_leak_report') = 3,
    'FALLO 12-pre: fallback de get_rate_limit sin config no es 3';
  raise notice 'OK 12-pre: get_rate_limit cae al fallback (3) sin fila de config';
end $$;

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "88888888-8888-4888-8888-888888888888", "aud": "authenticated"}';
do $$
declare
  resp    jsonb;
  v_count int;
begin
  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    13.000, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/88888888-8888-4888-8888-888888888888/rl1/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 12a (fallback 3): ' || resp::text;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    13.010, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/88888888-8888-4888-8888-888888888888/rl2/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 12b (fallback 3): ' || resp::text;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    13.020, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/88888888-8888-4888-8888-888888888888/rl3/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'CREATED', 'FALLO 12c (fallback 3): ' || resp::text;

  resp := public.create_leak_report(
    '00000000-0000-4000-8000-0000000000f1',
    '00000000-0000-4000-8000-0000000000e1',
    13.030, -64.000, 'GPS', null,
    '[{"storage_path":"report_photos/88888888-8888-4888-8888-888888888888/rl4/p1.jpg","sort_order":1}]'::jsonb);
  assert resp->>'status_code' = 'RATE_LIMIT_EXCEEDED',
    'FALLO 12d: con fallback 3 la 4ª llamada debía rechazarse: ' || resp::text;
  assert (resp->>'reset_at')::timestamptz = date_trunc('hour', now()) + interval '1 hour',
    'FALLO 12d-2: reset_at inesperado: ' || (resp->>'reset_at');

  set local role postgres;
  select count into v_count from public.rate_limit_tracking
   where user_id = (select id from public.app_users
                     where auth_user_id = '88888888-8888-4888-8888-888888888888')
     and operation_type = 'create_leak_report'
     and window_start = date_trunc('hour', now());
  assert v_count = 4, 'FALLO 12e: contador esperado 4 (> fallback 3)';
  set local role authenticated;

  update rl_stats set passed = passed + 1;
  raise notice 'OK 12: sin fila de config aplica el fallback documentado (3)';
end $$;

set role postgres;
insert into public.system_config (key, value)
select 'rate_limits', value from rl_cfg
on conflict (key) do update set value = excluded.value, updated_at = now();
do $$ begin
  assert (select count(*) from public.system_config where key = 'rate_limits') = 1,
    'FALLO 12-restore: fila rate_limits no restaurada';
  assert (select (value->>'create_leak_report')::int from public.system_config
           where key = 'rate_limits') = 3, 'FALLO 12-restore-2: valor restaurado inesperado';
  raise notice 'OK 12-restore: fila rate_limits restaurada';
end $$;

-- =====================================================================
-- 13. Bypass de helpers (DEF-01): como authenticated y como anon,
--     EXECUTE de check_rate_limit / check_rate_limit_inline eleva
--     insufficient_privilege (42501); get_rate_limit SÍ es ejecutable
--     por authenticated (estado intencional).
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$ begin
  perform public.check_rate_limit(
    (select id from public.app_users
      where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    'create_leak_report');
  raise exception 'FALLO 13a: authenticated ejecutó check_rate_limit';
exception when insufficient_privilege then
  if sqlstate <> '42501' then
    raise exception 'FALLO 13a: sqlstate inesperado %', sqlstate;
  end if;
  raise notice 'OK 13a: check_rate_limit revocado para authenticated (42501)';
end $$;

do $$ begin
  perform public.check_rate_limit_inline(
    (select id from public.app_users
      where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    'create_leak_report');
  raise exception 'FALLO 13b: authenticated ejecutó check_rate_limit_inline';
exception when insufficient_privilege then
  if sqlstate <> '42501' then
    raise exception 'FALLO 13b: sqlstate inesperado %', sqlstate;
  end if;
  raise notice 'OK 13b: check_rate_limit_inline revocado para authenticated (42501)';
end $$;

set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';
do $$ begin
  perform public.check_rate_limit(
    (select id from public.app_users
      where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    'create_leak_report');
  raise exception 'FALLO 13c: anon ejecutó check_rate_limit';
exception when insufficient_privilege then
  if sqlstate <> '42501' then
    raise exception 'FALLO 13c: sqlstate inesperado %', sqlstate;
  end if;
  raise notice 'OK 13c: check_rate_limit revocado para anon (42501)';
end $$;

do $$ begin
  perform public.check_rate_limit_inline(
    (select id from public.app_users
      where auth_user_id = '11111111-1111-4111-8111-111111111111'),
    'create_leak_report');
  raise exception 'FALLO 13d: anon ejecutó check_rate_limit_inline';
exception when insufficient_privilege then
  if sqlstate <> '42501' then
    raise exception 'FALLO 13d: sqlstate inesperado %', sqlstate;
  end if;
  raise notice 'OK 13d: check_rate_limit_inline revocado para anon (42501)';
end $$;

set role postgres;
do $$
declare
  v_ok boolean;
  v_n  int;
begin
  -- Matriz de privilegios (estado intencional post-DEF-01).
  v_ok := not has_function_privilege('authenticated',
                                     'public.check_rate_limit(uuid,text)', 'EXECUTE')
      and not has_function_privilege('anon',
                                     'public.check_rate_limit(uuid,text)', 'EXECUTE')
      and not has_function_privilege('authenticated',
                                     'public.check_rate_limit_inline(uuid,text)', 'EXECUTE')
      and not has_function_privilege('anon',
                                     'public.check_rate_limit_inline(uuid,text)', 'EXECUTE')
      and has_function_privilege('authenticated',
                                 'public.get_rate_limit(text)', 'EXECUTE');
  assert v_ok, 'FALLO 13e: matriz de privilegios de helpers inesperada';

  -- Sin EXECUTE concedido a authenticated/anon/PUBLIC en los ACL reales.
  select count(*) into v_n
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    cross join lateral aclexplode(p.proacl) a
   where ns.nspname = 'public'
     and p.proname in ('check_rate_limit', 'check_rate_limit_inline')
     and p.pronargs = 2
     and a.privilege_type = 'EXECUTE'
     and pg_get_userbyid(a.grantee) in ('authenticated', 'anon', 'PUBLIC');
  assert v_n = 0, 'FALLO 13f: EXECUTE de un helper concedido a ' || v_n || ' roles';

  update rl_stats set passed = passed + 1;
  raise notice 'OK 13e: sin EXECUTE (authenticated/anon/PUBLIC); get_rate_limit concedido a authenticated';
end $$;

-- =====================================================================
-- 14. Acceso directo: SELECT / INSERT / DELETE en public.rate_limit_tracking
--     denegados para authenticated (RLS habilitada + grants revocados).
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';
do $$ begin
  perform count(*) from public.rate_limit_tracking;
  raise exception 'FALLO 14a: authenticated pudo leer rate_limit_tracking';
exception when insufficient_privilege then
  raise notice 'OK 14a: SELECT bloqueado';
end $$;

do $$ begin
  insert into public.rate_limit_tracking
    (user_id, operation_type, window_start, count)
  values ('00000000-0000-4000-8000-0000000000d1', 'validate_leak', now(), 1);
  raise exception 'FALLO 14b: authenticated pudo insertar en rate_limit_tracking';
exception when insufficient_privilege then
  raise notice 'OK 14b: INSERT bloqueado';
end $$;

do $$ begin
  delete from public.rate_limit_tracking;
  raise exception 'FALLO 14c: authenticated pudo borrar rate_limit_tracking';
exception when insufficient_privilege then
  raise notice 'OK 14c: DELETE bloqueado';
end $$;

set role postgres;
do $$
declare v_rls boolean;
begin
  select c.relrowsecurity into v_rls
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relname = 'rate_limit_tracking';
  assert v_rls, 'FALLO 14d: RLS no habilitada en rate_limit_tracking';
  update rl_stats set passed = passed + 1;
  raise notice 'OK 14d: RLS habilitada en rate_limit_tracking';
end $$;

-- =====================================================================
-- Resumen y limpieza (rollback de toda la transacción)
-- =====================================================================
do $$
declare n int;
begin
  select passed into n from rl_stats;
  assert n = 14, format('FALLO resumen: %s/14 secciones superadas', n);
  raise notice 'Resumen: % de 14 secciones de rate limiting superadas', n;
end $$;

reset role;
reset request.jwt.claims;
rollback;
do $$ begin
  raise notice 'Todas las pruebas de rate limiting pasaron.';
end $$;
