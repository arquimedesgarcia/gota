-- 00019: Notificaciones — plataformas soportadas (Sprint 06, post-auditoría).
--
-- Sprint 06 contempla Android e iOS únicamente (sin soporte Web). La
-- migración 00018 admitía 'web' en el CHECK de notification_tokens.platform
-- y en la validación de register_notification_token; se corrige para que
-- la base de datos coincida con el alcance real del sprint. No hay datos
-- existentes que romper: la tabla no contiene tokens 'web'.

alter table public.notification_tokens
  drop constraint if exists notification_tokens_platform_check;

alter table public.notification_tokens
  add constraint notification_tokens_platform_check
  check (platform in ('android', 'ios'));

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
  -- Sprint 06: solo Android e iOS (sin soporte Web).
  if p_platform not in ('android', 'ios') then
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
