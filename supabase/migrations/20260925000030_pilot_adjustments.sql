-- 00030: Ajustes del piloto (fix/map-r5-r6).
--
-- A1: fotos opcionales — permite 0 fotos en create_leak_report;
--     actualiza system_config.photo_limits.max_count a 2.
-- B2: umbral de resolución piloto = 1.
-- B3: confirm_leak_resolution requiere validation_count >= 1.
-- I:  tabla contact_messages con RLS mínima (solo INSERT desde clientes).

-- =====================================================================
-- A1: photo_limits — max_count 3 → 2, fotos opcionales (mín. 0)
-- =====================================================================
update public.system_config
   set value = '{"max_count": 2, "max_bytes": 10485760,
                  "allowed_mime_types": ["image/jpeg", "image/png", "image/webp"]}'::jsonb,
       updated_at = now()
 where key = 'photo_limits';

-- Actualiza create_leak_report: elimina la restricción de mínimo 1 foto.
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
begin
  -- ---------- 1. Autenticación ----------
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

  -- ---------- 2. Validaciones básicas ----------
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

  -- ---------- 3. Sector + relación municipio/sector ----------
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

  -- ---------- 4. Límites de fotos (system_config.photo_limits) ----------
  select (value->>'max_count')::int,
         (value->>'max_bytes')::bigint
    into v_count_max, v_max_bytes
    from public.system_config where key = 'photo_limits';
  if v_count_max is null then v_count_max := 2; end if;
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

  -- A1: fotos opcionales (0..max_count).
  if jsonb_array_length(p_photos) > v_count_max then
    return jsonb_build_object('status_code', 'VALIDATION_ERROR',
      'message',
      format('Puedes agregar máximo %s fotos.', v_count_max));
  end if;

  -- ---------- 5. Validación y normalización de fotos ----------
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

  -- ---------- 6. Detección de duplicados (50 m / 48 h configurables) ----------
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

  -- ---------- 7. Creación (ACTIVE) ----------
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

  -- ---------- 8. Auditoría ----------
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
-- B2: umbral de resolución piloto = 1
-- =====================================================================
update public.system_config
   set value = '{"threshold": 1}'::jsonb,
       updated_at = now()
 where key = 'resolution';

-- =====================================================================
-- B3: confirm_leak_resolution requiere validation_count >= 1
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

  -- ---------- 2. Reporte (fila bloqueada) ----------
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

  -- ---------- B3: la fuga debe estar validada antes de confirmar resolución ----------
  if v_report.validation_count < 1 then
    return jsonb_build_object(
      'status_code', 'FORBIDDEN',
      'message', 'Esta fuga aún no fue confirmada por la comunidad. Valídala primero.',
      'validation_count', v_report.validation_count,
      'threshold', public.resolution_threshold()
    );
  end if;

  -- ---------- 3. Una confirmación por identidad y reporte (REQ-052) ----------
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

  -- ---------- 4. Contador + transición atómica (REQ-053) ----------
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

  -- ---------- 5. Auditoría (REQ-093) ----------
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
-- I: Tabla contact_messages
-- =====================================================================
create table if not exists public.contact_messages (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null check (char_length(trim(nombre)) > 0),
  correo     text check (correo is null or char_length(correo) <= 200),
  telefono   text check (telefono is null or char_length(telefono) <= 30),
  mensaje    text not null check (char_length(trim(mensaje)) > 0
                                  and char_length(mensaje) <= 2000),
  created_at timestamptz not null default now()
);

create index if not exists contact_messages_created_at_idx
  on public.contact_messages (created_at desc);

-- RLS: clientes solo pueden insertar, nunca leer ni modificar.
alter table public.contact_messages enable row level security;

grant insert on public.contact_messages to anon, authenticated;
revoke select, update, delete on public.contact_messages from anon, authenticated;

create policy contact_messages_insert
  on public.contact_messages
  for insert
  to anon, authenticated
  with check (
    char_length(trim(nombre)) > 0
    and char_length(trim(mensaje)) > 0
  );
