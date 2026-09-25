-- 00032: unicidad de municipio por (name, state).
-- El seed 010 usa 'on conflict do nothing', pero sin esta restricción el conflicto
-- nunca se dispara y re-ejecutar el seed duplica municipios (ocurrió en el cloud
-- piloto el 2026-09-25). Imprescindible aplicarla ANTES de re-ejecutar seeds.
create unique index if not exists municipalities_name_state_key
  on public.municipalities (name, state);
