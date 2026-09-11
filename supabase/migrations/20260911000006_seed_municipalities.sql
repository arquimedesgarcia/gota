-- 00006: Seed de municipios (también aplica en producción vía migraciones).
-- UUIDs fijos para que el seed sea idempotente.

insert into public.municipalities (id, name, state, country)
values
  ('00000000-0000-4000-8000-000000000001', 'Maneiro',   'Nueva Esparta', 'Venezuela'),
  ('00000000-0000-4000-8000-000000000002', 'Arismendi', 'Nueva Esparta', 'Venezuela')
on conflict (id) do nothing;

-- PENDIENTE: no se inventan sectores sin una fuente validada.
-- La estructura queda lista para cargar los sectores después.
