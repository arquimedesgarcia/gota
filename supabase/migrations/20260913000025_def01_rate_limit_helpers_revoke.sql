-- 00025: DEF-01 — Revocar EXECUTE de helpers de rate-limit (Sprint 07, remediación).
--
-- Hallazgo (docs/audits/2026-09-13_sprint07_security_abuse.md, DEF-01 CRÍTICO):
-- public.check_rate_limit(uuid, text) y public.check_rate_limit_inline(uuid, text)
-- son SECURITY DEFINER y tenían EXECUTE concedido a authenticated. Como ambas
-- aceptan p_user_id controlable por el caller, cualquier usuario autenticado
-- podía consumir el presupuesto de rate-limit de otro (DoS de las 5
-- operaciones críticas) y leer sus contadores (info-leak).
--
-- Corrección (mínima, sin rediseñar el rate limiter):
--  * Revocar EXECUTE a authenticated (y re-afirmar la revocación a PUBLIC/anon).
--    Los helpers quedan invocables únicamente desde el contexto interno:
--    las 5 RPC SECURITY DEFINER (dueñas postgres) que los llaman con la
--    identidad derivada de auth.uid() (v_app_user.id), nunca desde el cliente.
--  * search_path ya está fijado a '' en ambas funciones (sin superficie de
--    escalada por search_path); no se altera su lógica ni los límites.
--
-- Las RPC públicas (create_leak_report, validate_leak,
-- confirm_leak_resolution, register_water_event, validate_water_event)
-- resuelven la identidad de rate limiting desde auth.uid() → app_users,
-- por lo que siguen aplicando el límite al usuario que ejecuta la operación.

revoke execute on function public.check_rate_limit(uuid, text)
  from public, anon, authenticated;

revoke execute on function public.check_rate_limit_inline(uuid, text)
  from public, anon, authenticated;
