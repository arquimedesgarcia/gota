-- 00037: Tabla report_abuse_flags — denuncias de contenido inapropiado (requisito UGC de Google Play).
-- RLS: solo inserts para usuarios autenticados; selects solo para service_role.

create table if not exists public.report_abuse_flags (
  id               uuid primary key default gen_random_uuid(),
  report_id        uuid not null references public.reports(id) on delete cascade,
  reporter_id      uuid not null references public.app_users(id) on delete cascade,
  reason           text not null
                   check (reason in ('false_info', 'offensive', 'inappropriate_photos', 'other')),
  note             text check (char_length(note) <= 500),
  created_at       timestamptz not null default now(),
  resolved         boolean not null default false
);

alter table public.report_abuse_flags enable row level security;

-- Solo usuarios autenticados pueden insertar (y solo su propio reporter_id)
create policy "auth_insert_abuse_flag"
  on public.report_abuse_flags
  for insert
  to authenticated
  with check (
    reporter_id = (
      select id from public.app_users where auth_user_id = auth.uid()
    )
  );

-- Solo service_role puede leer (para revisión del desarrollador)
create policy "service_select_abuse_flag"
  on public.report_abuse_flags
  for select
  to service_role
  using (true);

revoke all on public.report_abuse_flags from anon, authenticated;
grant insert on public.report_abuse_flags to authenticated;
