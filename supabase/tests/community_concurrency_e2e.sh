#!/usr/bin/env bash
# tests/community_concurrency_e2e.sh — Prueba de concurrencia REAL de
# Sprint 03 contra la base local de Supabase: varias sesiones psql en
# paralelo (cada una con su propia identidad anónima simulada en
# request.jwt.claims) operan sobre el mismo reporte al mismo tiempo.
#
# Verifica:
#   1. misma identidad validando en paralelo → exactamente 1 validación y
#      validation_count = 1 (una sesión recibe VALIDATED, la otra
#      DUPLICATE_ACTION);
#   2. cuatro identidades distintas confirmando resolución en paralelo →
#      contador = filas = 3, estado RESOLVED, resolved_at establecido y
#      ninguna confirmación extra (la cuarta recibe REPORT_ALREADY_RESOLVED);
#   3. el contador nunca se incrementa sin su registro.
#
# Uso (local):
#   bash supabase/tests/community_concurrency_e2e.sh
#
# El script crea y elimina sus propios datos (usuarios, sector y reportes)
# usando `docker exec ... psql` sobre la BD local de Supabase.

set -u
cd "$(dirname "$0")/../.." || exit 2

DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1)
if [ -z "$DB_CONTAINER" ]; then
  echo "NOT EXECUTED: se requiere Supabase local (\`supabase start\`) y Docker."
  exit 2
fi

psql_db() { docker exec -i "$DB_CONTAINER" psql -q -U postgres -d postgres -t -A "$@"; }

# Sesión paralela: cada llamada abre su propia conexión.
session() {
  local claims="$1" statement="$2" out="$3"
  docker exec -i "$DB_CONTAINER" psql -q -U postgres -d postgres -t -A \
    -c "set role authenticated;" \
    -c "set request.jwt.claims = '$claims';" \
    -c "begin;" \
    -c "select pg_sleep(0.6);" \
    -c "$statement" \
    -c "commit;" > "$out" 2>&1
}

if [ -n "${LOCALAPPDATA:-}" ]; then
  TMP="$LOCALAPPDATA/Temp/gota_concurrency"
elif [ -n "${TMPDIR:-}" ]; then
  TMP="$TMPDIR/gota_concurrency"
else
  TMP="/tmp/gota_concurrency"
fi
rm -rf "$TMP"; mkdir -p "$TMP"

FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1 ($3)";
          else echo "FAIL: $1 (esperado $2, obtenido $3)"; FAIL=1; fi }

# Armado ANTES de crear datos: los guards con ':-' hacen que los deletes
# simplemente no encuentren nada cuando el recurso aún no existe; vacíos en
# el 'in (...)' tampoco coinciden con ningún id.
cleanup() {
  if [ -n "${SECTOR_ID:-}" ]; then
    psql_db -c "delete from public.reports where sector_id = '$SECTOR_ID';" >/dev/null
    psql_db -c "delete from public.sectors where id = '$SECTOR_ID';" >/dev/null
  fi
  psql_db -c "delete from auth.users where id in
              ('${CREATOR:-}','${VALIDATOR:-}','${CONF1:-}','${CONF2:-}','${CONF3:-}','${CONF4:-}');" >/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---------- Datos de prueba ----------
CREATOR='7a000000-0000-4000-8000-000000000000'
VALIDATOR='7b000000-0000-4000-8000-000000000000'
CONF1='7c000000-0000-4000-8000-000000000000'
CONF2='7d000000-0000-4000-8000-000000000000'
CONF3='7e000000-0000-4000-8000-000000000000'
CONF4='7f000000-0000-4000-8000-000000000000'

MUN_ID=$(psql_db -c "select id from public.municipalities limit 1;")
SECTOR_ID=$(psql_db -c "
  insert into public.sectors (municipality_id, name)
  values ('$MUN_ID', 'Sector Concurrencia Temporal')
  on conflict (municipality_id, name) do update set is_active = true
  returning id;")

psql_db -c "
  insert into auth.users (id, email) values
    ('$CREATOR',   'conc_creator@gota.test'),
    ('$VALIDATOR', 'conc_validator@gota.test'),
    ('$CONF1',     'conc_c1@gota.test'),
    ('$CONF2',     'conc_c2@gota.test'),
    ('$CONF3',     'conc_c3@gota.test'),
    ('$CONF4',     'conc_c4@gota.test')
  on conflict (id) do nothing;" >/dev/null

REPORT_VALID=$(psql_db -c "
  insert into public.reports (created_by, municipality_id, sector_id, location,
                              location_source)
  select u.id, '$MUN_ID', '$SECTOR_ID',
         extensions.st_setsrid(extensions.st_makepoint(-63.81, 11.01), 4326)::extensions.geography,
         'GPS'
    from public.app_users u where u.auth_user_id = '$CREATOR'
  returning id;")
REPORT_CONF=$(psql_db -c "
  insert into public.reports (created_by, municipality_id, sector_id, location,
                              location_source)
  select u.id, '$MUN_ID', '$SECTOR_ID',
         extensions.st_setsrid(extensions.st_makepoint(-63.82, 11.02), 4326)::extensions.geography,
         'GPS'
    from public.app_users u where u.auth_user_id = '$CREATOR'
  returning id;")

if [ -z "$REPORT_VALID" ] || [ -z "$REPORT_CONF" ]; then
  echo "NOT EXECUTED: no se pudieron crear los reportes de prueba."
  exit 2
fi
echo "reporte de validación: ${REPORT_VALID:0:8}…"
echo "reporte de resolución: ${REPORT_CONF:0:8}…"

claims() {
  echo "{\"role\": \"authenticated\", \"sub\": \"$1\", \"aud\": \"authenticated\"}"
}

# ---------- 1. Misma identidad validando en paralelo ----------
session "$(claims "$VALIDATOR")" \
  "select (public.validate_leak('$REPORT_VALID'))->>'status_code';" \
  "$TMP/val_1.out" &
P1=$!
session "$(claims "$VALIDATOR")" \
  "select (public.validate_leak('$REPORT_VALID'))->>'status_code';" \
  "$TMP/val_2.out" &
P2=$!
wait $P1; wait $P2

VAL_STATUSES=$(cat "$TMP/val_1.out" "$TMP/val_2.out" | grep -E '^(VALIDATED|DUPLICATE_ACTION)$' | sort | tr '\n' ',')
check "validaciones paralelas: una sesión VALIDATED y la otra DUPLICATE_ACTION" \
  "DUPLICATE_ACTION,VALIDATED," "$VAL_STATUSES"
check "una sola validación persistida" 1 \
  "$(psql_db -c "select count(*) from public.report_validations where report_id = '$REPORT_VALID';")"
check "validation_count = 1 (sin doble incremento)" 1 \
  "$(psql_db -c "select validation_count from public.reports where id = '$REPORT_VALID';")"

# ---------- 2. Cuatro identidades confirmando resolución en paralelo ----------
session "$(claims "$CONF1")" \
  "select (public.confirm_leak_resolution('$REPORT_CONF'))->>'status_code';" \
  "$TMP/conf_1.out" &
P1=$!
session "$(claims "$CONF2")" \
  "select (public.confirm_leak_resolution('$REPORT_CONF'))->>'status_code';" \
  "$TMP/conf_2.out" &
P2=$!
session "$(claims "$CONF3")" \
  "select (public.confirm_leak_resolution('$REPORT_CONF'))->>'status_code';" \
  "$TMP/conf_3.out" &
P3=$!
session "$(claims "$CONF4")" \
  "select (public.confirm_leak_resolution('$REPORT_CONF'))->>'status_code';" \
  "$TMP/conf_4.out" &
P4=$!
wait $P1; wait $P2; wait $P3; wait $P4

CONF_STATUSES=$(cat "$TMP/conf_1.out" "$TMP/conf_2.out" "$TMP/conf_3.out" "$TMP/conf_4.out" \
  | grep -E '^(CONFIRMED|RESOLVED|REPORT_ALREADY_RESOLVED|DUPLICATE_ACTION)$' | sort | tr '\n' ',')
check "confirmaciones paralelas: 3 acciones y 1 rechazo por estado" \
  "CONFIRMED,CONFIRMED,REPORT_ALREADY_RESOLVED,RESOLVED," "$CONF_STATUSES"
check "confirmaciones persistidas = 3 (umbral)" 3 \
  "$(psql_db -c "select count(*) from public.resolution_confirmations where report_id = '$REPORT_CONF';")"
check "resolution_confirmation_count = 3" 3 \
  "$(psql_db -c "select resolution_confirmation_count from public.reports where id = '$REPORT_CONF';")"
check "estado final RESOLVED" "RESOLVED" \
  "$(psql_db -c "select status from public.reports where id = '$REPORT_CONF';")"
check "resolved_at establecido" "t" \
  "$(psql_db -c "select resolved_at is not null from public.reports where id = '$REPORT_CONF';")"
check "no hay transiciones repetidas (una sola resolución)" 1 \
  "$(psql_db -c "select count(*) from public.audit_events where event_type = 'REPORT_RESOLVED' and entity_id = '$REPORT_CONF';")"
check "contador == filas persistidas" "3|3" \
  "$(psql_db -c "select r.resolution_confirmation_count || '|' || (select count(*) from public.resolution_confirmations c where c.report_id = r.id) from public.reports r where r.id = '$REPORT_CONF';")"

if [ "$FAIL" -eq 0 ]; then
  echo "Todas las pruebas de concurrencia de Sprint 03 pasaron."
  exit 0
fi
echo "Hay pruebas de concurrencia de Sprint 03 fallidas."
exit 1
