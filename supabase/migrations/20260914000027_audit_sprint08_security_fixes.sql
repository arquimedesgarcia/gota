-- 00027: correcciones de auditoría Sprint 08
-- (docs/audits/2026-09-14_sprint08_stabilization.md, commit auditado 1491952).
-- Sin cambios de datos, de API funcional ni de políticas de negocio.
--
-- AUD-S08-01: `water_events.created_by` era legible por anon/authenticated
--   (grant de tabla completa en 00014). Se aplica el mismo patrón con el que
--   se resolvió `reports.created_by` en 00016 (AUD-S2-01/02): GRANT por
--   columnas que excluye la identidad del creador. La autoría sigue
--   disponible para el cliente únicamente vía RPC (`get_water_event_detail`
--   devuelve `is_creator`, sin exponer el uuid). Las operaciones server-side
--   (register_water_event, validate_water_event, triggers, notificaciones)
--   son SECURITY DEFINER/owner y no dependen de estos grants.
--
-- AUD-S08-04: `system_config` tenía RLS desactivada y una policy pública
--   muerta (creada en 00011 sin `enable row level security`). El cliente
--   nunca lee esta tabla (la UI fija sus límites con respaldo server-side,
--   AUD-S2-15), así que el grant público es superficie innecesaria: cualquier
--   clave futura quedaría expuesta. Toda lectura real es interna:
--   create_leak_report (photo_limits/duplicate_detection),
--   resolution_threshold() y get_rate_limit(), todas SECURITY DEFINER
--   sobre tabla cuyo owner es el rol de migraciones: RLS y revokes de cliente
--   no las afectan. Se activa RLS, se retira la policy muerta y se revoca
--   el acceso de cliente.
--
-- Reversibilidad conceptual:
--   AUD-S08-01: grant select on public.water_events to anon, authenticated;
--   AUD-S08-04: revoke → grant select + recrear la policy, y
--               `alter table public.system_config disable row level security;`

-- =====================================================================
-- 1. AUD-S08-01 — water_events: grants por columna, sin created_by
-- =====================================================================
revoke all on public.water_events from anon, authenticated;

grant select (
  id, municipality_id, sector_id, event_type, event_time, comment,
  validation_count, created_at, updated_at
) on public.water_events to anon, authenticated;

-- =====================================================================
-- 2. AUD-S08-04 — system_config: RLS activa, sin acceso de cliente
-- =====================================================================
alter table public.system_config enable row level security;

drop policy if exists "Lectura pública de system_config"
  on public.system_config;

revoke all on public.system_config from anon, authenticated;
