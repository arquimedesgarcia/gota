#!/usr/bin/env bash
# Verificación del catálogo piloto: que un usuario anónimo pueda crear un
# reporte REAL (con foto subida a Storage) en un sector sembrado de
# Maneiro / Mariño / Arismendi.
#
# Uso: bash supabase/tests/pilot_catalog_e2e.sh
set -u

cd "$(dirname "$0")/../.."

API_URL="${API_URL:-http://localhost:54321}"
DB_URL="${DB_URL:-}"
if [ -z "$DB_URL" ]; then
  docker exec -i supabase_db_gota true 2>/dev/null \
    || { echo "NOT EXECUTED: contenedor supabase_db_gota caído."; exit 2; }
fi

eval "$(npx supabase status -o env 2>/dev/null | grep -i '^ANON_KEY=' || true)"
if [ -z "${ANON_KEY:-}" ]; then
  echo "NOT EXECUTED: no se pudo obtener ANON_KEY (¿supabase start?)."; exit 2
fi

TMP="${TMPDIR:-$LOCALAPPDATA/Temp}"
[ -d "$TMP" ] || TMP=.
mkdir -p "$TMP"
PHOTO="$TMP/gota_pilot.jpg"
# JPEG mínimo válido, escrito por python (evita problemas de binarios en MSYS).
python - <<'PY' "$PHOTO"
import sys
path = sys.argv[1]
jpg = (b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
       b"\xff\xdb\x00C\x00" + b"\x40" * 64 + b"\xff\xd9")
open(path, "wb").write(jpg)
PY

H_KEY=$(printf '%s: %s' 'apikey' "$ANON_KEY")
h_auth() { printf '%s: %s %s' 'Authorization' 'Bearer' "$1"; }
json_get() { python -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1],{'d':d}))" "$1" 2>/dev/null \
             || python -c "import sys,json;d=json.load(sys.stdin);print('')" ; }

psql_q() { docker exec -i supabase_db_gota psql -q -U postgres -d postgres -v ON_ERROR_STOP=1 -t -A "$@"; }

TOKEN=$(curl -s -X POST "$API_URL/auth/v1/signup" -H "$H_KEY" \
  -H "Content-Type: application/json" -d '{}' | json_get "d['access_token']")
UIDU=$(curl -s "$API_URL/auth/v1/user" -H "$H_KEY" -H "$(h_auth "$TOKEN")" | json_get "d['id']")

if [ -z "${UIDU:-}" ] || [ "$UIDU" = "None" ]; then
  echo "NOT EXECUTED: no se pudo crear usuario anónimo (¿Anonymous Sign-ins?)."; exit 2
fi
echo "Usuario anónimo: $UIDU"

FAIL=0
ok()   { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (esperado $3, obtenido $2)"; FAIL=1; fi; }

# 1. Subir foto propia a Storage.
UP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$API_URL/storage/v1/object/report-photos/report_photos/$UIDU/pilot/p1.jpg" \
  -H "$H_KEY" -H "$(h_auth "$TOKEN")" -H "Content-Type: image/jpeg" \
  --data-binary "@$PHOTO")
ok "Foto subida a Storage" "$UP_CODE" "200"

# 2. Crear reporte en un sector real de Mariño.
PHOTO_PATH="report_photos/$UIDU/pilot/p1.jpg"
RES=$(psql_q -c "
begin;
set local role authenticated;
set request.jwt.claims = '{\"role\":\"authenticated\",\"sub\":\"$UIDU\",\"aud\":\"authenticated\"}';
select public.ensure_app_user() is not null as u;
select public.create_leak_report(
  p_municipality_id := '00000000-0000-4000-8000-000000000003',
  p_sector_id       := (select id from public.sectors
                        where name='Genovés'
                          and municipality_id='00000000-0000-4000-8000-000000000003' limit 1),
  p_latitude        := 10.9581,
  p_longitude       := -63.8511,
  p_location_source := 'GPS',
  p_description     := 'Reporte piloto automatico en sector real de Marino',
  p_photos          := jsonb_build_array(jsonb_build_object('storage_path','$PHOTO_PATH')))->>'status_code';
rollback;")
echo "$RES"
echo "$RES" | grep -q "CREATED" && echo "PASS: reporte creado en sector real" \
  || { echo "FAIL: reporte no creado"; FAIL=1; }

# 3. El catálogo es legible por anon vía PostgREST.
MUNS=$(curl -s "$API_URL/rest/v1/municipalities?select=name&state=eq.Nueva%20Esparta&is_active=eq.true" \
  -H "$H_KEY" | python -c "import sys,json;print(len(json.load(sys.stdin)))")
ok "Municipios visibles para anon (3)" "$MUNS" "3"

SECS=$(curl -s "$API_URL/rest/v1/sectors?select=id&is_active=eq.true" -H "$H_KEY" \
  | python -c "import sys,json;print(len(json.load(sys.stdin)))")
ok "Sectores activos visibles para anon (96)" "$SECS" "96"

# Limpieza.
curl -s -o /dev/null -X DELETE \
  "$API_URL/storage/v1/object/report-photos/report_photos/$UIDU/pilot/p1.jpg" \
  -H "$H_KEY" -H "$(h_auth "$TOKEN")"

echo "---"
[ "$FAIL" = "0" ] && echo "RESULTADO: OK" || echo "RESULTADO: FALLOS"
exit "$FAIL"
