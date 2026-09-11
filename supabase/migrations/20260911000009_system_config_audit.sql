-- 00009: system_config (configuración de negocio) y audit_events.
-- Semillas según docs/DATA_MODEL.md §4 (duplicados 50 m / 48 h configurables).

create table if not exists public.system_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.system_config (key, value)
values
  (
    'duplicate_detection',
    '{"radius_meters": 50, "window_hours": 48}'::jsonb
  ),
  (
    'photo_limits',
    '{"max_count": 3, "max_bytes": 10485760,
      "allowed_mime_types": ["image/jpeg", "image/png", "image/webp"]}'::jsonb
  )
on conflict (key) do update
  set value      = excluded.value,
      updated_at = now();

create table if not exists public.audit_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid,
  event_type  text not null,
  entity_type text not null,
  entity_id   uuid,
  metadata    jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists audit_events_entity_idx
  on public.audit_events (entity_type, entity_id);

create index if not exists audit_events_created_at_idx
  on public.audit_events (created_at desc);
