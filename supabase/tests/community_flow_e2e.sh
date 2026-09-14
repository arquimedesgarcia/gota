#!/usr/bin/env bash
# tests/community_flow_e2e.sh — Verificación de integración real de Sprint 03
# contra la API local de Supabase (REST + Auth anónimo), es decir, el mismo
# camino que usa Flutter:
#
#   1. cuatro usuarios anónimos reales (auth) — creador + 3 identidades;
#   2. creación de una fuga por el creador (RPC create_leak_report + Storage);
#   3. el creador no puede validar su propia fuga (FORBIDDEN);
#   4. validación real (VALIDATED) y segunda validación (DUPLICATE_ACTION);
#   5. detalle con estado del usuario (already_validated / is_creator / threshold);
#   6. confirmaciones: 1/3 y 2/3 → ACTIVE; 3/3 → RESOLVED + resolved_at;
#   7. el cliente NO puede modificar contadores/estado ni insertar
#      validaciones por la API (RLS + GRANT);
#   8. la lectura del listado usada por la app (select con recursos
#      embebidos sector/municipio) funciona con RLS para un usuario anónimo.
#
# Uso (local):
#   bash supabase/tests/community_flow_e2e.sh
#
# El script crea y elimina sus propios datos usando `docker exec ... psql`
# (sector, reportes y usuarios anónimos) y la API de Storage (la foto),
# vía un trap EXIT armado antes de crear cualquier recurso.

set -u
cd "$(dirname "$0")/../.." || exit 2

API_URL=$(npx supabase status -o env 2>/dev/null | grep '^API_URL=' | cut -d= -f2- | tr -d '"')
ANON_KEY=$(npx supabase status -o env 2>/dev/null | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '"')
DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1)

if [ -z "$API_URL" ] || [ -z "$ANON_KEY" ] || [ -z "$DB_CONTAINER" ]; then
  echo "NOT EXECUTED: se requiere Supabase local (\`supabase start\`) y Docker."
  exit 2
fi

# Cabeceras construidas en tiempo de ejecución (evita repetir la clave en
# cada llamada y facilita cambiar el token por usuario).
H_KEY=$(printf '%s: %s' 'apikey' "$ANON_KEY")
h_auth() { printf '%s: %s %s' 'Authorization' 'Bearer' "$1"; }

psql_db() { docker exec -i "$DB_CONTAINER" psql -q -U postgres -d postgres -t -A "$@"; }

resolve_py() {
  for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 &&
       "$candidate" -c 'import json,sys' >/dev/null 2>&1; then
      echo "$candidate"; return 0
    fi
  done
  return 1
}
if command -v jq >/dev/null 2>&1; then
  json_get() { jq -r "$1"; }
elif PY=$(resolve_py); then
  json_get() { "$PY" -c "import sys,json;print(json.load(sys.stdin)$1)"; }
else
  echo "NOT EXECUTED: se requiere jq, python3 o python."
  exit 2
fi

if [ -n "${LOCALAPPDATA:-}" ]; then
  TMP="$LOCALAPPDATA/Temp/gota_e2e_community"
elif [ -n "${TMPDIR:-}" ]; then
  TMP="$TMPDIR/gota_e2e_community"
else
  TMP="/tmp/gota_e2e_community"
fi
mkdir -p "$TMP"
printf 'foto-e2e-sprint03' > "$TMP/photo.jpg"

FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1 ($3)";
          else echo "FAIL: $1 (esperado $2, obtenido $3)"; FAIL=1; fi }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

cleanup() {
  # Armado antes de crear nada: tolera recursos aún no creados (los guards
  # con ':-' hacen que los deletes simplemente no encuentren nada).
  # Storage: la foto solo la puede borrar el token del creador; un 404
  # (nunca subida) se ignora.
  if [ -n "${PHOTO_PATH:-}" ] && [ -n "${T_CREATOR:-}" ]; then
    curl -s -o /dev/null -X DELETE \
      "$API_URL/storage/v1/object/report-photos/$PHOTO_PATH" \
      -H "$H_KEY" -H "$(h_auth "$T_CREATOR")"
  fi
  if [ -n "${SECTOR_ID:-}" ]; then
    psql_db -c "delete from public.report_photos where report_id in (
                  select id from public.reports where sector_id = '$SECTOR_ID');" >/dev/null
    psql_db -c "delete from public.reports where sector_id = '$SECTOR_ID';" >/dev/null
    psql_db -c "delete from public.sectors where id = '$SECTOR_ID';" >/dev/null
  fi
  # auth.users: borrado directo (cascada sobre app_users), como en
  # community_concurrency_e2e.sh; las cadenas vacías no coinciden con nada.
  psql_db -c "delete from auth.users where id in
              ('${U_CREATOR:-}','${U_VAL1:-}','${U_VAL2:-}','${U_VAL3:-}');" >/dev/null
}
trap cleanup EXIT

# ---------- usuarios anónimos reales ----------
anon_signup() {
  curl -s -X POST "$API_URL/auth/v1/signup" \
    -H "$H_KEY" -H 'Content-Type: application/json' -d '{}' \
    | json_get "['access_token']"
}
token_to_user() {
  curl -s "$API_URL/auth/v1/user" -H "$H_KEY" -H "$(h_auth "$1")" \
    | json_get "['id']"
}

T_CREATOR=$(anon_signup)
T_VAL1=$(anon_signup)
T_VAL2=$(anon_signup)
T_VAL3=$(anon_signup)

U_CREATOR=$(token_to_user "$T_CREATOR")
U_VAL1=$(token_to_user "$T_VAL1")
U_VAL2=$(token_to_user "$T_VAL2")
U_VAL3=$(token_to_user "$T_VAL3")

if [ -z "$U_CREATOR" ] || [ -z "$U_VAL3" ]; then
  echo "NOT EXECUTED: no se pudieron crear usuarios anónimos."
  exit 2
fi
echo "creador: ${U_CREATOR:0:8}… · validadores: ${U_VAL1:0:8}… ${U_VAL2:0:8}… ${U_VAL3:0:8}…"

# ---------- sector temporal para el reporte ----------
MUN_ID=$(psql_db -c "select id from public.municipalities where name = 'Maneiro' limit 1;")
SECTOR_ID=$(psql_db -c "
  insert into public.sectors (municipality_id, name)
  values ('$MUN_ID', 'Sector E2E Comunidad')
  on conflict (municipality_id, name) do update set is_active = true
  returning id;")

# ---------- foto + creación de la fuga por el creador ----------
PHOTO_PATH="report_photos/$U_CREATOR/e2e03/p1.jpg"
UP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "$API_URL/storage/v1/object/report-photos/$PHOTO_PATH" \
  -H "$H_KEY" -H "$(h_auth "$T_CREATOR")" \
  -H 'Content-Type: image/jpeg' --data-binary "@$TMP/photo.jpg")
check "el creador sube su foto" 200 "$UP_CODE"

rpc() { # $1 = token, $2 = función, $3 = cuerpo json
  printf '%s' "$3" > "$TMP/rpc.json"
  curl -s -X POST "$API_URL/rest/v1/rpc/$2" \
    -H "$H_KEY" -H "$(h_auth "$1")" \
    -H 'Content-Type: application/json' --data-binary "@$TMP/rpc.json"
}
status_of() { echo "$1" | json_get "['status_code']"; }

RESP=$(rpc "$T_CREATOR" create_leak_report \
  "{\"p_municipality_id\":\"$MUN_ID\",\"p_sector_id\":\"$SECTOR_ID\",\"p_latitude\":11.05,\"p_longitude\":-63.85,\"p_location_source\":\"GPS\",\"p_description\":\"E2E Sprint 03\",\"p_photos\":[{\"storage_path\":\"$PHOTO_PATH\",\"sort_order\":1}]}")
check "la RPC crea la fuga" CREATED "$(status_of "$RESP")"
REPORT_ID=$(echo "$RESP" | json_get "['report_id']")

# ---------- 1. el creador no valida su propia fuga ----------
RESP=$(rpc "$T_CREATOR" validate_leak "{\"p_report_id\":\"$REPORT_ID\"}")
check "el creador no puede validar su propia fuga" FORBIDDEN "$(status_of "$RESP")"

# ---------- 2. validación real y duplicado del mismo usuario ----------
RESP=$(rpc "$T_VAL1" validate_leak "{\"p_report_id\":\"$REPORT_ID\"}")
check "un vecino valida la fuga" VALIDATED "$(status_of "$RESP")"
check "el contador de validaciones es 1" 1 "$(echo "$RESP" | json_get "['validation_count']")"

RESP=$(rpc "$T_VAL1" validate_leak "{\"p_report_id\":\"$REPORT_ID\"}")
check "la segunda validación del mismo usuario se rechaza" DUPLICATE_ACTION "$(status_of "$RESP")"
DB_COUNT=$(psql_db -c "select count(*) from public.report_validations where report_id = '$REPORT_ID';")
check "solo hay una validación persistida" 1 "$DB_COUNT"
DB_COUNT=$(psql_db -c "select validation_count from public.reports where id = '$REPORT_ID';")
check "validation_count no se duplicó" 1 "$DB_COUNT"

# ---------- 3. detalle con estado del usuario ----------
DETAIL=$(rpc "$T_VAL1" get_leak_report_detail "{\"p_report_id\":\"$REPORT_ID\"}")
check "el detalle marca already_validated" true \
  "$(lower "$(echo "$DETAIL" | json_get "['already_validated']")")"
check "el detalle marca is_creator=false" false \
  "$(lower "$(echo "$DETAIL" | json_get "['is_creator']")")"
check "el umbral del detalle es 3" 3 "$(echo "$DETAIL" | json_get "['threshold']")"

# ---------- 4. confirmaciones de resolución ----------
RESP=$(rpc "$T_VAL1" confirm_leak_resolution "{\"p_report_id\":\"$REPORT_ID\"}")
check "1ª confirmación → CONFIRMED" CONFIRMED "$(status_of "$RESP")"
check "sigue ACTIVE con 1/3" ACTIVE "$(echo "$RESP" | json_get "['status']")"

RESP=$(rpc "$T_VAL1" confirm_leak_resolution "{\"p_report_id\":\"$REPORT_ID\"}")
check "confirmación duplicada rechazada" DUPLICATE_ACTION "$(status_of "$RESP")"

RESP=$(rpc "$T_VAL2" confirm_leak_resolution "{\"p_report_id\":\"$REPORT_ID\"}")
check "2ª confirmación (otra identidad) → CONFIRMED" CONFIRMED "$(status_of "$RESP")"
check "sigue ACTIVE con 2/3" ACTIVE "$(echo "$RESP" | json_get "['status']")"

RESP=$(rpc "$T_VAL3" confirm_leak_resolution "{\"p_report_id\":\"$REPORT_ID\"}")
check "3ª identidad → RESOLVED" RESOLVED "$(status_of "$RESP")"
check "resolution_confirmation_count = 3" 3 "$(echo "$RESP" | json_get "['resolution_confirmation_count']")"

DB_ROW=$(psql_db -c "select status || '|' || (resolved_at is not null) from public.reports where id = '$REPORT_ID';")
check "el reporte quedó RESOLVED con resolved_at" "resolved|true" "$(lower "$DB_ROW")"
DB_COUNT=$(psql_db -c "select count(*) from public.resolution_confirmations where report_id = '$REPORT_ID';")
check "3 confirmaciones persistidas" 3 "$DB_COUNT"

# ---------- 5. una fuga resuelta no acepta más acciones ----------
RESP=$(rpc "$T_VAL1" validate_leak "{\"p_report_id\":\"$REPORT_ID\"}")
check "validar una fuga resuelta se rechaza" REPORT_ALREADY_RESOLVED "$(status_of "$RESP")"
RESP=$(rpc "$T_VAL2" confirm_leak_resolution "{\"p_report_id\":\"$REPORT_ID\"}")
check "confirmar una fuga resuelta se rechaza" REPORT_ALREADY_RESOLVED "$(status_of "$RESP")"
DB_ROW=$(psql_db -c "select status from public.reports where id = '$REPORT_ID';")
check "el estado sigue RESOLVED (nunca vuelve a ACTIVE)" RESOLVED "$DB_ROW"

# ---------- 6. el cliente no puede tocar campos críticos por la API ----------
printf '%s' '{"validation_count": 99, "status": "ACTIVE", "resolved_at": null}' > "$TMP/patch.json"
PATCH_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
  "$API_URL/rest/v1/reports?id=eq.$REPORT_ID" \
  -H "$H_KEY" -H "$(h_auth "$T_VAL1")" \
  -H 'Content-Type: application/json' --data-binary "@$TMP/patch.json")
if [ "$PATCH_CODE" = "200" ] || [ "$PATCH_CODE" = "204" ]; then
  check "el cliente no puede modificar contadores/estado" "bloqueado" "HTTP $PATCH_CODE"
else
  check "el cliente no puede modificar contadores/estado" "bloqueado" "bloqueado"
fi
DB_ROW=$(psql_db -c "select validation_count || '|' || status from public.reports where id = '$REPORT_ID';")
check "los valores críticos siguen intactos" "1|RESOLVED" "$DB_ROW"

printf '%s' "{\"report_id\":\"$REPORT_ID\"}" > "$TMP/insert.json"
INSERT_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$API_URL/rest/v1/report_validations" \
  -H "$H_KEY" -H "$(h_auth "$T_VAL2")" \
  -H 'Content-Type: application/json' --data-binary "@$TMP/insert.json")
if [ "$INSERT_CODE" = "200" ] || [ "$INSERT_CODE" = "201" ]; then
  check "el cliente no puede insertar validaciones directamente" "bloqueado" "HTTP $INSERT_CODE"
else
  check "el cliente no puede insertar validaciones directamente" "bloqueado" "bloqueado"
fi

# ---------- 7. lectura del listado que usa la app (recursos embebidos) ----------
LIST=$(curl -s \
  "$API_URL/rest/v1/reports?select=id,status,validation_count,resolution_confirmation_count,created_at,resolved_at,description,sectors(name),municipalities(name)&order=status.asc,created_at.desc&limit=5" \
  -H "$H_KEY" -H "$(h_auth "$T_VAL1")")
case "$LIST" in
  *"$REPORT_ID"*) check "el listado con sector/municipio embebidos funciona con RLS" "ok" "ok" ;;
  *) check "el listado con sector/municipio embebidos funciona con RLS" "ok" "respuesta inesperada: ${LIST:0:120}" ;;
esac

if [ "$FAIL" -eq 0 ]; then
  echo "Todas las pruebas E2E del ciclo comunitario de Sprint 03 pasaron."
  exit 0
fi
echo "Hay pruebas E2E del ciclo comunitario de Sprint 03 fallidas."
exit 1
