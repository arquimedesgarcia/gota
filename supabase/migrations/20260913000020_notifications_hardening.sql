-- 00020: Notificaciones — hardening de grants (Sprint 06, post-auditoría).
--
-- El cliente authenticated debe poder solo LEER tokens propios; la escritura
-- (register/unregister) se hace exclusivamente vía RPC con security definer.
-- Esto previene que el cliente bypasse los validadores y lógica de
-- reasignación de tokens en las funciones.

drop policy if exists "Usuario crea sus tokens" on public.notification_tokens;
drop policy if exists "Usuario actualiza sus tokens" on public.notification_tokens;
drop policy if exists "Usuario elimina sus tokens" on public.notification_tokens;

revoke all on public.notification_tokens from authenticated;
grant select on public.notification_tokens to authenticated;
