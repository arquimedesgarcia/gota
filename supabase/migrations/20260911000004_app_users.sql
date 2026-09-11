-- 00004: Tabla app_users + aprovisionamiento automático desde auth.users.

create table if not exists public.app_users (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid not null unique references auth.users(id) on delete cascade,
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  is_blocked    boolean not null default false
);

-- Provisión automática: crea la fila en app_users al registrarse un usuario.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.app_users (auth_user_id)
  values (new.id)
  on conflict (auth_user_id) do nothing;
  return new;
end;
$$;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Función pública idempotente llamada por el cliente (rpc) al iniciar:
-- crea la fila si falta y siempre actualiza last_seen_at.
-- Devuelve la fila de app_users del usuario autenticado.
create or replace function public.ensure_app_user()
returns public.app_users
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user public.app_users;
begin
  insert into public.app_users (auth_user_id)
  values (auth.uid())
  on conflict (auth_user_id) do nothing
  returning * into v_user;

  if v_user.id is null then
    update public.app_users
    set last_seen_at = now()
    where auth_user_id = auth.uid()
    returning * into v_user;
  end if;

  return v_user;
end;
$$;
