#!/usr/bin/env bash
# tests/rate_limit_concurrency_e2e.sh — Prueba de concurrencia REAL del
# rate limiting de Sprint 07 contra la base local de Supabase: M sesiones
# psql en paralelo (todas con la MISMA identidad autenticada simulada en
# request.jwt.claims) ejecutan create_leak_report al mismo tiempo.
#
# Verifica la atomicidad del contador (upsert bajo UNIQUE(user_id,
# operation_type, window_start), migración 20260913000021):
#   1. exactamente `limit` llamadas aceptadas (CREATED) — nunca más, aunque
#      los M requests se pisen; el resto recibe RATE_LIMIT_EXCEEDED;
#   2. ninguna llamada falla por otra causa (todas responden CREATED o
#      RATE_LIMIT_EXCEEDED): fotos y ubicaciones distintas por sesión para
#      no tropezar con la validación de fotos ni con POSSIBLE_DUPLICATE;
#   3. el contador del bucket queda en M y en public.reports hay como
#      máximo `limit` filas del usuario de la ráfaga.
#
# Uso (local):
#   bash supabase/tests/rate_limit_concurrency_e2e.sh
#
# El script crea y elimina sus propios datos (usuarios, sector, reportes,
# fotos simuladas y contadores) usando `docker exec ... psql` sobre la BD
# local de Supabase.

set -u
cd "$(dirname "$0")/../.." || exit 2

DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1)
if [ -z "$DB_CONTAINER" ]; then
  echo "NOT EXECUTED: se requiere Supabase local (\`supabase start\`) y Docker."
  exit 2
fi

# La API de Storage (con service_role) es la única vía para borrar objetos:
# storage.protect_delete() bloquea el DELETE directo en storage.objects.
API_URL=$(npx supabase status -o env 2>/dev/null | grep '^API_URL=' | cut -d= -f2- | tr -d '"')
SERVICE_KEY=$(npx supabase status -o env 2>/dev/null | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '"')
if [ -z "$API_URL" ] || [ -z "$SERVICE_KEY" ]; then
  echo "NOT EXECUTED: no se pudo resolver API_URL/SERVICE_ROLE_KEY (supabase status)."
  exit 2
fi

psql_db() { docker exec -i "$DB_CONTAINER" psql -q -U postgres -d postgres -t -A "$@"; }
del_object() { curl -s -o /dev/null -w '%{http_code}' -X DELETE \
  "$API_URL/storage/v1/object/report-photos/$1" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY"; }

# Sesión paralela: cada llamada abre su propia conexión.
session() {
  local claims="$1" statement="$2" out="$3"
  docker exec -i "$DB_CONTAINER" psql -q -U postgres -d postgres -t -A \
    -c "set role authenticated;" \
    -c "set request.jwt.claims = '$claims';" \
    -c "begin;" \
    -c "select pg_sleep(0.3);" \
    -c "$statement" \
    -c "commit;" > "$out" 2>&1
}

if [ -n "${LOCALAPPDATA:-}" ]; then
  TMP="$LOCALAPPDATA/Temp/gota_ratelimit"
elif [ -n "${TMPDIR:-}" ]; then
  TMP="$TMPDIR/gota_ratelimit"
else
  TMP="/tmp/gota_ratelimit"
fi
rm -rf "$TMP"; mkdir -p "$TMP"

FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1 ($3)";
          else echo "FAIL: $1 (esperado $2, obtenido $3)"; FAIL=1; fi }

# ---------- Datos de prueba ----------
# Usuario de la ráfaga concurrente y usuario "helper" dueño del reporte
# base: el reporte previo NO cuenta para el límite de la ráfaga, así que
# no puede pertenecer al usuario concurrente (quedarían 4 filas).
USER_ID='8a000000-0000-4000-8000-000000000000'
HELPER_ID='8a000000-0000-4000-8000-000000000001'
M=6            # llamadas paralelas ( > límite )
LIMIT=3        # límite exacto de create_leak_report (fallback y config)
SECTOR_ID=""

MUN_ID=$(psql_db -c "select id from public.municipalities limit 1;")
if [ -z "$MUN_ID" ]; then
  echo "NOT EXECUTED: no se encontró un municipio de prueba."
  rm -rf "$TMP"
  exit 2
fi

cleanup() {
  [ -n "$SECTOR_ID" ] && psql_db -c \
    "delete from public.reports where sector_id = '$SECTOR_ID';" >/dev/null
  # Fotos simuladas: solo por la API de Storage (protect_delete en la BD).
  for i in $(seq 1 "${M:-0}"); do
    del_object "report_photos/${USER_ID}/conc${i}/p1.jpg" >/dev/null 2>&1
  done
  [ -n "$SECTOR_ID" ] && psql_db -c \
    "delete from public.sectors where id = '$SECTOR_ID';" >/dev/null
  psql_db -c "delete from public.rate_limit_tracking
              where user_id in (select id from public.app_users
                                 where auth_user_id in
                                   ('$USER_ID','$HELPER_ID'));" >/dev/null
  psql_db -c "delete from auth.users
              where id in ('$USER_ID','$HELPER_ID');" >/dev/null
  rm -rf "$TMP"
}
# Armado ANTES de crear cualquier dato: falla o interrupción limpia todo.
trap cleanup EXIT

psql_db -c "
  insert into auth.users (id, email) values
    ('$USER_ID',  'rl_conc@gota.test'),
    ('$HELPER_ID','rl_conc_helper@gota.test')
  on conflict (id) do nothing;" >/dev/null

SECTOR_ID=$(psql_db -c "
  insert into public.sectors (municipality_id, name)
  values ('$MUN_ID', 'Sector Rate Limit Concurrencia')
  on conflict (municipality_id, name) do update set is_active = true
  returning id;")

if [ -z "$SECTOR_ID" ]; then
  echo "NOT EXECUTED: no se pudo crear el sector de prueba."
  exit 2
fi

# Reporte base del helper: un ACTIVE previo ~11 km de la ráfaga, para
# demostrar que ni el duplicado (50 m/48 h) ni el reporte ajeno interfieren.
psql_db -c "
  insert into public.reports (created_by, municipality_id, sector_id, location,
                              location_source)
  select u.id, '$MUN_ID', '$SECTOR_ID',
         extensions.st_setsrid(extensions.st_makepoint(-63.800, 9.800), 4326)::extensions.geography,
         'GPS'
    from public.app_users u where u.auth_user_id = '$HELPER_ID';" >/dev/null

# Una foto simulada por sesión (carpeta distinta; una foto ya asociada
# devolvería VALIDATION_ERROR y falsearía el conteo).
for i in $(seq 1 "$M"); do
  psql_db -c "
    insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
    values ('report-photos',
            'report_photos/${USER_ID}/conc${i}/p1.jpg',
            '$USER_ID', '$USER_ID',
            jsonb_build_object('mimetype', 'image/jpeg', 'size', 10240))
    on conflict (bucket_id, name) do update
      set owner = excluded.owner, owner_id = excluded.owner_id,
          metadata = excluded.metadata;" >/dev/null
done

APP_ID=$(psql_db -c "select id from public.app_users where auth_user_id = '$USER_ID';")
if [ -z "$APP_ID" ]; then
  echo "NOT EXECUTED: no se pudo aprovisionar el usuario de la ráfaga."
  exit 2
fi

claims() {
  echo "{\"role\": \"authenticated\", \"sub\": \"$USER_ID\", \"aud\": \"authenticated\"}"
}

# ---------- Ráfaga: M create_leak_report paralelos del mismo usuario ----------
# Coordenadas distintas y separadas > 50 m (0.001° ≈ 111 m) para que la
# detección de duplicados no intercepte ninguna llamada antes del rate check.
for i in $(seq 1 "$M"); do
  session "$(claims)" \
    "select (public.create_leak_report('$MUN_ID', '$SECTOR_ID', 9.90${i}, -63.900, 'GPS', null, '[{\"storage_path\":\"report_photos/${USER_ID}/conc${i}/p1.jpg\",\"sort_order\":1}]'::jsonb))->>'status_code';" \
    "$TMP/create_${i}.out" &
  eval "P$i=$!"
done
wait $P1; wait $P2; wait $P3; wait $P4; wait $P5; wait $P6

ACCEPTED=$(cat "$TMP"/create_*.out | grep -c '^CREATED$')
REJECTED=$(cat "$TMP"/create_*.out | grep -c '^RATE_LIMIT_EXCEEDED$')

check "llamadas aceptadas == límite exacto ($LIMIT)" "$LIMIT" "$ACCEPTED"
check "llamadas rechazadas == M - límite ($((M - LIMIT)))" "$((M - LIMIT))" "$REJECTED"
check "las $M sesiones respondieron CREATED o RATE_LIMIT_EXCEEDED" "$M" "$((ACCEPTED + REJECTED))"

REPORT_ROWS=$(psql_db -c "select count(*) from public.reports where created_by = '$APP_ID';")
if [ "$REPORT_ROWS" -le "$LIMIT" ]; then
  echo "PASS: filas de reportes del usuario <= $LIMIT ($REPORT_ROWS)"
else
  echo "FAIL: filas de reportes del usuario <= $LIMIT (obtenido $REPORT_ROWS)"
  FAIL=1
fi

COUNTER=$(psql_db -c "
  select coalesce((select count from public.rate_limit_tracking
                    where user_id = '$APP_ID'
                      and operation_type = 'create_leak_report'
                      and window_start = date_trunc('hour', now()))::text, '0');")
check "contador del bucket == M ($M) aunque 3 fueron rechazadas" "$M" "$COUNTER"

if [ "$FAIL" -eq 0 ]; then
  echo "Todas las pruebas de concurrencia de rate limiting pasaron."
  exit 0
fi
echo "Hay pruebas de concurrencia de rate limiting fallidas."
exit 1
