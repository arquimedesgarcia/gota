-- 00035: Dirección (reverse-geocode) en eventos de agua.
--
-- Migra el flujo "Reportar agua" a la misma captura de ubicación por GPS +
-- reverse geocoding que ya usa "Reportar fuga" (docs/backlog/reporte-agua-gps.md).
-- El municipio y el sector se siguen resolviendo contra el catálogo (la
-- deduplicación de eventos depende de `sector_id`), pero ahora se guarda
-- además la dirección completa sugerida por el geocoder para mostrarla en el
-- detalle del evento.
--
-- Cambios:
--   * `water_events.address` (text, nullable, <= 500 chars).
--   * `register_water_event` acepta `p_address` opcional y lo persiste en los
--     eventos CREATED (no toca eventos CONFIRMED: la dirección pertenece al
--     reporte original).
--   * `get_water_event_detail` devuelve `address`.
--
-- Se conserva íntegra la lógica de deduplicación introducida en 00029
-- (ventana de 4 horas, CONFIRMED / ALREADY_REPORTED).

-- =====================================================================
-- 1. Nueva columna
-- =====================================================================
alter table public.water_events
  add column if not exists address text
    check (address is null or char_length(address) <= 500);

-- =====================================================================
-- 2. RPC register_water_event (+ p_address)
-- =====================================================================
-- La firma cambia (6 argumentos): se elimina la versión de 5 argumentos para
-- evitar overloads ambiguos al resolver la RPC desde PostgREST.
drop function if exists public.register_water_event(uuid, uuid, text, timestamptz, text);

create or replace function public.register_water_event(
  p_municipality_id uuid,
  p_sector_id       uuid,
  p_event_type      text,
  p_event_time      timestamptz,
  p_comment         text default null,
  p_address         text default null
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
  v_existing     public.water_events;
  v_comment      text;
  v_address      text;
  v_inserted     uuid;
  v_count        int;
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
  if p_event_time is null then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'Indica la hora del evento.');
  end if;
  if p_event_time > now() then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'La hora del evento no puede estar en el futuro.');
  end if;

  -- ---------- 6. Comentario y dirección opcionales ----------
  v_comment := nullif(trim(p_comment), '');
  if v_comment is not null and char_length(v_comment) > 500 then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'El comentario no puede superar 500 caracteres.');
  end if;

  v_address := nullif(trim(p_address), '');
  if v_address is not null and char_length(v_address) > 500 then
    -- La dirección viene del geocoder; si excede el límite se recorta en
    -- lugar de rechazar el evento (no es un dato crítico).
    v_address := left(v_address, 500);
  end if;

  -- ---------- 7. Detección de evento reciente idéntico (ventana 4 horas) ----------
  -- Busca el evento más reciente del mismo sector y tipo creado en las
  -- últimas 4 horas. El FOR UPDATE serializa auto-validaciones concurrentes:
  -- la segunda transacción espera, relee el estado real, y su INSERT en
  -- water_event_validations choca con UNIQUE (water_event_id, user_id).
  select * into v_existing
    from public.water_events
   where sector_id  = p_sector_id
     and event_type = p_event_type
     and created_at >= now() - interval '4 hours'
   order by created_at desc
   limit 1
   for update;

  if v_existing.id is not null then

    -- El creador intenta reportar su propio evento de nuevo.
    if v_existing.created_by = v_app_user.id then
      return jsonb_build_object(
        'status_code', 'ALREADY_REPORTED',
        'event_id',    v_existing.id,
        'message',     'Ya registraste un evento similar hace menos de 4 horas.'
      );
    end if;

    -- Otro usuario: auto-validar el evento existente (mismo contrato que
    -- validate_water_event, pero inline para mantener la atomicidad).
    insert into public.water_event_validations (water_event_id, user_id)
    values (v_existing.id, v_app_user.id)
    on conflict (water_event_id, user_id) do nothing
    returning id into v_inserted;

    if v_inserted is null then
      -- El usuario ya había confirmado este evento.
      return jsonb_build_object(
        'status_code', 'ALREADY_REPORTED',
        'event_id',    v_existing.id,
        'message',     'Ya confirmaste un evento similar.'
      );
    end if;

    update public.water_events
       set validation_count = validation_count + 1
     where id = v_existing.id
    returning validation_count into v_count;

    insert into public.audit_events
      (user_id, event_type, entity_type, entity_id, metadata)
    values
      (v_auth_uid, 'WATER_EVENT_VALIDATED', 'water_event', v_existing.id,
       jsonb_build_object('auto_confirmed', true, 'validation_count', v_count));

    return jsonb_build_object(
      'status_code',      'CONFIRMED',
      'event_id',         v_existing.id,
      'event_type',       v_existing.event_type,
      'event_time',       v_existing.event_time,
      'created_at',       v_existing.created_at,
      'validation_count', v_count
    );
  end if;

  -- ---------- 8. Insert (sin duplicado reciente) ----------
  insert into public.water_events
    (created_by, municipality_id, sector_id, event_type, event_time, comment, address)
  values
    (v_app_user.id, p_municipality_id, p_sector_id, p_event_type,
     p_event_time, v_comment, v_address)
  returning * into v_event;

  -- ---------- 9. Auditoría (REQ-093) ----------
  insert into public.audit_events
    (user_id, event_type, entity_type, entity_id, metadata)
  values
    (v_auth_uid, 'WATER_EVENT_CREATED', 'water_event', v_event.id,
     jsonb_build_object('event_type', v_event.event_type));

  return jsonb_build_object(
    'status_code', 'CREATED',
    'event_id',    v_event.id,
    'event_type',  v_event.event_type,
    'event_time',  v_event.event_time,
    'created_at',  v_event.created_at
  );
end;
$$;

revoke execute on function public.register_water_event(uuid, uuid, text, timestamptz, text, text)
  from public, anon;
grant execute on function public.register_water_event(uuid, uuid, text, timestamptz, text, text)
  to authenticated;

-- =====================================================================
-- 3. RPC get_water_event_detail (+ address)
-- =====================================================================
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
    'address', v_event.address,
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
