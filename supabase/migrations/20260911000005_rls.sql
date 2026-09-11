-- 00005: RLS y permisos sobre municipalities, sectors y app_users.

alter table public.municipalities enable row level security;
alter table public.sectors enable row level security;
alter table public.app_users enable row level security;

-- ---------- municipalities ----------
create policy "Lectura pública de municipios activos"
  on public.municipalities for select
  to anon, authenticated
  using (is_active = true);

-- ---------- sectors ----------
create policy "Lectura pública de sectores activos"
  on public.sectors for select
  to anon, authenticated
  using (is_active = true);

-- ---------- app_users (sin lectura pública) ----------
create policy "Usuario lee su propio perfil"
  on public.app_users for select
  to authenticated
  using (auth_user_id = auth.uid());

create policy "Usuario crea su propio perfil"
  on public.app_users for insert
  to authenticated
  with check (auth_user_id = auth.uid());

-- Solo el propietario puede actualizar, y únicamente last_seen_at
-- (la actualización de otras columnas queda bloqueada por el GRANT de columna).
create policy "Usuario actualiza su propio perfil"
  on public.app_users for update
  to authenticated
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- ---------- Permisos explícitos (sin privilegios amplios) ----------
-- municipalities / sectors: solo lectura para anon y authenticated.
revoke all on public.municipalities from anon, authenticated;
grant select on public.municipalities to anon, authenticated;

revoke all on public.sectors from anon, authenticated;
grant select on public.sectors to anon, authenticated;

-- app_users: nada para anon; para authenticated, lectura/insert de su fila
-- y update solo de la columna last_seen_at.
revoke all on public.app_users from anon, authenticated;
grant select, insert on public.app_users to authenticated;
grant update (last_seen_at) on public.app_users to authenticated;

-- ensure_app_user: solo usuarios autenticados.
revoke execute on function public.ensure_app_user() from public;
revoke execute on function public.ensure_app_user() from anon;
grant execute on function public.ensure_app_user() to authenticated;
