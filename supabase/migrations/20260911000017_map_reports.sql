-- 00017: RPC pública get_map_reports para Sprint 05 (Map).
-- Devuelve exclusivamente el DTO público necesario para pintar markers y listar
-- fugas geolocalizadas, respetando estrictamente la privacidad (REQ-100: sin
-- created_by, emails, teléfonos ni metadatos privados).
--
-- Aprovecha el índice espacial GIST `reports_location_gix` ante filtros de
-- bounding box y aplica límites estrictos para prevenir descargas masivas.

create or replace function public.get_map_reports(
  p_status text default null,
  p_sector_id uuid default null,
  p_min_lat double precision default null,
  p_min_lng double precision default null,
  p_max_lat double precision default null,
  p_max_lng double precision default null,
  p_order_by text default 'recent',
  p_limit int default 100
)
returns table (
  id uuid,
  status text,
  latitude double precision,
  longitude double precision,
  validation_count int,
  resolution_confirmation_count int,
  created_at timestamptz,
  resolved_at timestamptz,
  description text,
  sector_id uuid,
  sector_name text,
  municipality_id uuid,
  municipality_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit int;
begin
  -- Control de estado válido si se especifica
  if p_status is not null and p_status not in ('ACTIVE', 'RESOLVED') then
    raise exception 'INVALID_STATUS';
  end if;

  -- Límite acotado entre 1 y 200 (defensa contra descarga indiscriminada)
  v_limit := least(greatest(coalesce(p_limit, 100), 1), 200);

  return query
  select
    r.id,
    r.status,
    extensions.st_y(r.location::extensions.geometry) as latitude,
    extensions.st_x(r.location::extensions.geometry) as longitude,
    r.validation_count,
    r.resolution_confirmation_count,
    r.created_at,
    r.resolved_at,
    r.description,
    r.sector_id,
    s.name as sector_name,
    r.municipality_id,
    m.name as municipality_name
  from public.reports r
  join public.sectors s on s.id = r.sector_id
  join public.municipalities m on m.id = r.municipality_id
  where
    (p_status is null or r.status = p_status)
    and (p_sector_id is null or r.sector_id = p_sector_id)
    and (
      p_min_lat is null or p_min_lng is null or p_max_lat is null or p_max_lng is null
      or extensions.st_intersects(
        r.location::extensions.geometry,
        extensions.st_makeenvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)
      )
    )
  order by
    case when p_order_by = 'validated' then r.validation_count end desc nulls last,
    r.created_at desc
  limit v_limit;
end;
$$;

revoke execute on function public.get_map_reports(text, uuid, double precision, double precision, double precision, double precision, text, int)
  from public;

grant execute on function public.get_map_reports(text, uuid, double precision, double precision, double precision, double precision, text, int)
  to anon, authenticated;
