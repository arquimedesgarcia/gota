-- 00033: RPC get_report_photos — lectura pública de fotos por signed URL
--
-- Parte del diseño aprobado en docs/PROMPT_12_FOTOS_COMUNITARIAS_2026-09-25.md:
-- cualquier usuario autenticado puede ver las fotos de un reporte a través de
-- esta RPC. El cliente NUNCA recibe storage_path ni thumbnail_path crudos; solo
-- signed URLs temporales (TTL 900 s, ~15 min).
--
-- Seguridad:
--  * SECURITY DEFINER + search_path fijo.
--  * REVOKE EXECUTE FROM anon; GRANT TO authenticated.
--  * Verifica existencia del reporte (NOT_FOUND).
--  * Verifica que el llamador no esté bloqueado (FORBIDDEN).
--  * Rate limit con los helpers existentes (mismo patrón que validate_leak).
--  * NO concede SELECT sobre report_photos: esta RPC es el único camino.
--
-- Thumbnails: si thumbnail_path es NULL, thumbnail_url es null en la respuesta.
-- Fotos de reportes RESOLVED: se devuelven igual (histórico).
--
-- Nota sobre rate_limit_tracking: el CHECK constraint de operation_type en
-- 00021 se extiende aquí para incluir 'get_report_photos'.

-- =====================================================================
-- 1. Extender rate_limit_tracking para admitir 'get_report_photos'
-- =====================================================================
alter table public.rate_limit_tracking
  drop constraint if exists rate_limit_tracking_operation_type_check;

alter table public.rate_limit_tracking
  add constraint rate_limit_tracking_operation_type_check
  check (operation_type in (
    'create_leak_report',
    'validate_leak',
    'confirm_leak_resolution',
    'register_water_event',
    'validate_water_event',
    'get_report_photos'
  ));

-- =====================================================================
-- 2. Configurar límite de tasa para get_report_photos
-- =====================================================================
-- Lectura: límite más amplio que las escrituras (60 lecturas/hora).
update public.system_config
   set value = value || '{"get_report_photos": 60}'::jsonb,
       updated_at = now()
 where key = 'rate_limits';

-- =====================================================================
-- 3. RPC get_report_photos
-- =====================================================================
create or replace function public.get_report_photos(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_auth_uid   uuid;
  v_app_user   public.app_users;
  v_report_id  uuid;
  v_rate_check jsonb;
  v_photos     jsonb;
  v_photo      record;
  v_url        text;
  v_thumb_url  text;
begin
  -- ---------- 1. Autenticación ----------
  v_auth_uid := auth.uid();
  if v_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user
    from public.app_users
   where auth_user_id = v_auth_uid;

  if v_app_user.id is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  -- ---------- 2. Bloqueado ----------
  if v_app_user.is_blocked then
    return jsonb_build_object(
      'status_code', 'FORBIDDEN',
      'message', 'Tu acceso está bloqueado.'
    );
  end if;

  -- ---------- 3. Rate limit ----------
  v_rate_check := public.check_rate_limit(v_app_user.id, 'get_report_photos');
  if not (v_rate_check->>'allowed')::boolean then
    return jsonb_build_object(
      'status_code', 'RATE_LIMIT_EXCEEDED',
      'message', 'Demasiadas solicitudes de fotos. Espera un momento.',
      'reset_at', v_rate_check->>'reset_at'
    );
  end if;

  -- ---------- 4. Existencia del reporte ----------
  select id into v_report_id
    from public.reports
   where id = p_report_id;

  if v_report_id is null then
    return jsonb_build_object(
      'status_code', 'NOT_FOUND',
      'message', 'No encontramos este reporte.'
    );
  end if;

  -- ---------- 5. Signed URLs por foto (orden sort_order) ----------
  -- NUNCA devuelve storage_path ni thumbnail_path crudos.
  -- storage.create_signed_url devuelve la URL completa en Supabase Cloud.
  v_photos := '[]'::jsonb;

  for v_photo in
    select id, sort_order, width, height, storage_path, thumbnail_path
      from public.report_photos
     where report_id = p_report_id
     order by sort_order
  loop
    -- URL principal (siempre presente).
    v_url := storage.create_signed_url('report-photos', v_photo.storage_path, 900);

    -- URL de miniatura (solo si thumbnail_path no es NULL).
    if v_photo.thumbnail_path is not null then
      v_thumb_url := storage.create_signed_url('report-photos', v_photo.thumbnail_path, 900);
    else
      v_thumb_url := null;
    end if;

    v_photos := v_photos || jsonb_build_array(jsonb_build_object(
      'id',            v_photo.id,
      'sort_order',    v_photo.sort_order,
      'width',         v_photo.width,
      'height',        v_photo.height,
      'url',           v_url,
      'thumbnail_url', v_thumb_url
    ));
  end loop;

  return jsonb_build_object(
    'status_code', 'OK',
    'photos', v_photos
  );
end;
$$;

revoke execute on function public.get_report_photos(uuid) from public, anon;
grant  execute on function public.get_report_photos(uuid) to authenticated;
