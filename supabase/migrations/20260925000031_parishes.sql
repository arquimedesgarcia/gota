-- 00031: Tabla parishes (división político territorial oficial, nivel parroquia).
-- Fuente: HDX/OCHA cod-ab-ven v01 (2025-01-17), datos INE, licencia CC BY-IGO.
-- https://data.humdata.org/dataset/cod-ab-ven
-- La parroquia es un nivel INTERMEDIO entre municipio y sector (los sectores de
-- OpenStreetMap son más finos y no se reemplazan). El sector queda como nivel
-- inferior opcional; no se fuerza relación sector -> parroquia por ahora.

create table if not exists public.parishes (
  id              uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete restrict,
  name            text not null,
  pcode           text not null unique, -- código INE (ej. VE170501)
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (municipality_id, name)
);

create trigger parishes_set_updated_at
  before update on public.parishes
  for each row execute function public.set_updated_at();

-- Parroquias de Nueva Esparta (pilotaje Margarita), desde ven_admin3 del XLSX HDX.
insert into public.parishes (municipality_id, name, pcode)
select m.id, v.name, v.pcode
from (values
  ('Antolín del Campo', 'Capital Antolín del Campo', 'VE170101'),
  ('Arismendi',         'Capital Arismendi',         'VE170201'),
  ('Díaz',              'Capital Díaz',              'VE170301'),
  ('Díaz',              'Zabala',                    'VE170302'),
  ('García',            'Capital García',            'VE170401'),
  ('García',            'Francisco Fajardo',         'VE170402'),
  ('Gómez',             'Capital Gómez',             'VE170501'),
  ('Gómez',             'Bolívar',                   'VE170502'),
  ('Gómez',             'Guevara',                   'VE170503'),
  ('Gómez',             'Matasiete',                 'VE170504'),
  ('Gómez',             'Sucre',                     'VE170505'),
  ('Maneiro',           'Capital Maneiro',           'VE170601'),
  ('Maneiro',           'Aguirre',                   'VE170602'),
  ('Marcano',           'Capital Marcano',           'VE170701'),
  ('Marcano',           'Adrian',                    'VE170702'),
  ('Mariño',            'Capital Mariño',            'VE170801'),
  ('Península de Macanao', 'Capital Península de Macanao', 'VE170901'),
  ('Península de Macanao', 'San Francisco',          'VE170902'),
  ('Tubores',           'Capital Tubores',           'VE171001'),
  ('Tubores',           'Los Barales',               'VE171002'),
  ('Villalba',          'Capital Villalba',          'VE171101'),
  ('Villalba',          'Vicente Fuentes',           'VE171102')
) as v(municipality_name, name, pcode)
join public.municipalities m
  on m.name = v.municipality_name and m.state = 'Nueva Esparta'
on conflict do nothing;
