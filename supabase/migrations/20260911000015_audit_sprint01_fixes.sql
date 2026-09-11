-- 00015: Correcciones de la auditoría del Sprint 01 (AUD-S1-04/05/06).
-- Aditiva e idempotente; no reescribe migraciones ya aplicadas.

-- ============================================================
-- AUD-S1-04: mínimo privilegio sobre app_users.
-- La fila la crean el trigger handle_new_user y la RPC
-- ensure_app_user (ambas security definer), nunca el cliente.
-- ============================================================

-- Retirar la política de INSERT directo del cliente.
drop policy if exists "Usuario crea su propio perfil"
  on public.app_users;

-- Retirar INSERT del GRANT a authenticated.
revoke insert on public.app_users from authenticated;

-- ============================================================
-- AUD-S1-05: fallar cerrado si postgis no está habilitada.
-- Las migraciones 00007/00010/00013 usan extensions.geography y
-- extensions.st_*; sin PostGIS fallan tarde y de forma confusa.
-- ============================================================
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'postgis') then
    raise exception 'postgis no está habilitada: los tipos geography y las funciones geoespaciales no están disponibles.';
  end if;
end $$;

-- ============================================================
-- AUD-S1-06: ensure_app_user sin auth.uid() no debe insertar
-- ni propagar una violación NOT NULL cruda. Patrón de validate_leak:
-- UNAUTHORIZED controlado (la devolución de un jsonb la maneja el
-- cliente como excepción de dominio con mensaje en español).
-- (drop previo: cambia el tipo de retorno de app_users a jsonb)
drop function if exists public.ensure_app_user();
create or replace function public.ensure_app_user()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user public.app_users;
begin
  if auth.uid() is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED',
        'message', 'Necesitas una sesión válida.');
  end if;

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

  return to_jsonb(v_user);
end;
$$;

-- (la concesión de EXECUTE a authenticated sobrevive al replace)
revoke execute on function public.ensure_app_user() from public;
revoke execute on function public.ensure_app_user() from anon;
