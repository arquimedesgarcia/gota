-- 00024: Rate Limiting RPC Updates (Sprint 07).
--
-- Actualiza los 5 RPCs críticos para incluir check de rate limiting.
-- Método: inline del check atomicamente dentro de cada RPC.
-- No utiliza funciones helper para asegurar transacción completa.

-- =====================================================================
-- 1. Helper inline: obtener límite y realizar check
-- =====================================================================
-- Esta se define como una función para reutilizarse, pero puede inlinearse
-- si es necesario. Permanece como helper para claridad.

create or replace function public.check_rate_limit_inline(
  p_user_id uuid,
  p_operation text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit          int;
  v_window_start   timestamptz;
  v_count          int;
  v_allowed        boolean;
begin
  -- Límite configurado o default
  v_limit := greatest(
    coalesce(
      (select (value->>(p_operation))::int
         from public.system_config
        where key = 'rate_limits'),
      case p_operation
        when 'create_leak_report' then 3
        when 'validate_leak' then 20
        when 'confirm_leak_resolution' then 10
        when 'register_water_event' then 5
        when 'validate_water_event' then 20
        else 1
      end
    ),
    1
  );

  v_window_start := date_trunc('hour', now());

  -- Upsert atómico
  insert into public.rate_limit_tracking
    (user_id, operation_type, window_start, count)
  values
    (p_user_id, p_operation, v_window_start, 1)
  on conflict (user_id, operation_type, window_start)
  do update
     set count = rate_limit_tracking.count + 1
  returning count into v_count;

  v_allowed := (v_count <= v_limit);

  return jsonb_build_object(
    'allowed', v_allowed,
    'count', v_count,
    'limit', v_limit,
    'reset_at', v_window_start + interval '1 hour'
  );
end;
$$;

revoke execute on function public.check_rate_limit_inline(uuid, text) from public, anon;
grant execute on function public.check_rate_limit_inline(uuid, text) to authenticated;

-- =====================================================================
-- 2. Update create_leak_report
-- =====================================================================
create or replace function public.create_leak_report(
  p_municipality_id uuid,
  p_sector_id       uuid,
  p_latitude        double precision,
  p_longitude       double precision,
  p_location_source text,
  p_description     text default null,
  p_photos          jsonb default '[]'::jsonb,
  p_ignore_duplicate boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app_user      public.app_users;
  v_auth_uid      uuid;
  v_sector        public.sectors;
  v_radius_m      int;
  v_window_hours  int;
  v_count_max     int;
  v_max_bytes     bigint;
  v_mime_allowed  text[];
  v_point         extensions.geography(Point, 4326);
  v_candidates    jsonb;
  v_report_id     uuid;
  v_photo         jsonb;
  v_path          text;
  v_sort          int;
  v_seen_sorts    int[] := '{}';
  v_mime          text;
  v_size          bigint;
  v_photos_valid  jsonb := '[]'::jsonb;
  v_thumb         text;
  v_width         int;
  v_height        int;
  v_created_at    timestamptz;
  v_idx           int;
  v_rate_check    jsonb;
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

  if p_location_source not in ('GPS', 'MANUAL') then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
      'message', 'La fuente de ubicación no es válida.');
  end if;

  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180
  then
    return jsonb_build_object('status_code', 'INVALID_LOCATION',
      'message', 'La ubicación está fuera de rango.');
  end if;

  if jsonb_typeof(p_photos) <> 'array' then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
      'message', 'Las fotos no son una lista válida.');
  end if;

  select * into v_sector from public.sectors
    where id = p_sector_id and is_active = true;
  if v_sector.id is null then
    return jsonb_build_object('status_code', 'INVALID_SECTOR',
      'message', 'El sector no existe o no está activo.');
  end if;
  if v_sector.municipality_id <> p_municipality_id then
    return jsonb_build_object('status_code', 'INVALID_SECTOR',
      'message', 'El sector no pertenece al municipio indicado.');
  end if;

  if not exists (
    select 1 from public.municipalities
    where id = p_municipality_id and is_active = true
  ) then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
      'message', 'El municipio no existe o no está activo.');
  end if;

  v_point := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude), 4326
  )::extensions.geography;

  select (value->>'max_count')::int,
         (value->>'max_bytes')::bigint
    into v_count_max, v_max_bytes
    from public.system_config where key = 'photo_limits';
  if v_count_max is null then v_count_max := 3; end if;
  if v_max_bytes is null then v_max_bytes := 10485760; end if;

  select coalesce(
           array(select jsonb_array_elements_text(value->'allowed_mime_types')),
           array['image/jpeg', 'image/png', 'image/webp']
         )
    into v_mime_allowed
    from public.system_config where key = 'photo_limits';
  if v_mime_allowed is null or cardinality(v_mime_allowed) = 0 then
    v_mime_allowed := array['image/jpeg', 'image/png', 'image/webp'];
  end if;

  if jsonb_array_length(p_photos) < 1
     or jsonb_array_length(p_photos) > v_count_max
  then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
      'message',
      format('La cantidad de fotos debe ser entre 1 y %s.', v_count_max));
  end if;

  for v_idx in 0 .. (jsonb_array_length(p_photos) - 1) loop
    v_photo := p_photos -> v_idx;
    v_path  := v_photo->>'storage_path';

    if v_path is null or btrim(v_path) = '' then
      return jsonb_build_object('status_code', 'VALIDATION_ERROR',
        'message', 'Una de las fotos no tiene referencia de almacenamiento.');
    end if;

    if v_path not like 'report_photos/' || v_auth_uid::text || '/%' then
      return jsonb_build_object('status_code', 'VALIDATION_ERROR',
        'message', 'Una de las fotos no pertenece a tu sesión.');
    end if;

    if exists (
      select 1 from public.report_photos rp
      where rp.storage_path = v_path
    ) then
      return jsonb_build_object('status_code', 'VALIDATION_ERROR',
        'message', 'Una de las fotos ya está asociada a un reporte.');
    end if;

    select (o.metadata->>'mimetype'),
           (o.metadata->>'size')::bigint
      into v_mime, v_size
      from storage.objects o
     where o.bucket_id = 'report-photos'
       and o.name = v_path
       and coalesce(o.owner_id, o.owner::text) = v_auth_uid::text
     limit 1;

    if not found then
      return jsonb_build_object('status_code', 'STORAGE_ERROR',
        'message', 'No encontramos una de las fotos subidas. Intenta de nuevo.');
    end if;

    if v_mime is null or not (v_mime = any (v_mime_allowed)) then
      return jsonb_build_object('status_code', 'VALIDATION_ERROR',
        'message', format('Formato de foto no permitido (%s). Use JPG, PNG o WebP.',
                          coalesce(v_mime, 'desconocido')));
    end if;

    if v_size is null or v_size <= 0 or v_size > v_max_bytes then
      return jsonb_build_object('status_code', 'VALIDATION_ERROR',
        'message', format('Cada foto debe pesar como máximo %s MB.',
                          (v_max_bytes / 1048576)));
    end if;

    v_sort := coalesce((v_photo->>'sort_order')::int, v_idx + 1);
    if v_sort < 1 or v_sort > v_count_max or v_sort = any (v_seen_sorts) then
      return jsonb_build_object('status_code', 'VALIDATION_ERROR',
        'message', 'El orden de las fotos no es válido.');
    end if;
    v_seen_sorts := v_seen_sorts || v_sort;

    v_thumb  := v_photo->>'thumbnail_path';
    v_width  := (v_photo->>'width')::int;
    v_height := (v_photo->>'height')::int;

    v_photos_valid := v_photos_valid || jsonb_build_object(
      'storage_path',   v_path,
      'thumbnail_path', v_thumb,
      'mime_type',      v_mime,
      'size_bytes',     v_size,
      'width',          case when v_width  > 0 then v_width  end,
      'height',         case when v_height > 0 then v_height end,
      'sort_order',     v_sort
    );
  end loop;

  select (value->>'radius_meters')::int into v_radius_m
    from public.system_config where key = 'duplicate_detection';
  if v_radius_m is null then v_radius_m := 50; end if;

  select (value->>'window_hours')::int into v_window_hours
    from public.system_config where key = 'duplicate_detection';
  if v_window_hours is null then v_window_hours := 48; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'sector_id', r.sector_id,
    'distance_meters', round(r.distance)::int,
    'created_at', r.created_at
  ) order by r.distance), '[]'::jsonb)
  into v_candidates
  from (
    select r.id, r.sector_id, r.created_at,
           extensions.st_distance(r.location, v_point) as distance
    from public.reports r
    where r.status = 'ACTIVE'
      and r.created_at >= now() - make_interval(hours => v_window_hours)
      and extensions.st_dwithin(r.location, v_point, v_radius_m)
    limit 5
  ) r;

  if v_candidates <> '[]'::jsonb and not coalesce(p_ignore_duplicate, false) then
    return jsonb_build_object('status_code', 'POSSIBLE_DUPLICATE',
                              'candidates', v_candidates);
  end if;

  v_rate_check := public.check_rate_limit_inline(v_app_user.id, 'create_leak_report');
  if not (v_rate_check->>'allowed')::boolean then
    return jsonb_build_object(
      'status_code', 'RATE_LIMIT_EXCEEDED',
      'message', 'Has alcanzado el límite de reportes por hora.',
      'reset_at', v_rate_check->>'reset_at'
    );
  end if;

  insert into public.reports
    (created_by, municipality_id, sector_id, location,
     location_source, description, status)
  values
    (v_app_user.id, p_municipality_id, v_sector.id, v_point,
     p_location_source,
     nullif(trim(p_description), ''),
     'ACTIVE')
  returning id, updated_at into v_report_id, v_created_at;

  for v_photo in select * from jsonb_array_elements(v_photos_valid) loop
    insert into public.report_photos
      (report_id, storage_path, thumbnail_path, mime_type,
       size_bytes, width, height, sort_order)
    values
      (v_report_id,
       v_photo->>'storage_path',
       v_photo->>'thumbnail_path',
       v_photo->>'mime_type',
       (v_photo->>'size_bytes')::bigint,
       (v_photo->>'width')::int,
       (v_photo->>'height')::int,
       (v_photo->>'sort_order')::int);
  end loop;

  insert into public.audit_events (user_id, event_type, entity_type, entity_id)
  values (v_auth_uid, 'REPORT_CREATED', 'report', v_report_id);

  return jsonb_build_object(
    'status_code', 'CREATED',
    'report_id',   v_report_id,
    'status',      'ACTIVE',
    'created_at',  v_created_at
  );
end;
$$;

revoke execute on function public.create_leak_report(uuid, uuid,
  double precision, double precision, text, text, jsonb, boolean)
  from public, anon;
grant execute on function public.create_leak_report(uuid, uuid,
  double precision, double precision, text, text, jsonb, boolean)
  to authenticated;

-- =====================================================================
-- 3. Update validate_leak
-- =====================================================================
create or replace function public.validate_leak(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid uuid;
  v_app_user public.app_users;
  v_report   public.reports;
  v_inserted uuid;
  v_count    int;
  v_rate_check jsonb;
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

  select * into v_report from public.reports
    where id = p_report_id
    for update;

  if v_report.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos esta fuga.');
  end if;

  if v_report.status <> 'ACTIVE' then
    return jsonb_build_object(
      'status_code', 'REPORT_ALREADY_RESOLVED',
      'message', 'Esta fuga ya fue reportada como resuelta por la comunidad.',
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at
    );
  end if;

  if v_report.created_by = v_app_user.id then
    return jsonb_build_object('status_code', 'FORBIDDEN',
      'message', 'No puedes validar tu propio reporte.');
  end if;

  v_rate_check := public.check_rate_limit_inline(v_app_user.id, 'validate_leak');
  if not (v_rate_check->>'allowed')::boolean then
    return jsonb_build_object(
      'status_code', 'RATE_LIMIT_EXCEEDED',
      'message', 'Has alcanzado el límite de validaciones por hora.',
      'reset_at', v_rate_check->>'reset_at'
    );
  end if;

  insert into public.report_validations (report_id, user_id)
  values (p_report_id, v_app_user.id)
  on conflict (report_id, user_id) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'status_code', 'DUPLICATE_ACTION',
      'message', 'Ya validaste este reporte.',
      'already_validated', true,
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at,
      'threshold', public.resolution_threshold()
    );
  end if;

  update public.reports
     set validation_count = validation_count + 1
   where id = p_report_id
     and status = 'ACTIVE'
  returning validation_count into v_count;

  if v_count is null then
    raise exception 'validation_count no pudo actualizarse para %', p_report_id
      using errcode = 'P0001';
  end if;

  insert into public.audit_events
    (user_id, event_type, entity_type, entity_id, metadata)
  values
    (v_auth_uid, 'REPORT_VALIDATED', 'report', p_report_id,
     jsonb_build_object('validation_count', v_count));

  return jsonb_build_object(
    'status_code', 'VALIDATED',
    'already_validated', false,
    'status', v_report.status,
    'validation_count', v_count,
    'resolution_confirmation_count', v_report.resolution_confirmation_count,
    'resolved_at', v_report.resolved_at,
    'threshold', public.resolution_threshold()
  );
end;
$$;

revoke execute on function public.validate_leak(uuid) from public, anon;
grant execute on function public.validate_leak(uuid) to authenticated;

-- =====================================================================
-- 4. Update confirm_leak_resolution
-- =====================================================================
create or replace function public.confirm_leak_resolution(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid     uuid;
  v_app_user     public.app_users;
  v_report       public.reports;
  v_inserted     uuid;
  v_threshold    int;
  v_count        int;
  v_status       text;
  v_resolved_at  timestamptz;
  v_rate_check   jsonb;
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

  select * into v_report from public.reports
    where id = p_report_id
    for update;

  if v_report.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos esta fuga.');
  end if;

  if v_report.status <> 'ACTIVE' then
    return jsonb_build_object(
      'status_code', 'REPORT_ALREADY_RESOLVED',
      'message', 'Esta fuga ya fue marcada como resuelta.',
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at
    );
  end if;

  v_rate_check := public.check_rate_limit_inline(v_app_user.id, 'confirm_leak_resolution');
  if not (v_rate_check->>'allowed')::boolean then
    return jsonb_build_object(
      'status_code', 'RATE_LIMIT_EXCEEDED',
      'message', 'Has alcanzado el límite de confirmaciones por hora.',
      'reset_at', v_rate_check->>'reset_at'
    );
  end if;

  insert into public.resolution_confirmations (report_id, user_id)
  values (p_report_id, v_app_user.id)
  on conflict (report_id, user_id) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'status_code', 'DUPLICATE_ACTION',
      'message', 'Ya confirmaste la resolución de esta fuga.',
      'already_confirmed', true,
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at,
      'threshold', public.resolution_threshold()
    );
  end if;

  v_threshold := public.resolution_threshold();

  update public.reports
     set resolution_confirmation_count = resolution_confirmation_count + 1,
         status = case
                    when resolution_confirmation_count + 1 >= v_threshold
                    then 'RESOLVED'
                    else status
                  end,
         resolved_at = case
                         when resolution_confirmation_count + 1 >= v_threshold
                         then now()
                         else resolved_at
                       end
   where id = p_report_id
     and status = 'ACTIVE'
  returning resolution_confirmation_count, status, resolved_at
    into v_count, v_status, v_resolved_at;

  if v_count is null then
    raise exception 'resolution_confirmation_count no pudo actualizarse para %',
      p_report_id using errcode = 'P0001';
  end if;

  insert into public.audit_events
    (user_id, event_type, entity_type, entity_id, metadata)
  values
    (v_auth_uid, 'RESOLUTION_CONFIRMED', 'report', p_report_id,
     jsonb_build_object('resolution_confirmation_count', v_count,
                        'threshold', v_threshold));

  if v_status = 'RESOLVED' then
    insert into public.audit_events
      (user_id, event_type, entity_type, entity_id, metadata)
    values
      (v_auth_uid, 'REPORT_RESOLVED', 'report', p_report_id,
       jsonb_build_object('resolution_confirmation_count', v_count,
                          'threshold', v_threshold));
  end if;

  return jsonb_build_object(
    'status_code', case when v_status = 'RESOLVED' then 'RESOLVED'
                        else 'CONFIRMED' end,
    'already_confirmed', false,
    'status', v_status,
    'validation_count', v_report.validation_count,
    'resolution_confirmation_count', v_count,
    'resolved_at', v_resolved_at,
    'threshold', v_threshold
  );
end;
$$;

revoke execute on function public.confirm_leak_resolution(uuid)
  from public, anon;
grant execute on function public.confirm_leak_resolution(uuid)
  to authenticated;

-- =====================================================================
-- 5. Update register_water_event
-- =====================================================================
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
  v_rate_check   jsonb;
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

  select * into v_municipality from public.municipalities
    where id = p_municipality_id;
  if v_municipality.id is null or not v_municipality.is_active then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos este municipio.');
  end if;

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

  if p_event_type not in ('WATER_ARRIVED', 'WATER_LEFT') then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'Tipo de evento no válido.');
  end if;

  if p_event_time is null then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'Indica la hora del evento.');
  end if;
  if p_event_time > now() then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'La hora del evento no puede estar en el futuro.');
  end if;

  v_comment := nullif(trim(p_comment), '');
  if v_comment is not null and char_length(v_comment) > 500 then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
                              'message', 'El comentario no puede superar 500 caracteres.');
  end if;

  v_rate_check := public.check_rate_limit_inline(v_app_user.id, 'register_water_event');
  if not (v_rate_check->>'allowed')::boolean then
    return jsonb_build_object(
      'status_code', 'RATE_LIMIT_EXCEEDED',
      'message', 'Has alcanzado el límite de eventos de agua por hora.',
      'reset_at', v_rate_check->>'reset_at'
    );
  end if;

  insert into public.water_events
    (created_by, municipality_id, sector_id, event_type, event_time, comment)
  values
    (v_app_user.id, p_municipality_id, p_sector_id, p_event_type,
     p_event_time, v_comment)
  returning * into v_event;

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
-- 6. Update validate_water_event
-- =====================================================================
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
  v_rate_check jsonb;
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

  select * into v_event from public.water_events
    where id = p_water_event_id
    for update;

  if v_event.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos este evento.');
  end if;

  if v_event.created_by = v_app_user.id then
    return jsonb_build_object('status_code', 'FORBIDDEN',
      'message', 'No puedes validar tu propio evento.');
  end if;

  v_rate_check := public.check_rate_limit_inline(v_app_user.id, 'validate_water_event');
  if not (v_rate_check->>'allowed')::boolean then
    return jsonb_build_object(
      'status_code', 'RATE_LIMIT_EXCEEDED',
      'message', 'Has alcanzado el límite de validaciones de eventos por hora.',
      'reset_at', v_rate_check->>'reset_at'
    );
  end if;

  insert into public.water_event_validations (water_event_id, user_id)
  values (p_water_event_id, v_app_user.id)
  on conflict (water_event_id, user_id) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'status_code', 'DUPLICATE_ACTION',
      'message', 'Ya validaste este evento.',
      'already_validated', true,
      'validation_count', v_event.validation_count
    );
  end if;

  update public.water_events
     set validation_count = validation_count + 1
   where id = p_water_event_id
  returning validation_count into v_count;

  if v_count is null then
    raise exception 'validation_count no pudo actualizarse para %',
      p_water_event_id using errcode = 'P0001';
  end if;

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
