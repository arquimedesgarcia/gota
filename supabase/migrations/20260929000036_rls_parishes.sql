-- 00036: Habilitar RLS en parishes (faltaba en la migración 00031).
-- Supabase alertó: rls_disabled_in_public — la tabla era accesible sin RLS.
-- Política: lectura pública (datos de referencia como municipalities/sectors),
-- escritura solo para autenticados (service_role o admin).

alter table public.parishes enable row level security;

create policy "Lectura pública de parroquias activas"
  on public.parishes
  for select
  using (is_active = true);

create policy "Solo autenticados pueden escribir parroquias"
  on public.parishes
  for all
  to authenticated
  using (true)
  with check (true);
