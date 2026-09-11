-- 00014: Eventos de agua (Sprint 04).
--
-- Implementa docs/API_SPEC.md §2 (register-water-event, validate-water-event),
-- docs/DATA_MODEL.md §2 (water_events, water_event_validations) y
-- docs/FUNCTIONAL_SPEC.md §8, sobre el patrón ya establecido en Sprint 02/03:
-- tablas con constraints, RLS cerrada para clientes y operaciones críticas
-- en funciones `security definer`.
--
-- Reglas aplicadas (docs/REQUIREMENTS.md §5):
--  * REQ-070: el usuario registra WATER_ARRIVED o WATER_LEFT.
--  * REQ-071/REQ-072: cada evento va ligado a municipio y sector, y separa
--    `event_time` (hora efectiva del evento) de `created_at` (hora de
--    registro en el sistema).
--  * REQ-073/REQ-074: otros usuarios validan el evento; el creador no puede
--    validar el suyo (regla server-side, como en validate_leak).
--  * REQ-075: una identidad valida una sola vez cada evento; la autoridad
--    real es UNIQUE (water_event_id, user_id).
--  * REQ-076: los eventos recientes e historial son consultables públicamente
--    sin exponer la identidad del creador.
--  * REQ-093: las acciones relevantes quedan en `audit_events`.
--
-- Decisiones registradas en docs/MIGRATION_NOTES.md:
--  * No hay ventana temporal de validación (los docs no la especifican).
--  * `event_time` no admite valores futuros (sanidad mínima, no es una
--    ventana de validación).
--  * Rate limiting queda para Sprint 07 (mismo precedente que Sprint 03):
--    REQ-091 lo asigna a "Security & abuse" en docs/MVP_PLAN.md.

-- =====================================================================
-- 1. Tabla de eventos de agua
-- =====================================================================
create table if not exists public.water_events (
  id              uuid primary key default gen_random_uuid(),
  created_by      uuid not null references public.app_users(id) on delete cascade,
  municipality_id uuid not null references public.municipalities(id) on delete restrict,
  sector_id       uuid not null references public.sectors(id) on delete restrict,
  event_type      text not null check (event_type in ('WATER_ARRIVED', 'WATER_LEFT')),
  event_time      timestamptz not null,
  comment         text check (comment is null or char_length(comment) <= 500),
  validation_count int not null default 0 check (validation_count >= 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create trigger water_events_set_updated_at
  before update on public.water_events
  for each row execute function public.set_updated_at();

-- Historial: los eventos se listan por sector/municipio ordenados por la
-- hora efectiva del evento (REQ-076), más recientes primero.
create index if not exists water_events_sector_event_time_idx
  on public.water_events (sector_id, event_time desc);

create index if not exists water_events_municipality_event_time_idx
  on public.water_events (municipality_id, event_time desc);

create index if not exists water_events_created_at_idx
  on public.water_events (created_at desc);

-- =====================================================================
-- 2. Tabla de validaciones comunitarias
-- =====================================================================
create table if not exists public.water_event_validations (
  id             uuid primary key default gen_random_uuid(),
  water_event_id uuid not null references public.water_events(id) on delete cascade,
  user_id        uuid not null references public.app_users(id) on delete cascade,
  created_at     timestamptz not null default now(),

  -- Autoridad real contra duplicados: una identidad, una validación.
  constraint water_event_validations_unique_user
    unique (water_event_id, user_id)
);

create index if not exists water_event_validations_event_idx
  on public.water_event_validations (water_event_id);

create index if not exists water_event_validations_user_idx
  on public.water_event_validations (user_id);

-- =====================================================================
-- 3. RLS
-- =====================================================================
-- water_events: lectura pública (historial). La identidad del creador no
-- se expone: el cliente nunca solicita `created_by` (mismo criterio que
-- reports, ver docs/MIGRATION_NOTES.md), y las escrituras pasan por la RPC
-- register_water_event. El contador solo lo mueve validate_water_event.
alter table public.water_events enable row level security;

create policy "Lectura pública de eventos de agua"
  on public.water_events for select
  to anon, authenticated
  using (true);

-- Sin políticas insert/update/delete: denegado por defecto.
revoke all on public.water_events from anon, authenticated;
grant select on public.water_events to anon, authenticated;

-- water_event_validations: sin acceso de cliente, igual que
-- report_validations / resolution_confirmations en Sprint 03.
--  * lectura del estado propio (¿ya validé?) -> RPC get_water_event_detail;
--  * escritura -> RPC validate_water_event.
alter table public.water_event_validations enable row level security;

revoke all on public.water_event_validations from anon, authenticated;

-- =====================================================================
-- 4. RPC register_water_event (docs/API_SPEC.md §2)
-- =====================================================================
-- Registra un evento WATER_ARRIVED / WATER_LEFT con su hora efectiva
-- (`event_time`, que puede diferir de `created_at`, REQ-072) y comentario
-- opcional. Todas las reglas críticas viven aquí, no en Flutter.
--
-- Salidas (`status_code`):
--   CREATED / NOT_FOUND / INVALID_SECTOR / VALIDATION_ERROR /
--   FORBIDDEN / UNAUTHORIZED
create or replace function public.register_water_event(
  p_municipality_id uuid,
  p_sector_id       uuid,
  p_event_type      text,
  p_event_time      timestamptz,
  p_comment         text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid     uuid;
  v_app_user     public.app_users;
  v_municipality public.municipalities;
  v_sector       public.sectors;
  v_event        public.water_events;
  v_comment      text;
begin
  -- ---------- 1. Autenticación y usuario de aplicación ----------
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

  -- ---------- 2. Municipio ----------
  select * into v_municipality from public.municipalities
    where id = p_municipality_id;
  if v_municipality.id is null or not v_municipality.is_active then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos este municipio.');
  end if;

  -- ---------- 3. Sector y pertenencia al municipio (REQ-071) ----------
  select * into v_sector from public.sectors
    where id = p_sector_id;
  if v_sector.id is null or not v_sector.is_active then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos este sector.');
  end if;
  if v_sector.municipality_id <> p_municipality_id then
    return jsonb_build_object('status_code', 'INVALID_SECTOR',
                              'message', 'El sector no pertenece al municipio.');
  end if;

  -- ---------- 4. Tipo de evento (REQ-070) ----------
  if p_event_type not in ('WATER_ARRIVED', 'WATER_LEFT') then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'Tipo de evento no válido.');
  end if;

  -- ---------- 5. Hora efectiva del evento (REQ-072) ----------
  -- Debe existir y no puede estar en el futuro (sanidad mínima; no es una
  -- ventana de validación, ver docs/MIGRATION_NOTES.md).
  if p_event_time is null then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'Indica la hora del evento.');
  end if;
  if p_event_time > now() then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'La hora del evento no puede estar en el futuro.');
  end if;

  -- ---------- 6. Comentario opcional ----------
  v_comment := nullif(trim(p_comment), '');
  if v_comment is not null and char_length(v_comment) > 500 then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'El comentario no puede superar 500 caracteres.');
  end if;

  -- ---------- 7. Insert ----------
  insert into public.water_events
    (created_by, municipality_id, sector_id, event_type, event_time, comment)
  values
    (v_app_user.id, p_municipality_id, p_sector_id, p_event_type,
     p_event_time, v_comment)
  returning * into v_event;

  -- ---------- 8. Auditoría (REQ-093) ----------
  insert into public.audit_events
    (user_id, event_type, entity_type, entity_id, metadata)
  values
    (v_auth_uid, 'WATER_EVENT_CREATED', 'water_event', v_event.id,
     jsonb_build_object('event_type', v_event.event_type));

  return jsonb_build_object(
    'status_code', 'CREATED',
    'event_id', v_event.id,
    'event_type', v_event.event_type,
    'event_time', v_event.event_time,
    'created_at', v_event.created_at
  );
end;
$$;

revoke execute on function public.register_water_event(uuid, uuid, text, timestamptz, text)
  from public, anon;
grant execute on function public.register_water_event(uuid, uuid, text, timestamptz, text)
  to authenticated;

-- =====================================================================
-- 5. RPC validate_water_event (docs/API_SPEC.md §2)
-- =====================================================================
-- Una identidad válida un evento una sola vez (REQ-073/REQ-075) y el
-- creador no valida el suyo (REQ-074), igual que validate_leak.
--
-- Atomicidad: la fila del evento se bloquea (`for update`), lo que
-- serializa las validaciones concurrentes: la segunda transacción espera,
-- vuelve a leer el estado real y su inserción choca con
-- UNIQUE (water_event_id, user_id). Validación, contador y auditoría
-- ocurren en la misma transacción.
--
-- Salidas (`status_code`):
--   VALIDATED / DUPLICATE_ACTION / NOT_FOUND / FORBIDDEN / UNAUTHORIZED
create or replace function public.validate_water_event(p_water_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid uuid;
  v_app_user public.app_users;
  v_event    public.water_events;
  v_inserted uuid;
  v_count    int;
begin
  -- ---------- 1. Autenticación y usuario de aplicación ----------
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

  -- ---------- 2. Evento (fila bloqueada) ----------
  select * into v_event from public.water_events
    where id = p_water_event_id
    for update;

  if v_event.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos este evento.');
  end if;

  -- ---------- 3. El creador no valida su propio evento (REQ-074) ----------
  if v_event.created_by = v_app_user.id then
    return jsonb_build_object('status_code', 'FORBIDDEN',
      'message', 'No puedes validar tu propio evento.');
  end if;

  -- ---------- 4. Una validación por identidad y evento (REQ-075) ----------
  insert into public.water_event_validations (water_event_id, user_id)
  values (p_water_event_id, v_app_user.id)
  on conflict (water_event_id, user_id) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    -- Segunda acción del mismo usuario: determinista y sin efectos.
    return jsonb_build_object(
      'status_code', 'DUPLICATE_ACTION',
      'message', 'Ya validaste este evento.',
      'already_validated', true,
      'validation_count', v_event.validation_count
    );
  end if;

  -- ---------- 5. Contador consistente con el registro ----------
  update public.water_events
     set validation_count = validation_count + 1
   where id = p_water_event_id
  returning validation_count into v_count;

  if v_count is null then
    -- Invariante: nunca puede existir una validación sin contador.
    raise exception 'validation_count no pudo actualizarse para %',
      p_water_event_id using errcode = 'P0001';
  end if;

  -- ---------- 6. Auditoría (REQ-093) ----------
  insert into public.audit_events
    (user_id, event_type, entity_type, entity_id, metadata)
  values
    (v_auth_uid, 'WATER_EVENT_VALIDATED', 'water_event', p_water_event_id,
     jsonb_build_object('validation_count', v_count));

  return jsonb_build_object(
    'status_code', 'VALIDATED',
    'already_validated', false,
    'validation_count', v_count
  );
end;
$$;

revoke execute on function public.validate_water_event(uuid) from public, anon;
grant execute on function public.validate_water_event(uuid) to authenticated;

-- =====================================================================
-- 6. RPC get_water_event_detail
-- =====================================================================
-- Lectura del detalle + estado del usuario actual (¿es creador? ¿ya validó?),
-- necesaria para que la UI no ofrezca acciones inválidas. El cliente no lee
-- la tabla de validaciones: todo sale de aquí. No expone `created_by`.
create or replace function public.get_water_event_detail(p_water_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_uid  uuid;
  v_app_user  public.app_users;
  v_event     public.water_events;
  v_sector    public.sectors;
  v_municipal public.municipalities;
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

  select * into v_event from public.water_events where id = p_water_event_id;
  if v_event.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos este evento.');
  end if;

  select * into v_sector from public.sectors where id = v_event.sector_id;
  select * into v_municipal
    from public.municipalities where id = v_event.municipality_id;

  return jsonb_build_object(
    'status_code', 'OK',
    'event_id', v_event.id,
    'event_type', v_event.event_type,
    'event_time', v_event.event_time,
    'comment', v_event.comment,
    'validation_count', v_event.validation_count,
    'created_at', v_event.created_at,
    'updated_at', v_event.updated_at,
    'municipality_id', v_event.municipality_id,
    'municipality_name', v_municipal.name,
    'sector_id', v_event.sector_id,
    'sector_name', v_sector.name,
    'is_creator', (v_event.created_by = v_app_user.id),
    'is_blocked', v_app_user.is_blocked,
    'already_validated', exists (
      select 1 from public.water_event_validations
       where water_event_id = p_water_event_id and user_id = v_app_user.id
    )
  );
end;
$$;

revoke execute on function public.get_water_event_detail(uuid)
  from public, anon;
grant execute on function public.get_water_event_detail(uuid)
  to authenticated;
