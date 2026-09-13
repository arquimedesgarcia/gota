-- 00022: Notification Preferences — RLS Fix (Sprint 07).
--
-- Problema: Sprint 06 permitió INSERT/UPDATE directo desde el cliente.
-- Solución: remover esos permisos. El cliente solo puede LEER.
-- Todas las modificaciones pasan por la RPC save_notification_preferences
-- (security definer), que valida y aplica las reglas de negocio.

-- Revocar permisos de escritura directa.
revoke insert, update on public.notification_preferences from authenticated;

-- Mantener solo SELECT.
-- (El grant select ya existe; esta operación es idempotente.)
