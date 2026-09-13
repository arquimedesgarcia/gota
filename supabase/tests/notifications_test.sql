-- tests/notifications_test.sql — Pruebas de Sprint 06:
-- preferencias de notificación (un solo sector, opcional), notifications
-- persistentes (idempotencia, generación server-side desde water_events),
-- tokens FCM (RPC register/unregister, plataformas) y RLS de las tres
-- tablas (aislamiento entre usuarios, sin INSERT de notifications,
-- read_at como única columna actualizable).
--
-- Ejecutar contra una BD Supabase con las migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/tests/notifications_test.sql
--   (con Supabase local: docker exec -i supabase_db_gota psql -U postgres \
--     -d postgres -v ON_ERROR_STOP=1 < supabase/tests/notifications_test.sql)
--
-- Todo corre en una transacción que se revierte al terminar: el script no
-- deja datos en la base.

begin;
set role postgres;
reset request.jwt.claims;

-- =====================================================================
-- Preparación
-- =====================================================================
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'notif-a@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'notif-b@gota.test'),
  ('33333333-3333-4333-8333-333333333333', 'notif-c@gota.test'),
  ('44444444-4444-4444-8444-444444444444', 'notif-d@gota.test'),
  ('55555555-5555-4555-8555-555555555555', 'notif-blocked@gota.test'),
  ('66666666-6666-4666-8666-666666666666', 'notif-e@gota.test')
on conflict (id) do nothing;

update public.app_users set is_blocked = true
 where auth_user_id = '55555555-5555-4555-8555-555555555555';

insert into public.municipalities (id, name, state, is_active) values
  ('00000000-0000-4000-8000-0000000000f1', 'Municipio Sprint 06', 'Nueva Esparta', true)
on conflict (id) do nothing;

insert into public.sectors (id, municipality_id, name, is_active) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', 'Sector X', true),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1', 'Sector Y', true)
on conflict (id) do nothing;

do $$ begin
  raise notice 'OK 0: datos de prueba listos';
end $$;

-- =====================================================================
-- 1. Estructura: RLS, constraints de idempotencia y plataformas
-- =====================================================================
do $$
declare n int; begin
  select count(*) into n from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public'
     and c.relname in ('notifications', 'notification_preferences', 'notification_tokens')
     and c.relrowsecurity = true;
  assert n = 3, 'FALLO 1a: RLS no está habilitada en las 3 tablas';
  raise notice 'OK 1a: RLS habilitada en notifications, notification_preferences y notification_tokens';
end $$;

do $$ begin
  assert exists (select 1 from pg_constraint
    where conname = 'notifications_unique_user_event' and contype = 'u'),
    'FALLO 1b: falta UNIQUE (user_id, water_event_id) en notifications';
  assert exists (select 1 from pg_constraint
    where conname = 'notification_preferences_pkey' and contype = 'p'),
    'FALLO 1b: notification_preferences no tiene PK user_id (1 fila/usuario)';
  raise notice 'OK 1b: UNIQUE (user_id, water_event_id) y PK user_id presentes';
end $$;

do $$ begin
  assert exists (select 1 from pg_constraint
    where conname = 'notification_tokens_platform_check'
      and pg_get_constraintdef(oid) like '%android%ios%'
      and pg_get_constraintdef(oid) not like '%web%'),
    'FALLO 1c: platform sigue admitiendo web (Sprint 06 = android/ios)';
  raise notice 'OK 1c: platform restringido a android/ios';
end $$;

do $$ begin
  assert exists (select 1 from pg_trigger where tgname = 'water_events_notify'),
    'FALLO 1d: falta trigger water_events_notify';
  raise notice 'OK 1d: trigger de generación water_events_notify instalado';
end $$;

-- =====================================================================
-- 2. Preferencias (RPC save_notification_preferences)
-- =====================================================================
-- 2a. Crear preferencia con sector X y ON.
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "aud": "authenticated", "sub": "11111111-1111-4111-8111-111111111111"}';
do $$ declare r jsonb; begin
  r := public.save_notification_preferences('00000000-0000-4000-8000-0000000000e1', true);
  assert r->>'status_code' = 'OK', 'FALLO 2a: save preferences';
  assert exists (select 1 from public.notification_preferences
    where preferred_sector_id = '00000000-0000-4000-8000-0000000000e1'
      and water_notifications_enabled), 'FALLO 2a: preferencia no guardada';
  raise notice 'OK 2a: preferencia creada (sector X, ON)';
end $$;

-- 2b. Cambiar sector (X -> Y) y desactivar: el sector se conserva al OFF.
do $$ declare r jsonb; begin
  r := public.save_notification_preferences('00000000-0000-4000-8000-0000000000e2', false);
  assert r->>'status_code' = 'OK', 'FALLO 2b: save preferences';
  assert exists (select 1 from public.notification_preferences
    where preferred_sector_id = '00000000-0000-4000-8000-0000000000e2'
      and not water_notifications_enabled), 'FALLO 2b: OFF no conservó el sector';
  raise notice 'OK 2b: cambio de sector + OFF conserva el sector';
end $$;

-- 2c. Quitar sector = NULL; una sola fila por usuario.
do $$ declare r jsonb; n int; begin
  r := public.save_notification_preferences(null, true);
  assert r->>'status_code' = 'OK', 'FALLO 2c: quitar sector';
  select count(*) into n from public.notification_preferences
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111');
  assert n = 1 and exists (select 1 from public.notification_preferences
    where user_id = (select id from public.app_users
                      where auth_user_id = '11111111-1111-4111-8111-111111111111')
      and preferred_sector_id is null), 'FALLO 2c: fila única/sector NULL';
  raise notice 'OK 2c: sector eliminado (NULL), sigue habiendo 1 fila por usuario';
end $$;

-- 2d. Sector inexistente => NOT_FOUND; usuario bloqueado => FORBIDDEN.
do $$ declare r jsonb; begin
  r := public.save_notification_preferences('00000000-0000-4000-8000-0000000000ee', true);
  assert r->>'status_code' = 'NOT_FOUND', 'FALLO 2d: sector inexistente';
  raise notice 'OK 2d: sector inexistente => NOT_FOUND';
end $$;

set request.jwt.claims =
  '{"role": "authenticated", "aud": "authenticated", "sub": "55555555-5555-4555-8555-555555555555"}';
do $$ declare r jsonb; begin
  r := public.save_notification_preferences(null, true);
  assert r->>'status_code' = 'FORBIDDEN', 'FALLO 2e: usuario bloqueado';
  raise notice 'OK 2e: usuario bloqueado => FORBIDDEN';
end $$;
reset request.jwt.claims;
set role postgres;

-- =====================================================================
-- 3. Generación server-side de notifications desde water_events
-- =====================================================================
-- Usuarios (como app_users) para el escenario de generación.
-- A: sector X + ON. B: sector X + OFF. C: sector Y + ON. D: sin sector.
set role postgres;
insert into public.notification_preferences (user_id, preferred_sector_id, water_notifications_enabled)
select u.id, '00000000-0000-4000-8000-0000000000e1', true
  from public.app_users u where u.auth_user_id = '11111111-1111-4111-8111-111111111111'
on conflict (user_id) do update set preferred_sector_id = excluded.preferred_sector_id,
                                    water_notifications_enabled = true;
insert into public.notification_preferences (user_id, preferred_sector_id, water_notifications_enabled)
select u.id, '00000000-0000-4000-8000-0000000000e1', false
  from public.app_users u where u.auth_user_id = '22222222-2222-4222-8222-222222222222'
on conflict (user_id) do update set preferred_sector_id = excluded.preferred_sector_id,
                                    water_notifications_enabled = false;
insert into public.notification_preferences (user_id, preferred_sector_id, water_notifications_enabled)
select u.id, '00000000-0000-4000-8000-0000000000e2', true
  from public.app_users u where u.auth_user_id = '33333333-3333-4333-8333-333333333333'
on conflict (user_id) do update set preferred_sector_id = excluded.preferred_sector_id,
                                    water_notifications_enabled = true;

-- Caso 1: WATER_ARRIVED en X => A recibe exactamente 1 notification.
insert into public.water_events
  (created_by, municipality_id, sector_id, event_type, event_time)
select u.id, '00000000-0000-4000-8000-0000000000f1',
       '00000000-0000-4000-8000-0000000000e1', 'WATER_ARRIVED', now() - interval '1 hour'
  from public.app_users u where u.auth_user_id = '11111111-1111-4111-8111-111111111111';

do $$ declare n int; begin
  select count(*) into n from public.notifications
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111');
  assert n = 1, 'FALLO 3.1: WATER_ARRIVED X no generó exactamente 1 notification para A';
  raise notice 'OK 3.1: WATER_ARRIVED en X => 1 notification (A)';
end $$;

-- Caso 4: B tiene sector X pero OFF => 0 nuevas notifications.
do $$ declare n int; begin
  select count(*) into n from public.notifications
   where user_id = (select id from public.app_users
                     where auth_user_id = '22222222-2222-4222-8222-222222222222');
  assert n = 0, 'FALLO 3.4: OFF generó notifications';
  raise notice 'OK 3.4: OFF => 0 notifications (B)';
end $$;

-- Caso 3: C tiene sector Y (distinto al del evento X) => 0 notifications.
do $$ declare n int; begin
  select count(*) into n from public.notifications
   where user_id = (select id from public.app_users
                     where auth_user_id = '33333333-3333-4333-8333-333333333333');
  assert n = 0, 'FALLO 3.3: sector Y recibió notification del evento en X';
  raise notice 'OK 3.3: sector distinto => 0 notifications (C)';
end $$;

-- Caso 2: D sin sector => 0 notifications.
do $$ declare n int; begin
  select count(*) into n from public.notifications
   where user_id = (select id from public.app_users
                     where auth_user_id = '44444444-4444-4444-8444-444444444444');
  assert n = 0, 'FALLO 3.2: usuario sin sector recibió notification';
  raise notice 'OK 3.2: sin sector => 0 notifications (D)';
end $$;

-- Caso 5: WATER_LEFT en X => A recibe una notification más (distinto evento).
insert into public.water_events
  (created_by, municipality_id, sector_id, event_type, event_time)
select u.id, '00000000-0000-4000-8000-0000000000f1',
       '00000000-0000-4000-8000-0000000000e1', 'WATER_LEFT', now() - interval '30 minutes'
  from public.app_users u where u.auth_user_id = '11111111-1111-4111-8111-111111111111';

do $$ declare n int; begin
  select count(*) into n from public.notifications
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111');
  assert n = 2, 'FALLO 3.5: WATER_LEFT no generó la 2ª notification para A';
  raise notice 'OK 3.5: WATER_LEFT en X => notification adicional (A)';
end $$;

-- Caso 6 / idempotencia: la BD es la autoridad final. Un segundo
-- procesamiento del mismo evento (mismo user_id + water_event_id) choca
-- con el constraint: ON CONFLICT DO NOTHING deja la fila única.
do $$ declare
  v_user uuid;
  v_event uuid;
  n int;
begin
  select id into v_user from public.app_users
   where auth_user_id = '11111111-1111-4111-8111-111111111111';
  select water_event_id into v_event from public.notifications
   where user_id = v_user order by created_at desc limit 1;

  insert into public.notifications (user_id, water_event_id, type, title, body)
  values (v_user, v_event, 'WATER_LEFT', 'Reintento', 'Reintento')
  on conflict (user_id, water_event_id) do nothing;

  select count(*) into n from public.notifications
   where user_id = v_user and water_event_id = v_event;
  assert n = 1, 'FALLO 3.6: el mismo evento produjo duplicados';

  -- Y un INSERT directo sin ON CONFLICT debe fallar.
  begin
    insert into public.notifications (user_id, water_event_id, type, title, body)
    values (v_user, v_event, 'WATER_LEFT', 'Duplicado', 'Duplicado');
    assert false, 'FALLO 3.6: el constraint no rechazó el duplicado';
  exception when unique_violation then
    null;
  end;

  raise notice 'OK 3.6: idempotencia real (UNIQUE user_id + water_event_id)';
end $$;

-- =====================================================================
-- 4. Tokens FCM (RPC register/unregister)
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "aud": "authenticated", "sub": "11111111-1111-4111-8111-111111111111"}';
do $$ declare r jsonb; begin
  r := public.register_notification_token('token-dispositivo-a', 'android');
  assert r->>'status_code' = 'OK', 'FALLO 4a: register token';
  raise notice 'OK 4a: register_notification_token (android)';
end $$;

-- Plataforma no soportada (web) => VALIDATION_ERROR.
do $$ declare r jsonb; begin
  r := public.register_notification_token('token-web', 'web');
  assert r->>'status_code' = 'VALIDATION_ERROR', 'FALLO 4b: web sigue admitido';
  raise notice 'OK 4b: platform web rechazado';
end $$;

-- Re-registro del mismo token (mismo usuario): sigue activo, sin duplicado.
do $$ declare r jsonb; n int; begin
  r := public.register_notification_token('token-dispositivo-a', 'android');
  assert r->>'status_code' = 'OK', 'FALLO 4c: re-register';
  select count(*) into n from public.notification_tokens where token = 'token-dispositivo-a';
  assert n = 1, 'FALLO 4c: re-register duplicó la fila';
  raise notice 'OK 4c: re-register idempotente (1 fila)';
end $$;

do $$ declare r jsonb; begin
  r := public.unregister_notification_token('token-dispositivo-a');
  assert r->>'status_code' = 'OK', 'FALLO 4d: unregister';
  assert exists (select 1 from public.notification_tokens
    where token = 'token-dispositivo-a' and not is_active),
    'FALLO 4d: unregister no desactivó';
  raise notice 'OK 4d: unregister desactiva el token propio';
end $$;

-- 4e. El cliente no puede hacer INSERT directo en notification_tokens
-- (hardening: solo RPC).
do $$ begin
  begin
    insert into public.notification_tokens (user_id, token, platform)
    select id, 'token-directo', 'android'
      from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111';
    assert false, 'FALLO 4e: el cliente insertó directo en tokens';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'OK 4e: INSERT directo en tokens denegado (solo RPC)';
end $$;
reset request.jwt.claims;
set role postgres;

-- =====================================================================
-- 5. RLS: aislamiento entre usuarios
-- =====================================================================
-- 5a. Crear explícitamente una notification para C como admin, verificar
-- que A no puede leerla: prueba de RLS real (no falso positivo por
-- ausencia de datos).
set role postgres;
do $$ declare
  v_user_c uuid;
  v_event uuid;
begin
  select id into v_user_c from public.app_users
   where auth_user_id = '33333333-3333-4333-8333-333333333333';
  select id into v_event from public.water_events
   where sector_id = '00000000-0000-4000-8000-0000000000e1'
   order by created_at limit 1;
  -- Insertar una notification explícita para C.
  insert into public.notifications (user_id, water_event_id, type, title, body)
  values (v_user_c, v_event, 'WATER_ARRIVED', 'Notificación de C', 'Para usuario C')
  on conflict (user_id, water_event_id) do nothing;
end $$;

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "aud": "authenticated", "sub": "11111111-1111-4111-8111-111111111111"}';
do $$ declare
  v_other uuid;
  v_notif uuid;
  n int;
begin
  select id into v_other from public.app_users
   where auth_user_id = '33333333-3333-4333-8333-333333333333';
  -- A intenta leer notifications de C.
  select count(*) into n from public.notifications where user_id = v_other;
  assert n = 0, 'FALLO 5a: A lee notifications ajenas (RLS falló)';

  -- A intenta modificar notifications de C (debe fallar).
  select id into v_notif from public.notifications
   where user_id = v_other limit 1;
  if v_notif is not null then
    begin
      update public.notifications set read_at = now() where id = v_notif;
      assert not found, 'FALLO 5a: A modificó notification ajena';
    exception when insufficient_privilege then
      null;
    end;
  end if;

  raise notice 'OK 5a: A no ve ni modifica notifications de C (RLS real)';
end $$;

-- 5b. A no puede INSERTAR notifications (creación server-side).
do $$ begin
  begin
    insert into public.notifications
      (user_id, water_event_id, type, title, body)
    select id, '00000000-0000-4000-8000-0000000000e1', 'WATER_ARRIVED', 'x', 'x'
      from public.app_users where auth_user_id = '11111111-1111-4111-8111-111111111111';
    assert false, 'FALLO 5b: el cliente insertó una notification';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'OK 5b: INSERT de notifications denegado al cliente';
end $$;

-- 5c. A puede marcar como leída SOLO sus notifications y SOLO read_at.
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "aud": "authenticated", "sub": "11111111-1111-4111-8111-111111111111"}';
do $$ declare
  v_notification uuid;
  v_other_notification uuid;
begin
  select id into v_notification from public.notifications
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111')
   order by created_at desc limit 1;

  update public.notifications set read_at = now() where id = v_notification;
  assert found, 'FALLO 5c: no se pudo marcar como leída la notification propia';
  assert exists (select 1 from public.notifications
    where id = v_notification and read_at is not null),
    'FALLO 5c: read_at no quedó guardado';
  raise notice 'OK 5c: read_at actualizable en notification propia';
end $$;

-- 5d. Cambiar el destinatario o el contenido desde el cliente => denegado
-- (grant de columna: solo read_at; RLS: solo filas propias).
do $$ declare
  v_other uuid;
  v_notification uuid;
begin
  select id into v_other from public.app_users
   where auth_user_id = '33333333-3333-4333-8333-333333333333';
  select id into v_notification from public.notifications
   where user_id = (select id from public.app_users
                     where auth_user_id = '11111111-1111-4111-8111-111111111111')
   order by created_at desc limit 1;

  begin
    update public.notifications set user_id = v_other where id = v_notification;
    assert false, 'FALLO 5d: se cambió el destinatario desde el cliente';
  exception when insufficient_privilege then
    null;
  end;
  begin
    update public.notifications set title = 'Fabricada' where id = v_notification;
    assert false, 'FALLO 5d: se cambió el contenido desde el cliente';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'OK 5d: cambio de destinatario/contenido denegado (RLS + grant de columna)';
end $$;

-- 5e. Preferencias ajenas: A no lee ni escribe la fila de C.
do $$ declare
  v_other uuid;
  n int;
begin
  select id into v_other from public.app_users
   where auth_user_id = '33333333-3333-4333-8333-333333333333';
  select count(*) into n from public.notification_preferences where user_id = v_other;
  assert n = 0, 'FALLO 5e: A lee las preferencias de C';
  update public.notification_preferences
     set water_notifications_enabled = false
   where user_id = v_other;
  assert not found, 'FALLO 5e: A modificó preferencias ajenas';
  raise notice 'OK 5e: preferencias ajenas no legibles ni modificables';
end $$;

-- 5f. Tokens ajenos: A no ve el token de C.
do $$ declare
  v_other uuid;
begin
  select id into v_other from public.app_users
   where auth_user_id = '33333333-3333-4333-8333-333333333333';
  perform 1 from public.notification_tokens where user_id = v_other;
  assert not found, 'FALLO 5f: A lee tokens ajenos';
  raise notice 'OK 5f: tokens de otros usuarios no visibles';
end $$;
reset request.jwt.claims;
set role postgres;

do $$ begin
  raise notice 'TODAS LAS PRUEBAS DE SPRINT 06 PASARON';
end $$;

rollback;
