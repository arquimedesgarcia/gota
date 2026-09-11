-- 00007: Tabla reports + índices definidos en docs/DATA_MODEL.md.
-- Solo se crea ACTIVE en Sprint 02 (estado por defecto). RESOLVED existe
-- como estado del modelo; la transición atómica es de un sprint posterior.

create table if not exists public.reports (
  id                            uuid primary key default gen_random_uuid(),
  created_by                    uuid not null
                                references public.app_users(id) on delete cascade,
  municipality_id               uuid not null
                                references public.municipalities(id) on delete restrict,
  sector_id                     uuid not null
                                references public.sectors(id) on delete restrict,
  location                      geography(Point, 4326) not null,
  location_source               text not null
                                check (location_source in ('GPS', 'MANUAL')),
  description                   text
                                check (char_length(description) <= 500),
  status                        text not null default 'ACTIVE'
                                check (status in ('ACTIVE', 'RESOLVED')),
  validation_count              int not null default 0
                                check (validation_count >= 0),
  resolution_confirmation_count int not null default 0
                                check (resolution_confirmation_count >= 0),
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  resolved_at                   timestamptz
);

-- Coherencia estado/resolución: RESOLVED siempre con resolved_at,
-- ACTIVE siempre sin él.
alter table public.reports
  add constraint reports_status_consistency check (
    (status = 'ACTIVE'    and resolved_at is null)
    or
    (status = 'RESOLVED'  and resolved_at is not null)
  );

create trigger reports_set_updated_at
  before update on public.reports
  for each row execute function public.set_updated_at();

-- ---------- Índices (docs/DATA_MODEL.md §3) ----------
create index if not exists reports_location_gix
  on public.reports using gist (location);

create index if not exists reports_status_idx
  on public.reports (status);

create index if not exists reports_sector_idx
  on public.reports (sector_id);

create index if not exists reports_municipality_idx
  on public.reports (municipality_id);

create index if not exists reports_created_at_idx
  on public.reports (created_at desc);

create index if not exists reports_created_by_idx
  on public.reports (created_by);
