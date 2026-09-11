-- 00002: Tabla municipalities + función set_updated_at (compartida) + trigger.

create table if not exists public.municipalities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  state       text not null,
  country     text not null default 'Venezuela',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Mantiene updated_at al día en municipalities y sectors.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger municipalities_set_updated_at
  before update on public.municipalities
  for each row execute function public.set_updated_at();
