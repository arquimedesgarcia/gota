-- 00021: Rate Limiting — Schema and Functions (Sprint 07).
--
-- Implementa control de frecuencia server-side para operaciones críticas.
-- Requisitos (docs/SPRINT_07.md):
--  * Atomicidad bajo concurrencia (no hay ventana de carrera).
--  * Ventana de 1 hora configurada en system_config.
--  * Identidad: usuario autenticado (app_users.id).
--  * Persistencia: tabla dedicada sin cron jobs.
--  * Configuración centralizada, no hardcoded.

-- =====================================================================
-- 1. Rate Limiting Configuration
-- =====================================================================
-- Configuración centralizada de límites por operación. Valores en sistema_config.
insert into public.system_config (key, value)
values (
  'rate_limits',
  '{
    "create_leak_report": 3,
    "validate_leak": 20,
    "confirm_leak_resolution": 10,
    "register_water_event": 5,
    "validate_water_event": 20
  }'::jsonb
)
on conflict (key) do update
  set value = excluded.value,
      updated_at = now();

-- =====================================================================
-- 2. Rate Limit Tracking Table
-- =====================================================================
-- Registra intentos por usuario y operación dentro de la ventana de 1 hora.
-- La combinación (user_id, operation_type, window_start) identifica el bucket.
-- `count` se incrementa atómicamente; cuando expira la ventana, la fila
-- persiste (sin cleanup automático) pero ya no cuenta.
create table if not exists public.rate_limit_tracking (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.app_users(id) on delete cascade,
  operation_type   text not null check (operation_type in (
    'create_leak_report',
    'validate_leak',
    'confirm_leak_resolution',
    'register_water_event',
    'validate_water_event'
  )),
  -- Ventana de 1 hora: truncamos el timestamp actual a la hora.
  -- Ejemplo: 14:37:42 → 14:00:00. Cuando expire (now() >= window_start + 1h),
  -- este bucket ya no cuenta.
  window_start      timestamptz not null,
  count             int not null default 0 check (count >= 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- Única fila por usuario/operación/ventana.
  constraint rate_limit_tracking_unique
    unique (user_id, operation_type, window_start)
);

create index if not exists rate_limit_tracking_user_op_idx
  on public.rate_limit_tracking (user_id, operation_type);

create trigger rate_limit_tracking_set_updated_at
  before update on public.rate_limit_tracking
  for each row execute function public.set_updated_at();

-- =====================================================================
-- 3. RLS: sin acceso directo de cliente
-- =====================================================================
alter table public.rate_limit_tracking enable row level security;
revoke all on public.rate_limit_tracking from anon, authenticated;

-- =====================================================================
-- 4. Función Helper: obtener límite configurado
-- =====================================================================
create or replace function public.get_rate_limit(p_operation text)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    coalesce(
      (select (value->>(p_operation))::int
         from public.system_config
        where key = 'rate_limits'),
      case p_operation
        when 'create_leak_report' then 3
        when 'validate_leak' then 20
        when 'confirm_leak_resolution' then 10
        when 'register_water_event' then 5
        when 'validate_water_event' then 20
        else 1
      end
    ),
    1
  );
$$;

revoke execute on function public.get_rate_limit(text) from public, anon;
grant execute on function public.get_rate_limit(text) to authenticated;

-- =====================================================================
-- 5. Función Core: Check + Increment Rate Limit (Atómico)
-- =====================================================================
-- Valida que el usuario no haya excedido el límite en la ventana actual.
-- Si pasa, incrementa atomicamente el contador en una única fila.
-- Retorna JSON con:
--  * allowed: true/false
--  * remaining: intentos restantes en la ventana actual
--  * reset_at: cuándo se reinicia el contador (window_start + 1 hour)
--
-- Atomicidad: la inserción + update ocurren en la misma transacción y bajo
-- el UNIQUE constraint. Si dos requests llegan simultáneamente y el contador
-- está en el límite, ambos ven la misma fila bloqueada (serializable).
create or replace function public.check_rate_limit(
  p_user_id uuid,
  p_operation text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit          int;
  v_window_start   timestamptz;
  v_count          int;
  v_remaining      int;
  v_reset_at       timestamptz;
  v_allowed        boolean;
begin
  v_limit := public.get_rate_limit(p_operation);
  v_window_start := date_trunc('hour', now());
  v_reset_at := v_window_start + interval '1 hour';

  -- Upsert: garantiza exactamente una fila por usuario/op/ventana.
  -- El UNIQUE constraint maneja la idempotencia si dos requests
  -- intentan insertar simultáneamente: solo uno gana.
  insert into public.rate_limit_tracking
    (user_id, operation_type, window_start, count)
  values
    (p_user_id, p_operation, v_window_start, 1)
  on conflict (user_id, operation_type, window_start)
  do update
     set count = rate_limit_tracking.count + 1
  returning count into v_count;

  v_allowed := (v_count <= v_limit);
  v_remaining := greatest(v_limit - v_count, 0);

  return jsonb_build_object(
    'allowed', v_allowed,
    'remaining', v_remaining,
    'reset_at', v_reset_at
  );
end;
$$;

revoke execute on function public.check_rate_limit(uuid, text) from public, anon;
grant execute on function public.check_rate_limit(uuid, text) to authenticated;
