-- 00013: Validación comunitaria y resolución (Sprint 03).
--
-- Implementa docs/API_SPEC.md §2 (validate-leak, confirm-leak-resolution) y
-- docs/DATA_MODEL.md §5 (resolución atómica) sobre el patrón ya establecido
-- en Sprint 02: tablas con constraints, RLS cerrada para clientes y
-- operaciones críticas en funciones `security definer`.
--
-- Reglas aplicadas (docs/REQUIREMENTS.md §5 y §6):
--  * REQ-040/REQ-041/REQ-042/REQ-043: un usuario anónimo valida una fuga
--    ACTIVE de otro usuario; el creador no puede validar la suya; una
--    identidad valida una sola vez por reporte; la regla vive en el backend.
--  * REQ-044: cada validación se registra con timestamp e identidad.
--  * REQ-050/REQ-052/REQ-053: cualquier usuario puede confirmar resolución,
--    una confirmación por identidad, y con 3 identidades distintas el
--    reporte pasa atómicamente a RESOLVED.
--  * REQ-093: las acciones relevantes quedan en `audit_events`.
--
-- Atomicidad: cada operación bloquea la fila del reporte (`for update`),
-- inserta la acción (con UNIQUE (report_id, user_id) como autoridad real) y
-- actualiza el contador y el estado en la misma transacción. No hay ninguna
-- ventana en la que el contador se incremente sin que exista el registro, ni
-- dos incrementos para la misma identidad.

-- =====================================================================
-- 1. Tablas de acciones comunitarias
-- =====================================================================
create table if not exists public.report_validations (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid not null references public.reports(id) on delete cascade,
  user_id    uuid not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),

  -- Autoridad real contra duplicados: una identidad, una validación.
  constraint report_validations_unique_user unique (report_id, user_id)
);

create index if not exists report_validations_report_idx
  on public.report_validations (report_id);

create index if not exists report_validations_user_idx
  on public.report_validations (user_id);

create table if not exists public.resolution_confirmations (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid not null references public.reports(id) on delete cascade,
  user_id    uuid not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),

  constraint resolution_confirmations_unique_user unique (report_id, user_id)
);

create index if not exists resolution_confirmations_report_idx
  on public.resolution_confirmations (report_id);

create index if not exists resolution_confirmations_user_idx
  on public.resolution_confirmations (user_id);

-- =====================================================================
-- 2. RLS: sin acceso de cliente a las tablas de acciones
-- =====================================================================
-- El cliente nunca lee ni escribe estas tablas directamente:
--  * lectura del estado propio (¿ya validé?) -> RPC get_leak_report_detail;
--  * escritura -> RPC validate_leak / confirm_leak_resolution.
-- RLS habilitada sin políticas + GRANT nulo = denegado por defecto.
alter table public.report_validations enable row level security;
alter table public.resolution_confirmations enable row level security;

revoke all on public.report_validations from anon, authenticated;
revoke all on public.resolution_confirmations from anon, authenticated;

-- =====================================================================
-- 3. Configuración del umbral de resolución
-- =====================================================================
-- El umbral sigue siendo 3 identidades distintas (REQ-053). Vive en
-- `system_config` como el resto de la configuración de negocio, para no
-- quedar hard-codeado dentro de la función.
insert into public.system_config (key, value)
values ('resolution', '{"threshold": 3}'::jsonb)
on conflict (key) do update
  set value = excluded.value,
      updated_at = now();

create or replace function public.resolution_threshold()
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    coalesce(
      (select (value->>'threshold')::int
         from public.system_config
        where key = 'resolution'),
      3
    ),
    1
  );
$$;

-- Función interna: solo la usan las RPC (que son security definer).
revoke execute on function public.resolution_threshold()
  from public, anon, authenticated;

-- =====================================================================
-- 4. RPC validate_leak (docs/API_SPEC.md §2)
-- =====================================================================
-- Salidas (`status_code`):
--   VALIDATED / DUPLICATE_ACTION / NOT_FOUND / FORBIDDEN /
--   REPORT_ALREADY_RESOLVED / UNAUTHORIZED
create or replace function public.validate_leak(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid uuid;
  v_app_user public.app_users;
  v_report   public.reports;
  v_inserted uuid;
  v_count    int;
begin
  -- ---------- 1. Autenticación y usuario de aplicación ----------
  v_auth_uid := auth.uid();
  if v_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user from public.app_users
    where auth_user_id = v_auth_uid;
  if v_app_user.id is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;
  if v_app_user.is_blocked then
    return jsonb_build_object('status_code', 'FORBIDDEN',
                              'message', 'Tu acceso está bloqueado.');
  end if;

  -- ---------- 2. Reporte (fila bloqueada) ----------
  -- El bloqueo serializa las validaciones concurrentes del mismo reporte:
  -- la segunda transacción espera, vuelve a leer el estado real y su
  -- inserción choca con UNIQUE (report_id, user_id).
  select * into v_report from public.reports
    where id = p_report_id
    for update;

  if v_report.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos esta fuga.');
  end if;

  if v_report.status <> 'ACTIVE' then
    return jsonb_build_object(
      'status_code', 'REPORT_ALREADY_RESOLVED',
      'message', 'Esta fuga ya fue reportada como resuelta por la comunidad.',
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at
    );
  end if;

  -- ---------- 3. El creador no valida su propia fuga (REQ-041) ----------
  if v_report.created_by = v_app_user.id then
    return jsonb_build_object('status_code', 'FORBIDDEN',
      'message', 'No puedes validar tu propio reporte.');
  end if;

  -- ---------- 4. Una validación por identidad y reporte (REQ-042) ----------
  insert into public.report_validations (report_id, user_id)
  values (p_report_id, v_app_user.id)
  on conflict (report_id, user_id) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    -- Segunda acción del mismo usuario: determinista y sin efectos.
    return jsonb_build_object(
      'status_code', 'DUPLICATE_ACTION',
      'message', 'Ya validaste este reporte.',
      'already_validated', true,
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at,
      'threshold', public.resolution_threshold()
    );
  end if;

  -- ---------- 5. Contador consistente con el registro ----------
  update public.reports
     set validation_count = validation_count + 1
   where id = p_report_id
     and status = 'ACTIVE'
  returning validation_count into v_count;

  if v_count is null then
    -- Invariante: nunca puede existir una validación sin contador.
    raise exception 'validation_count no pudo actualizarse para %', p_report_id
      using errcode = 'P0001';
  end if;

  -- ---------- 6. Auditoría (REQ-093) ----------
  insert into public.audit_events
    (user_id, event_type, entity_type, entity_id, metadata)
  values
    (v_auth_uid, 'REPORT_VALIDATED', 'report', p_report_id,
     jsonb_build_object('validation_count', v_count));

  return jsonb_build_object(
    'status_code', 'VALIDATED',
    'already_validated', false,
    'status', v_report.status,
    'validation_count', v_count,
    'resolution_confirmation_count', v_report.resolution_confirmation_count,
    'resolved_at', v_report.resolved_at,
    'threshold', public.resolution_threshold()
  );
end;
$$;

revoke execute on function public.validate_leak(uuid) from public, anon;
grant execute on function public.validate_leak(uuid) to authenticated;

-- =====================================================================
-- 5. RPC confirm_leak_resolution (docs/API_SPEC.md §2)
-- =====================================================================
-- Salidas (`status_code`):
--   CONFIRMED / RESOLVED / DUPLICATE_ACTION / NOT_FOUND / FORBIDDEN /
--   REPORT_ALREADY_RESOLVED / UNAUTHORIZED
--
-- Decisión sobre la ambigüedad de REQ-051 (ver docs/MIGRATION_NOTES.md):
-- `confirm-leak-resolution` en API_SPEC.md no excluye al creador (a
-- diferencia de `validate-leak`, que sí lo hace), y REQ-050 dice
-- "cualquier usuario". Se implementa sin exclusión del creador: cualquier
-- identidad no bloqueada confirma una sola vez por reporte.
create or replace function public.confirm_leak_resolution(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_uid     uuid;
  v_app_user     public.app_users;
  v_report       public.reports;
  v_inserted     uuid;
  v_threshold    int;
  v_count        int;
  v_status       text;
  v_resolved_at  timestamptz;
begin
  -- ---------- 1. Autenticación y usuario de aplicación ----------
  v_auth_uid := auth.uid();
  if v_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user from public.app_users
    where auth_user_id = v_auth_uid;
  if v_app_user.id is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;
  if v_app_user.is_blocked then
    return jsonb_build_object('status_code', 'FORBIDDEN',
                              'message', 'Tu acceso está bloqueado.');
  end if;

  -- ---------- 2. Reporte (fila bloqueada) ----------
  select * into v_report from public.reports
    where id = p_report_id
    for update;

  if v_report.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos esta fuga.');
  end if;

  if v_report.status <> 'ACTIVE' then
    return jsonb_build_object(
      'status_code', 'REPORT_ALREADY_RESOLVED',
      'message', 'Esta fuga ya fue marcada como resuelta.',
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at
    );
  end if;

  -- ---------- 3. Una confirmación por identidad y reporte (REQ-052) ----------
  insert into public.resolution_confirmations (report_id, user_id)
  values (p_report_id, v_app_user.id)
  on conflict (report_id, user_id) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'status_code', 'DUPLICATE_ACTION',
      'message', 'Ya confirmaste la resolución de esta fuga.',
      'already_confirmed', true,
      'status', v_report.status,
      'validation_count', v_report.validation_count,
      'resolution_confirmation_count', v_report.resolution_confirmation_count,
      'resolved_at', v_report.resolved_at,
      'threshold', public.resolution_threshold()
    );
  end if;

  -- ---------- 4. Contador + transición atómica (REQ-053) ----------
  v_threshold := public.resolution_threshold();

  update public.reports
     set resolution_confirmation_count = resolution_confirmation_count + 1,
         status = case
                    when resolution_confirmation_count + 1 >= v_threshold
                    then 'RESOLVED'
                    else status
                  end,
         resolved_at = case
                         when resolution_confirmation_count + 1 >= v_threshold
                         then now()
                         else resolved_at
                       end
   where id = p_report_id
     and status = 'ACTIVE'
  returning resolution_confirmation_count, status, resolved_at
    into v_count, v_status, v_resolved_at;

  if v_count is null then
    -- Invariante: nunca puede existir una confirmación sin contador.
    raise exception 'resolution_confirmation_count no pudo actualizarse para %',
      p_report_id using errcode = 'P0001';
  end if;

  -- ---------- 5. Auditoría (REQ-093) ----------
  insert into public.audit_events
    (user_id, event_type, entity_type, entity_id, metadata)
  values
    (v_auth_uid, 'RESOLUTION_CONFIRMED', 'report', p_report_id,
     jsonb_build_object('resolution_confirmation_count', v_count,
                        'threshold', v_threshold));

  if v_status = 'RESOLVED' then
    insert into public.audit_events
      (user_id, event_type, entity_type, entity_id, metadata)
    values
      (v_auth_uid, 'REPORT_RESOLVED', 'report', p_report_id,
       jsonb_build_object('resolution_confirmation_count', v_count,
                          'threshold', v_threshold));
  end if;

  return jsonb_build_object(
    'status_code', case when v_status = 'RESOLVED' then 'RESOLVED'
                        else 'CONFIRMED' end,
    'already_confirmed', false,
    'status', v_status,
    'validation_count', v_report.validation_count,
    'resolution_confirmation_count', v_count,
    'resolved_at', v_resolved_at,
    'threshold', v_threshold
  );
end;
$$;

revoke execute on function public.confirm_leak_resolution(uuid)
  from public, anon;
grant execute on function public.confirm_leak_resolution(uuid)
  to authenticated;

-- =====================================================================
-- 6. RPC get_leak_report_detail
-- =====================================================================
-- Lectura del detalle + estado del usuario actual (¿es creador? ¿ya validó?
-- ¿ya confirmó?), necesaria para que la UI no ofrezca acciones inválidas.
-- El cliente no lee las tablas de acciones: todo sale de aquí.
create or replace function public.get_leak_report_detail(p_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_uid  uuid;
  v_app_user  public.app_users;
  v_report    public.reports;
  v_sector    public.sectors;
  v_municipal public.municipalities;
  v_photos    int;
begin
  v_auth_uid := auth.uid();
  if v_auth_uid is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_app_user from public.app_users
    where auth_user_id = v_auth_uid;
  if v_app_user.id is null then
    return jsonb_build_object('status_code', 'UNAUTHORIZED');
  end if;

  select * into v_report from public.reports where id = p_report_id;
  if v_report.id is null then
    return jsonb_build_object('status_code', 'NOT_FOUND',
                              'message', 'No encontramos esta fuga.');
  end if;

  select * into v_sector from public.sectors where id = v_report.sector_id;
  select * into v_municipal
    from public.municipalities where id = v_report.municipality_id;

  select count(*) into v_photos
    from public.report_photos where report_id = p_report_id;

  return jsonb_build_object(
    'status_code', 'OK',
    'report_id', v_report.id,
    'status', v_report.status,
    'validation_count', v_report.validation_count,
    'resolution_confirmation_count', v_report.resolution_confirmation_count,
    'threshold', public.resolution_threshold(),
    'created_at', v_report.created_at,
    'resolved_at', v_report.resolved_at,
    'updated_at', v_report.updated_at,
    'description', v_report.description,
    'location_source', v_report.location_source,
    'latitude', extensions.st_y(v_report.location::extensions.geometry),
    'longitude', extensions.st_x(v_report.location::extensions.geometry),
    'municipality_id', v_report.municipality_id,
    'municipality_name', v_municipal.name,
    'sector_id', v_report.sector_id,
    'sector_name', v_sector.name,
    'photo_count', v_photos,
    'is_creator', (v_report.created_by = v_app_user.id),
    'is_blocked', v_app_user.is_blocked,
    'already_validated', exists (
      select 1 from public.report_validations
       where report_id = p_report_id and user_id = v_app_user.id
    ),
    'already_confirmed', exists (
      select 1 from public.resolution_confirmations
       where report_id = p_report_id and user_id = v_app_user.id
    )
  );
end;
$$;

revoke execute on function public.get_leak_report_detail(uuid)
  from public, anon;
grant execute on function public.get_leak_report_detail(uuid)
  to authenticated;
