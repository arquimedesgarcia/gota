#!/usr/bin/env bash
# tests/create_leak_report_e2e.sh — Verificación de integración real del
# camino completo de Sprint 02 contra Supabase local:
#
#   1. usuario anónimo real (auth);
#   2. subida de la foto a su propia carpeta (Storage + RLS);
#   3. creación del reporte vía la RPC `create_leak_report` (REST);
#   4. duplicado: mismo punto → POSSIBLE_DUPLICATE (no se persiste);
#   5. validación server-side del MIME (archivo subido como image/gif);
#   6. cleanup: el usuario borra sus temporales por la API (como hace
#      `_cleanupUploaded()` cuando la creación falla o hay duplicado).
#
# Uso (local):
#   bash supabase/tests/create_leak_report_e2e.sh
#
# El script crea y elimina sus propios datos (reporte, sector temporal y
# archivos): los datos vía `docker exec ... psql` y los archivos por la API
# de Storage (trap EXIT, además de los checks finales).

set -u
cd "$(dirname "$0")/../.." || exit 2

API_URL=$(npx supabase status -o env 2>/dev/null | grep '^API_URL=' | cut -d= -f2- | tr -d '"')
ANON_KEY=$(npx supabase status -o env 2>/dev/null | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '"')
DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1)

if [ -z "$API_URL" ] || [ -z "$ANON_KEY" ] || [ -z "$DB_CONTAINER" ]; then
  echo "NOT EXECUTED: se requiere Supabase local (`supabase start`) y Docker."
  exit 2
fi

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
  TMP="$LOCALAPPDATA/Temp/gota_e2e"
elif [ -n "${TMPDIR:-}" ]; then
  TMP="$TMPDIR/gota_e2e"
else
  TMP="/tmp/gota_e2e"
fi
mkdir -p "$TMP"
printf 'foto-e2e-gota' > "$TMP/photo.jpg"
printf 'gif-e2e-gota' > "$TMP/photo.gif"

FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1 ($3)";
          else echo "FAIL: $1 (esperado $2, obtenido $3)"; FAIL=1; fi }

# ---------- 1. usuario anónimo ----------
TOKEN=$(curl -s -X POST "$API_URL/auth/v1/signup" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -d '{}' \
  | json_get "['access_token']")
USER_ID=$(curl -s "$API_URL/auth/v1/user" -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $TOKEN" | json_get "['id']")
if [ -z "$USER_ID" ]; then echo "NOT EXECUTED: sin usuarios anónimos."; exit 2; fi
echo "usuario anónimo: ${USER_ID:0:8}…"

# ---------- sector temporal (los sectores reales están pendientes) ----------
MUN_ID=$(psql_db -c "select id from public.municipalities where name = 'Maneiro' limit 1;")
SECTOR_ID=$(psql_db -c "
  insert into public.sectors (municipality_id, name)
  values ('$MUN_ID', 'Sector E2E Temporal')
  on conflict (municipality_id, name) do update set is_active = true
  returning id;")

# delete con el token propio (también lo usa cleanup para no dejar huérfanos).
del() { curl -s -o /dev/null -w '%{http_code}' -X DELETE "$1" \
        -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN"; }

cleanup() {
  # Storage: los temporales solo los puede borrar el token propio; un 404
  # (objeto ya borrado por los checks finales) se ignora. Los guards con
  # ':-' toleran un trap disparado antes de definir las rutas.
  if [ -n "${TOKEN:-}" ]; then
    [ -n "${OBJ:-}" ] && del "$OBJ" >/dev/null
    [ -n "${GIFOBJ:-}" ] && del "$GIFOBJ" >/dev/null
    [ -n "${P3_PATH:-}" ] && \
      del "$API_URL/storage/v1/object/report-photos/$P3_PATH" >/dev/null
  fi
  psql_db -c "delete from public.report_photos where report_id in (
                select id from public.reports where sector_id = '$SECTOR_ID');" >/dev/null
  psql_db -c "delete from public.reports where sector_id = '$SECTOR_ID';" >/dev/null
  psql_db -c "delete from public.sectors where id = '$SECTOR_ID';" >/dev/null
}
trap cleanup EXIT

# ---------- 2. subida a la propia carpeta ----------
OBJ="$API_URL/storage/v1/object/report-photos/report_photos/$USER_ID/e2e/p1.jpg"
GIFOBJ="$API_URL/storage/v1/object/report-photos/report_photos/$USER_ID/e2e/p2.gif"

up_code() { curl -s -o /dev/null -w '%{http_code}' -X POST "$1" \
            -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: $2" --data-binary "@$3"; }

check "subida de la foto a la carpeta propia" 200 "$(up_code "$OBJ" image/jpeg "$TMP/photo.jpg")"
check "subida de un GIF a la carpeta propia" 200 "$(up_code "$GIFOBJ" image/gif "$TMP/photo.gif")"

# El JSON se envía en archivo: MSYS mutila los argumentos con '/' y
# rompería las rutas de storage_path.
rpc() {
  printf '%s' "$1" > "$TMP/rpc.json"
  curl -s -X POST "$API_URL/rest/v1/rpc/create_leak_report" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" --data-binary "@$TMP/rpc.json"
}
status_of() { echo "$1" | json_get "['status_code']"; }

JPEG_PATH="report_photos/$USER_ID/e2e/p1.jpg"
GIF_PATH="report_photos/$USER_ID/e2e/p2.gif"
P3_PATH="report_photos/$USER_ID/e2e/p3.jpg"
COORDS="\"p_latitude\": 11.001, \"p_longitude\": -63.801"

# ---------- 3. creación ----------
RESP=$(rpc "{\"p_municipality_id\":\"$MUN_ID\",\"p_sector_id\":\"$SECTOR_ID\",$COORDS,\"p_location_source\":\"GPS\",\"p_description\":\"E2E\",\"p_photos\":[{\"storage_path\":\"$JPEG_PATH\",\"mime_type\":\"image/jpeg\",\"size_bytes\":14,\"sort_order\":1}]}")
check "la RPC crea el reporte" CREATED "$(status_of "$RESP")"
REPORT_ID=$(echo "$RESP" | json_get "['report_id']")
ROWS=$(psql_db -c "select count(*) from public.report_photos where report_id = '$REPORT_ID';")
check "las fotos quedan referenciadas" 1 "$ROWS"
STATUS=$(psql_db -c "select status from public.reports where id = '$REPORT_ID';")
check "el reporte nace ACTIVE" ACTIVE "$STATUS"

# ---------- 4. duplicado en el mismo punto ----------
# 4a. Reutilizar la misma foto no es posible (ya está asociada a un reporte).
RESP=$(rpc "{\"p_municipality_id\":\"$MUN_ID\",\"p_sector_id\":\"$SECTOR_ID\",$COORDS,\"p_location_source\":\"GPS\",\"p_photos\":[{\"storage_path\":\"$JPEG_PATH\",\"sort_order\":1}]}")
check "una foto ya asociada se rechaza" VALIDATION_ERROR "$(status_of "$RESP")"

# 4b. Con una foto nueva en el mismo punto → duplicado.
check "subida de la tercera foto" 200 \
  "$(up_code "$API_URL/storage/v1/object/report-photos/$P3_PATH" image/jpeg "$TMP/photo.jpg")"
RESP=$(rpc "{\"p_municipality_id\":\"$MUN_ID\",\"p_sector_id\":\"$SECTOR_ID\",$COORDS,\"p_location_source\":\"GPS\",\"p_photos\":[{\"storage_path\":\"$P3_PATH\",\"sort_order\":1}]}")
check "mismo punto → POSSIBLE_DUPLICATE" POSSIBLE_DUPLICATE "$(status_of "$RESP")"
DUP=$(psql_db -c "select count(*) from public.report_photos where storage_path = '$P3_PATH';")
check "el duplicado no se persiste" 0 "$DUP"

# ---------- 5. validación server-side del MIME ----------
RESP=$(rpc "{\"p_municipality_id\":\"$MUN_ID\",\"p_sector_id\":\"$SECTOR_ID\",\"p_latitude\":11.002,\"p_longitude\":-63.802,\"p_location_source\":\"GPS\",\"p_photos\":[{\"storage_path\":\"$GIF_PATH\",\"sort_order\":1}]}")
check "MIME no permitido rechazado por el servidor" VALIDATION_ERROR \
  "$(status_of "$RESP")"

# ---------- 6. cleanup de temporales por la API ----------
check "el usuario borra sus temporales (cleanup)" 200 "$(del "$OBJ")"
check "el usuario borra el p3 (cleanup de duplicado)" 200 \
  "$(del "$API_URL/storage/v1/object/report-photos/$P3_PATH")"
check "el usuario borra el gif rechazado" 200 "$(del "$GIFOBJ")"
check "el temporal ya no existe" 400 "$(curl -s -o /dev/null -w '%{http_code}' "$OBJ" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN")"

if [ "$FAIL" -eq 0 ]; then
  echo "Todas las pruebas E2E de create_leak_report pasaron."
  exit 0
fi
echo "Hay pruebas E2E de create_leak_report fallidas."
exit 1
