-- 00008: Tabla report_photos con límite de 3 fotos por reporte y
-- orden total (unique (report_id, sort_order), sort_order >= 1).

create table if not exists public.report_photos (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid not null
                 references public.reports(id) on delete cascade,
  storage_path   text not null,
  thumbnail_path text,
  mime_type      text not null,
  size_bytes     bigint not null check (size_bytes > 0),
  width          int check (width > 0),
  height         int check (height > 0),
  sort_order     int not null check (sort_order >= 1),
  created_at     timestamptz not null default now(),

  unique (report_id, sort_order),
  -- Refuerza integridad de referencias: cada binario de Storage se
  -- referencia desde un único reporte.
  unique (storage_path)
);

create index if not exists report_photos_report_id_idx
  on public.report_photos (report_id);

create index if not exists report_photos_report_sort_idx
  on public.report_photos (report_id, sort_order);

-- Máximo 3 fotos por reporte. El advisory lock evita una condición de
-- carrera entre inserts concurrentes para un mismo reporte.
create or replace function public.enforce_report_photo_limit()
returns trigger
language plpgsql
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.report_id::text, 0));
  if
    (
      select count(*)
      from public.report_photos
      where report_id = new.report_id
    ) >= 3
  then
    raise exception 'Un reporte no puede tener más de 3 fotos'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger report_photos_limit_trigger
  before insert on public.report_photos
  for each row execute function public.enforce_report_photo_limit();
