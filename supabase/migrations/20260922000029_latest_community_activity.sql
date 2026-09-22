-- 00029: "Actividad reciente" global en el Home (RPC get_latest_community_activity).
--
-- Implementa docs/API_SPEC.md §2 (operación `get-latest-community-activity`) y
-- docs/FUNCTIONAL_SPEC.md §2 (Inicio): una sola fila con el último evento de la
-- comunidad a nivel global (todos los sectores del piloto), para fallas.
--
-- Decisiones y por qué:
--
--  * Umbral de validación en `system_config`, nunca hard-codeado. Hasta hoy el
--    umbral "validada" solo existía en el cliente (`validatedThreshold = 3`);
--    el servidor no lo conocía. Se siembra la clave `validation` con
--    {"threshold": 3} y se expone `public.validation_threshold()` copiando el
--    patrón exacto de `public.resolution_threshold()` (00013): función interna,
--    `security definer`, `search_path = ''`, con `revoke execute` para clientes.
--    El cliente sigue usando su propio default 3: unificar eso queda como deuda
--    documentada en docs/MIGRATION_NOTES.md (fuera de alcance de este cambio).
--
--  * El evento VALIDATED es el CRUCE DEL UMBRAL, no cada validación.
--    "Validada" es un estado derivado (validation_count alcanzó el umbral), así
--    que el evento es el momento en que lo alcanzó: el `created_at` de la
--    N-ésima validación (N = umbral, orden por (created_at, id)). La 1ª y la 2ª
--    validación de una falla con umbral 3 no son noticia; la 3ª sí.
--
--  * Privacidad (REQ-100): el DTO no expone ninguna identidad. No hay
--    `created_by`, ni `user_id`, ni email, ni teléfono, ni `storage_path`, ni
--    ids de `app_users`. Solo lo que la fila del listado ya muestra.
--
--  * Rendimiento: nada de `union all` sobre TODOS los `reports`. Cada tipo de
--    evento resuelve su candidato con un `order by ... limit 1` (índice
--    `reports_created_at_idx` para REPORTED, el índice parcial nuevo para
--    RESOLVED) y el VALIDATED usa `join lateral` posicional sobre
--    `report_validations` — la única lectura de esa tabla, válida porque la
--    función es `security definer` (el cliente sigue sin acceso: RLS sin
--    políticas + `revoke all` en 00013).
--
--  * Limitación aceptada y documentada: `validation_count` es monótono (no
--    existe RPC para des-validar), pero el umbral es configurable. Si se
--    cambiara en el futuro, el `at` histórico del evento VALIDATED se
--    recalcularía con el umbral nuevo. Es el precio de derivar el estado en
--    lugar de persistirlo; se acepta mientras el umbral no cambie en el piloto.
--
-- Grants: lectura pública (`revoke ... from public` + `grant ... to anon,
-- authenticated`), igual que `get_map_reports` (00017).

-- =====================================================================
-- 1. Configuración del umbral de validación
-- =====================================================================
-- Mismo estilo de semilla que 00009/00013: `on conflict (key) do update`.
insert into public.system_config (key, value)
values ('validation', '{"threshold": 3}'::jsonb)
on conflict (key) do update
  set value      = excluded.value,
      updated_at = now();

create or replace function public.validation_threshold()
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
        where key = 'validation'),
      3
    ),
    1
  );
$$;

-- Función interna: solo la usan las RPC (que son security definer).
revoke execute on function public.validation_threshold()
  from public, anon, authenticated;

-- =====================================================================
-- 2. Índice para el barrido del evento RESOLVED
-- =====================================================================
-- Parcial: solo interesan las fallas resueltas (el índice es pequeño y el
-- `order by resolved_at desc limit 1` se resuelve con un único seek).
create index if not exists reports_resolved_at_idx
  on public.reports (resolved_at desc)
  where status = 'RESOLVED';

-- =====================================================================
-- 3. RPC get_latest_community_activity (docs/API_SPEC.md §2)
-- =====================================================================
-- Devuelve 0 o 1 fila. Global: sin filtro de sector.
-- Columnas exactas del contrato del cliente (CommunityActivity.fromJson):
--   activity_type ('REPORTED' | 'VALIDATED' | 'RESOLVED'), "at",
--   report_id, status (estado ACTUAL de la falla), validation_count,
--   resolution_confirmation_count, created_at, resolved_at, description,
--   sector_id, sector_name, municipality_id, municipality_name.
create or replace function public.get_latest_community_activity()
returns table (
  activity_type                 text,
  "at"                          timestamptz,
  report_id                     uuid,
  status                        text,
  validation_count              int,
  resolution_confirmation_count int,
  created_at                    timestamptz,
  resolved_at                   timestamptz,
  description                   text,
  sector_id                     uuid,
  sector_name                   text,
  municipality_id               uuid,
  municipality_name             text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_threshold int;
begin
  v_threshold := public.validation_threshold();

  return query
  with candidates as (
    -- ---------- 1. REPORTED: última falla creada (reports_created_at_idx) ----
    (
      select 'REPORTED'::text as activity_type,
             r.created_at      as "at",
             3                 as prio,
             r.id              as report_id
        from public.reports r
       order by r.created_at desc, r.id
       limit 1
    )

    union all

    -- ---------- 2. RESOLVED: última falla resuelta (reports_resolved_at_idx) -
    (
      select 'RESOLVED'::text as activity_type,
             r.resolved_at     as "at",
             1                 as prio,
             r.id              as report_id
        from public.reports r
       where r.status = 'RESOLVED'
         and r.resolved_at is not null
       order by r.resolved_at desc, r.id
       limit 1
    )

    union all

    -- ---------- 3. VALIDATED: falla que cruzó el umbral ----------------------
    -- Posición N = v_threshold dentro de sus validaciones, orden (created_at,
    -- id). `join lateral` (inner): si el contador dice >= umbral pero faltan
    -- filas (inconsistencia imposible con las RPC actuales), la falla no
    -- produce candidato en lugar de producir uno con `at` nulo.
    (
      select 'VALIDATED'::text as activity_type,
             v.at              as "at",
             2                 as prio,
             v.report_id       as report_id
        from (
          select r.id           as report_id,
                 vv.created_at  as at
            from public.reports r
            join lateral (
              select rv.created_at
                from public.report_validations rv
               where rv.report_id = r.id
               order by rv.created_at, rv.id
               offset (v_threshold - 1)
               limit 1
            ) vv on true
           where r.validation_count >= v_threshold
           order by vv.created_at desc, r.id
           limit 1
        ) v
    )
  )
  -- Orden determinista: el evento más reciente gana; a igual `at`, gana
  -- RESOLVED > VALIDATED > REPORTED y, como desempate final, el report_id
  -- menor (misma fila en cada llamada).
  select c.activity_type,
         c."at",
         r.id,
         r.status,
         r.validation_count,
         r.resolution_confirmation_count,
         r.created_at,
         r.resolved_at,
         r.description,
         r.sector_id,
         s.name,
         r.municipality_id,
         m.name
    from candidates c
    join public.reports r on r.id = c.report_id
    join public.sectors s on s.id = r.sector_id
    join public.municipalities m on m.id = r.municipality_id
   order by c."at" desc, c.prio asc, c.report_id asc
   limit 1;
end;
$$;

revoke execute on function public.get_latest_community_activity() from public;
grant execute on function public.get_latest_community_activity()
  to anon, authenticated;