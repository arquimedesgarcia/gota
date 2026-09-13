-- 00018: Notificaciones (Sprint 06).
--
-- Implementa docs/API_SPEC.md §7, docs/DATA_MODEL.md §4 y
-- docs/FUNCTIONAL_SPEC.md §9/§10, sobre el patrón ya establecido en
-- Sprint 04 (20260911000014_water_events.sql):
--  * tablas con constraints, RLS cerrada para clientes y operaciones
--    críticas en funciones `security definer`;
--  * RPCs con `status_code` y mínimo privilegio (revoke/grant explícitos).
--
-- Decisión de diseño (docs/MIGRATION_NOTES.md, Sprint 06): UN SOLO sector de
-- interés por usuario, representado como columna nullable
-- (`preferred_sector_id`) en una fila única por usuario (PK = user_id).
-- No hay tabla de suscripciones ni arrays de sectores.
--
-- Cadena de notificación (docs/ARCHITECTURE.md):
--   water_events INSERT → trigger notify_water_event → notifications
--   → Database Webhook → Edge Function notify-push → FCM.
-- La fila de `notifications` es la fuente de verdad; el push es un
-- efecto posterior que NUNCA puede revertir la notificación persistente.

-- =====================================================================
-- 0. Helper: app_user_id del usuario autenticado
-- =====================================================================
-- Las políticas RLS de este sprint comparan contra `app_users.id` (FK de
-- las nuevas tablas), no contra `auth.users.id`. Función stable security
-- definer para no repetir el subselect en cada policy.
create or replace function public.current_app_user_id() returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.app_users where auth_user_id = auth.uid();
$$;

revoke execute on function public.current_app_user_id() from public, anon;
grant execute on function public.current_app_user_id() to authenticated;

-- =====================================================================
-- 1. Preferencias de notificación: un sector, opcional
-- =====================================================================
create table if not exists public.notification_preferences (
  -- PK = user_id garantiza exactamente 0..1 fila por usuario: la
  -- preferencia es escalar (un solo sector de interés, nullable).
  user_id                     uuid primary key references public.app_users(id) on delete cascade,
  -- 0 o 1 sector. No depende del GPS y no representa necesariamente el
  -- domicilio. Si el sector desaparece, la preferencia sobrevive sin él.
  preferred_sector_id         uuid references public.sectors(id) on delete set null,
  water_notifications_enabled boolean not null default true,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function public.set_updated_at();

-- Búsqueda de destinatarios por sector (trigger de generación, §4).
create index if not exists notification_preferences_sector_idx
  on public.notification_preferences (preferred_sector_id)
  where preferred_sector_id is not null;

-- =====================================================================
-- 2. Notifications persistentes
-- =====================================================================
create table if not exists public.notifications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.app_users(id) on delete cascade,
  water_event_id uuid not null references public.water_events(id) on delete cascade,
  type           text not null check (type in ('WATER_ARRIVED', 'WATER_LEFT')),
  title          text not null,
  body           text not null,
  created_at     timestamptz not null default now(),
  read_at        timestamptz,

  -- Autoridad real de idempotencia: procesar el mismo Water Event 1, 2 o
  -- 10 veces deja exactamente 1 notification por usuario. Aplica también
  -- ante inserciones concurrentes (la segunda transacción espera al
  -- unique index y su INSERT choca con la restricción).
  constraint notifications_unique_user_event
    unique (user_id, water_event_id)
);

-- Bandeja: notificaciones del usuario, más recientes primero.
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

-- =====================================================================
-- 3. Tokens FCM
-- =====================================================================
create table if not exists public.notification_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.app_users(id) on delete cascade,
  -- UNIQUE global: un token FCM pertenece a una sola identidad activa.
  token       text not null unique,
  platform    text not null check (platform in ('android', 'ios', 'web')),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create trigger notification_tokens_set_updated_at
  before update on public.notification_tokens
  for each row execute function public.set_updated_at();

-- Envío push: tokens activos de un usuario.
create index if not exists notification_tokens_user_active_idx
  on public.notification_tokens (user_id) where is_active;

-- =====================================================================
-- 4. RLS
-- =====================================================================
-- ---------- notification_preferences ----------
-- El usuario solo toca su propia fila. No hay DELETE concedido al cliente:
-- "quitar sector" = poner preferred_sector_id a NULL vía RPC.
alter table public.notification_preferences enable row level security;

create policy "Usuario lee sus preferencias"
  on public.notification_preferences for select
  to authenticated
  using (user_id = public.current_app_user_id());

create policy "Usuario crea sus preferencias"
  on public.notification_preferences for insert
  to authenticated
  with check (user_id = public.current_app_user_id());

create policy "Usuario actualiza sus preferencias"
  on public.notification_preferences for update
  to authenticated
  using (user_id = public.current_app_user_id())
  with check (user_id = public.current_app_user_id());

revoke all on public.notification_preferences from anon, authenticated;
grant select, insert, update on public.notification_preferences to authenticated;

-- ---------- notifications ----------
-- Lectura y "marcar leída" solo sobre filas propias. La única columna
-- actualizable desde el cliente es read_at: así el usuario NO puede
-- fabricar notifications ni cambiar destinatario, evento o contenido
-- (la creación está en el trigger §5, que corre como propietario de la
-- tabla, fuera del alcance de RLS). No hay INSERT ni DELETE concedidos.
alter table public.notifications enable row level security;

create policy "Usuario lee sus notifications"
  on public.notifications for select
  to authenticated
  using (user_id = public.current_app_user_id());

create policy "Usuario marca como leída sus notifications"
  on public.notifications for update
  to authenticated
  using (user_id = public.current_app_user_id())
  with check (user_id = public.current_app_user_id());

revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ---------- notification_tokens ----------
-- El usuario solo lee sus propios tokens. La escritura (register/unregister)
-- la hace la RPC register_notification_token y unregister_notification_token
-- con security definer, nunca el cliente directo (hardening).
alter table public.notification_tokens enable row level security;

create policy "Usuario lee sus tokens"
  on public.notification_tokens for select
  to authenticated
  using (user_id = public.current_app_user_id());

revoke all on public.notification_tokens from anon, authenticated;
grant select on public.notification_tokens to authenticated;

-- =====================================================================
-- 5. Generación server-side de notifications (Fase 3 del contrato)
-- =====================================================================
-- Al insertarse un WATER_ARRIVED / WATER_LEFT, se notifica a los usuarios
-- cuyo sector de interés coincide Y que tienen las notificaciones activas.
-- Reglas críticas que viven aquí, no en Flutter:
--  * un usuario elegible recibe exactamente 1 notification por evento
--    (UNIQUE (user_id, water_event_id) + ON CONFLICT DO NOTHING);
--  * usuarios sin sector o con otro sector no reciben nada;
--  * notifications desactivadas => 0 notifications nuevas;
--  * la lógica no depende del GPS.
create or replace function public.notify_water_event() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sector_name       text;
  v_municipality_name text;
  v_title             text;
  v_body              text;
begin
  if new.event_type not in ('WATER_ARRIVED', 'WATER_LEFT') then
    return new;
  end if;

  select s.name, m.name into v_sector_name, v_municipality_name
    from public.sectors s
    join public.municipalities m on m.id = s.municipality_id
   where s.id = new.sector_id;

  if new.event_type = 'WATER_ARRIVED' then
    v_title := 'Llegó el agua';
  else
    v_title := 'Se fue el agua';
  end if;
  v_body := 'Sector ' || coalesce(v_sector_name, '')
         || ' · ' || coalesce(v_municipality_name, '');

  insert into public.notifications (user_id, water_event_id, type, title, body)
  select p.user_id, new.id, new.event_type, v_title, v_body
    from public.notification_preferences p
   where p.preferred_sector_id = new.sector_id
     and p.water_notifications_enabled
  on conflict (user_id, water_event_id) do nothing;

  return new;
end;
$$;

drop trigger if exists water_events_notify on public.water_events;
create trigger water_events_notify
  after insert on public.water_events
  for each row execute function public.notify_water_event();

-- =====================================================================
-- 6. RPC save_notification_preferences (docs/API_SPEC.md §7)
-- =====================================================================
-- Upsert de la preferencia del usuario autenticado. `preferred_sector_id`
-- NULL significa "sin sector de interés". Validación server-side del
-- sector (existe y está activo). La unicidad 1 fila/usuario la garantiza
-- la PK, no el cliente.
--
-- Salidas (`status_code`): OK / NOT_FOUND / FORBIDDEN / UNAUTHORIZED
create or replace function public.save_notification_preferences(
  p_preferred_sector_id uuid,
  p_water_notifications_enabled boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid uuid;
  v_app_user public.app_users;
begin
  v_auth_uid := auth.uid();
  if v_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user from public.app_users
    where auth_user_id = v_auth_uid;
  if v_app_user.id is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;
  if v_app_user.is_blocked then
    return jsonb_build_object('status_code', 'FORBIDDEN',
                              'message', 'Tu acceso está bloqueado.');
  end if;

  if p_preferred_sector_id is not null then
    if not exists (
      select 1 from public.sectors
       where id = p_preferred_sector_id and is_active
    ) then
      return jsonb_build_object('status_code', 'NOT_FOUND',
                                'message', 'No encontramos este sector.');
    end if;
  end if;

  insert into public.notification_preferences
    (user_id, preferred_sector_id, water_notifications_enabled)
  values
    (v_app_user.id, p_preferred_sector_id, p_water_notifications_enabled)
  on conflict (user_id) do update
     set preferred_sector_id = excluded.preferred_sector_id,
         water_notifications_enabled = excluded.water_notifications_enabled;

  return jsonb_build_object('status_code', 'OK');
end;
$$;

revoke execute on function public.save_notification_preferences(uuid, boolean)
  from public, anon;
grant execute on function public.save_notification_preferences(uuid, boolean)
  to authenticated;

-- =====================================================================
-- 7. RPC register_notification_token (docs/API_SPEC.md §7)
-- =====================================================================
-- Registra (o reactiva) el token FCM del dispositivo para el usuario
-- autenticado. Como el token es UNIQUE global, un mismo token reasignado
-- (mismo dispositivo, otra sesión/instalación) pasa a pertenecer a la
-- identidad que lo registra ahora. El cliente nunca escribe `user_id`:
-- viene de auth.uid(), así nadie puede registrar un token a nombre de
-- otro usuario.
--
-- Salidas (`status_code`): OK / VALIDATION_ERROR / FORBIDDEN / UNAUTHORIZED
create or replace function public.register_notification_token(
  p_token text,
  p_platform text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid uuid;
  v_app_user public.app_users;
  v_token    text;
begin
  v_auth_uid := auth.uid();
  if v_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user from public.app_users
    where auth_user_id = v_auth_uid;
  if v_app_user.id is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;
  if v_app_user.is_blocked then
    return jsonb_build_object('status_code', 'FORBIDDEN',
                              'message', 'Tu acceso está bloqueado.');
  end if;

  v_token := nullif(trim(p_token), '');
  if v_token is null then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'El token de notificaciones no es válido.');
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'La plataforma no es válida.');
  end if;

  insert into public.notification_tokens
    (user_id, token, platform, is_active, last_seen_at)
  values
    (v_app_user.id, v_token, p_platform, true, now())
  on conflict (token) do update
     set user_id = excluded.user_id,
         platform = excluded.platform,
         is_active = true,
         last_seen_at = now();

  return jsonb_build_object('status_code', 'OK');
end;
$$;

revoke execute on function public.register_notification_token(text, text)
  from public, anon;
grant execute on function public.register_notification_token(text, text)
  to authenticated;

-- =====================================================================
-- 8. RPC unregister_notification_token
-- =====================================================================
-- Desactiva UN token propio (p. ej. logout o desinstalación controlada).
-- No borra filas: conserva historial de tokens obsoletos. La Edge
-- Function de push desactiva por su cuenta los tokens que FCM rechaza.
--
-- Salidas (`status_code`): OK / NOT_FOUND / UNAUTHORIZED
create or replace function public.unregister_notification_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid uuid;
  v_app_user public.app_users;
begin
  v_auth_uid := auth.uid();
  if v_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user from public.app_users
    where auth_user_id = v_auth_uid;
  if v_app_user.id is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  update public.notification_tokens
     set is_active = false
   where token = p_token
     and user_id = v_app_user.id;

  if not found then
    return jsonb_build_object('status_code', 'NOT_FOUND');
  end if;

  return jsonb_build_object('status_code', 'OK');
end;
$$;

revoke execute on function public.unregister_notification_token(text)
  from public, anon;
grant execute on function public.unregister_notification_token(text)
  to authenticated;

-- =====================================================================
-- 9. Realtime (bandeja en vivo con la app abierta)
-- =====================================================================
-- Realtime SOLO mejora la actualización del inbox cuando la app está
-- abierta; no sustituye a FCM (docs/ARCHITECTURE.md).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
