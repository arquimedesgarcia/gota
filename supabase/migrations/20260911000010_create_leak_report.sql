-- 00010: RPC create_leak_report — operación crítica definida en
-- docs/API_SPEC.md §2 (create-leak-report). Se ejecuta como
-- security definer; ningún cliente escribe en `reports` directamente.
--
-- Validaciones server-side (no se confía solo en el cliente):
--  * sesión anónima válida y no bloqueada;
--  * municipio activo y sector activo que pertenezca a ese municipio;
--  * ubicación válida (rango y fuente GPS/MANUAL);
--  * fotos: cantidad, formato (MIME), tamaño y pertenencia, verificados
--    contra `storage.objects` y contra `system_config.photo_limits`;
--  * duplicados: reportes ACTIVE a ≤50 m creados en ≤48 h (configurable).
--
-- Estados de salida (jsonb `status_code`):
--   CREATED / POSSIBLE_DUPLICATE / UNAUTHORIZED / FORBIDDEN /
--   VALIDATION_ERROR / INVALID_LOCATION / INVALID_SECTOR / STORAGE_ERROR
--
-- `p_ignore_duplicate = true` es la confirmación explícita del usuario
-- tras revisar el candidato (docs/REQUIREMENTS.md REQ-025); sin ella el
-- posible duplicado no se crea.

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

  -- ---------- 5. Validación y normalización de fotos ----------
  -- Cada foto se comprueba contra el binario realmente almacenado:
  -- pertenencia (ruta del propio usuario), MIME y tamaño.
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

    -- Los metadatos del binario mandan: no se guarda lo que declare el
    -- cliente si contradice a Storage.
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

  -- REQ-025: el candidato no bloquea; el usuario decide. Solo se crea si
  -- confirmó explícitamente "es otra fuga".
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
