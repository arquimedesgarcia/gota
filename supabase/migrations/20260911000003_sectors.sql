-- 00003: Tabla sectors.

create table if not exists public.sectors (
  id              uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete restrict,
  name            text not null,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (municipality_id, name)
);

create trigger sectors_set_updated_at
  before update on public.sectors
  for each row execute function public.set_updated_at();
