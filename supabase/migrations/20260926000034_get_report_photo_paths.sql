-- 00034: Fix fotos comunitarias — firma correcta de signed URLs.
--
-- Ver docs/PROMPT_15_FIX_FOTOS_SIGNED_URLS_2026-09-26.md.
--
-- La RPC anterior get_report_photos (00033) construía la respuesta con
-- storage.create_signed_url(...), función que NO existe en Supabase: las
-- signed URLs de Storage solo se firman en el servicio storage-api (o vía
-- service_role desde una Edge Function), nunca desde SQL. En tiempo de
-- ejecución esa RPC fallaba y el Detalle de fuga nunca mostraba fotos.
--
-- Diseño corregido (misma privacidad del PROMPT 12):
--   * El gating (auth/bloqueado/existe/rate limit) queda aquí, en una RPC
--     invocable SOLO por el servidor (service_role → Edge Function
--     get-report-photos).
--   * La RPC devuelve rutas crudas (storage_path/thumbnail_path). Es seguro:
--     estas rutas NUNCA salen del servidor; la Edge Function las firma con
--     service_role y solo entrega signed URLs temporales al cliente.
--   * Como la Edge Function corre con service_role, auth.uid() es NULL dentro
--     de la RPC: la identidad la aporta p_auth_uid, ya verificado por la
--     Edge Function contra /auth/v1/user antes de llamar.

-- =====================================================================
-- 1. Eliminar la RPC rota (firma imposible en SQL)
-- =====================================================================
drop function if exists public.get_report_photos(uuid);

-- =====================================================================
-- 2. RPC get_report_photo_paths — solo service_role
-- =====================================================================
create or replace function public.get_report_photo_paths(
  p_auth_uid  uuid,
  p_report_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app_user   public.app_users;
  v_report_id  uuid;
  v_rate_check jsonb;
  v_photos     jsonb;
  v_photo      record;
begin
  -- ---------- 1. Identidad (aportada por la Edge Function) ----------
  if p_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user
    from public.app_users
   where auth_user_id = p_auth_uid;

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

  -- ---------- 5. Rutas crudas (uso server-side; la Edge Function firma) --
  v_photos := '[]'::jsonb;

  for v_photo in
    select id, sort_order, width, height, storage_path, thumbnail_path
      from public.report_photos
     where report_id = p_report_id
     order by sort_order
  loop
    v_photos := v_photos || jsonb_build_array(jsonb_build_object(
      'id',             v_photo.id,
      'sort_order',     v_photo.sort_order,
      'width',          v_photo.width,
      'height',         v_photo.height,
      'storage_path',   v_photo.storage_path,
      'thumbnail_path', v_photo.thumbnail_path
    ));
  end loop;

  return jsonb_build_object(
    'status_code', 'OK',
    'photos', v_photos
  );
end;
$$;

-- Solo el servidor (Edge Function con service_role) puede ejecutarla: la
-- función acepta un p_auth_uid arbitrario, así que jamás debe ser alcanzable
-- por el cliente (permitiría suplantar identidad y leer rutas crudas).
revoke execute on function public.get_report_photo_paths(uuid, uuid)
  from public, anon, authenticated;
grant  execute on function public.get_report_photo_paths(uuid, uuid)
  to service_role;
