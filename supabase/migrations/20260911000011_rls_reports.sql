-- 00011: RLS para reports, report_photos, system_config y audit_events.
-- Alcance según docs/DATA_MODEL.md §6 y docs/API_SPEC.md:
--
-- reports:
--  * lectura pública de reportes (el alcance MVP pinta mapa/lista);
--  * identidad del creador nunca se expone vía columnas de identidad
--    (created_by es un UUID de app_users, no un dato personal);
--  * escritura NULA para clientes: toda creación pasa por la RPC
--    create_leak_report (security definer), cumple req-043/REQ-043 y el
--    flujo de duplicados. Sprint 03 añadirá validate/confirm atómicos.

alter table public.reports enable row level security;
alter table public.report_photos enable row level security;
alter table public.audit_events enable row level security;

-- ---------- reports (lectura pública, escritura cero) ----------
create policy "Lectura pública de reportes"
  on public.reports for select
  to anon, authenticated
  using (true);

-- Sin políticas insert/update/delete: chars denegados por defecto.
-- GRANT explícito solo select.
revoke all on public.reports from anon, authenticated;
grant select on public.reports to anon, authenticated;

-- ---------- report_photos (lectura pública, escritura cero) ----------
create policy "Lectura pública de fotos de reportes"
  on public.report_photos for select
  to anon, authenticated
  using (true);

revoke all on public.report_photos from anon, authenticated;
grant select on public.report_photos to anon, authenticated;

-- ---------- audit_events (solo escritura por security definer) ----------
create policy "Sin lectura pública de auditoría"
  on public.audit_events for select
  to anon, authenticated
  using (false);

revoke all on public.audit_events from anon, authenticated;

-- system_config: solo configuración no sensible en formato clave/valor
-- jsonb; la lectura es necesaria para que el cliente muestre límites.
create policy "Lectura pública de system_config"
  on public.system_config for select
  to anon, authenticated
  using (true);

revoke all on public.system_config from anon, authenticated;
grant select on public.system_config to anon, authenticated;
