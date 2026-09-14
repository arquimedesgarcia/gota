#!/usr/bin/env bash
# tests/storage_rls_e2e.sh — Verificación end-to-end de las políticas del
# bucket privado `report-photos` usando la API de Storage real.
#
# Cubre lo que no se puede probar con SQL puro (Supabase bloquea el DML
# directo sobre storage.objects):
#   * subida a la carpeta propia;
#   * subida a la carpeta de otro usuario (debe fallar);
#   * lectura del archivo de otro usuario (debe fallar);
#   * borrado del archivo de otro usuario (debe fallar);
#   * borrado del propio temporal (debe funcionar → habilita _cleanupUploaded).
#
# Uso (entorno local con `supabase start`):
#   bash supabase/tests/storage_rls_e2e.sh
#
# Uso contra un proyecto remoto (las claves públicas se leen del entorno):
#   SUPABASE_URL=https://<proyecto>.supabase.co \
#   SUPABASE_ANON_KEY=<anon-public> \
#   bash supabase/tests/storage_rls_e2e.sh
#
# Requiere Anonymous Sign-ins habilitado (docs/SETUP.md).
#
# Nota de higiene: los dos usuarios anónimos de auth.users creados en cada
# corrida son residuo permanente POR DISEÑO — este script no tiene handle de
# BD (no usa `docker exec ... psql`), así que no intenta borrarlos (a
# diferencia de los scripts community_*_e2e.sh). Los objetos de Storage SÍ
# se eliminan siempre vía trap EXIT, con éxito o fallo.

set -u

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  API_URL=$(npx supabase status -o env 2>/dev/null | grep '^API_URL=' | cut -d= -f2- | tr -d '"')
  ANON_KEY=$(npx supabase status -o env 2>/dev/null | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '"')
else
  API_URL="$SUPABASE_URL"
  ANON_KEY="$SUPABASE_ANON_KEY"
fi

if [ -z "$API_URL" ] || [ -z "$ANON_KEY" ]; then
  echo "NOT EXECUTED: no hay Supabase local ni SUPABASE_URL/SUPABASE_ANON_KEY."
  exit 2
fi

resolve_py() {
  for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 &&
       "$candidate" -c 'import json,sys' >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if command -v jq >/dev/null 2>&1; then
  json_get() { jq -r "$1"; }
elif PY=$(resolve_py); then
  json_get() { "$PY" -c "import sys,json;print(json.load(sys.stdin)$1)"; }
else
  echo "NOT EXECUTED: se requiere jq, python3 o python para parsear el JSON."
  exit 2
fi

# En Windows/MSYS los binarios nativos (curl) no resuelven rutas /tmp, así
# que se prefiere LOCALAPPDATA cuando existe.
if [ -n "${LOCALAPPDATA:-}" ]; then
  TMP="$LOCALAPPDATA/Temp/gota_storage_e2e"
elif [ -n "${TMPDIR:-}" ]; then
  TMP="$TMPDIR/gota_storage_e2e"
else
  TMP="/tmp/gota_storage_e2e"
fi
mkdir -p "$TMP"
printf 'gota-e2e-probe' > "$TMP/photo.jpg"

FAIL=0
check() { # check <descripción> <esperado> <obtenido>
  if [ "$2" = "$3" ]; then
    echo "PASS: $1 ($3)"
  else
    echo "FAIL: $1 (esperado $2, obtenido $3)"
    FAIL=1
  fi
}

not_ok() { # not_ok <descripción> <código que NO debe ser 200>
  if [ "$2" != "200" ]; then
    echo "PASS: $1 (bloqueado con $2)"
  else
    echo "FAIL: $1 (¡permitido con 200!)"
    FAIL=1
  fi
}

signup_anon() {
  curl -s -X POST "$API_URL/auth/v1/signup" \
    -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -d '{}' \
  | json_get "['access_token']"
}

user_id() {
  curl -s "$API_URL/auth/v1/user" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $1" \
  | json_get "['id']"
}

code() { curl -s -o "$TMP/body.txt" -w '%{http_code}' "$@"; }

TOKEN_A=$(signup_anon)
TOKEN_B=$(signup_anon)
UID_A=$(user_id "$TOKEN_A")
UID_B=$(user_id "$TOKEN_B")

if [ -z "$UID_A" ] || [ -z "$UID_B" ]; then
  echo "NOT EXECUTED: no se pudieron crear usuarios anónimos (¿Anonymous Sign-ins?)."
  exit 2
fi

BASE="$API_URL/storage/v1/object/report-photos/report_photos"
A_FILE="$BASE/$UID_A/e2e/p1.jpg"
B_FILE="$BASE/$UID_B/e2e/p1.jpg"

up() { code -X POST "$1" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $2" \
        -H "Content-Type: image/jpeg" --data-binary "@$TMP/photo.jpg"; }
down() { code "$1" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $2"; }
del() { code -X DELETE "$1" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $2"; }

cleanup() {
  # Garantiza el borrado de los dos objetos subidos, con éxito o fallo; un
  # 404 (objeto ya borrado por los checks) se ignora.
  if [ -n "${TOKEN_A:-}" ] && [ -n "${A_FILE:-}" ]; then
    del "$A_FILE" "$TOKEN_A" >/dev/null 2>&1
  fi
  if [ -n "${TOKEN_B:-}" ] && [ -n "${B_FILE:-}" ]; then
    del "$B_FILE" "$TOKEN_B" >/dev/null 2>&1
  fi
}
trap cleanup EXIT

check "A sube a su propia carpeta" 200 "$(up "$A_FILE" "$TOKEN_A")"
check "B sube a su propia carpeta" 200 "$(up "$B_FILE" "$TOKEN_B")"
not_ok "A NO puede subir a la carpeta de B" "$(up "$B_FILE" "$TOKEN_A")"
check "A lee su propio archivo" 200 "$(down "$A_FILE" "$TOKEN_A")"
not_ok "A NO puede leer el archivo de B" "$(down "$B_FILE" "$TOKEN_A")"
not_ok "A NO puede borrar el archivo de B" "$(del "$B_FILE" "$TOKEN_A")"
check "A borra su propio temporal (cleanup)" 200 "$(del "$A_FILE" "$TOKEN_A")"
not_ok "el archivo borrado ya no existe" "$(down "$A_FILE" "$TOKEN_A")"

# Limpieza del archivo restante (de B, con su propio token).
del "$B_FILE" "$TOKEN_B" >/dev/null

if [ "$FAIL" -eq 0 ]; then
  echo "Todas las pruebas E2E de Storage pasaron."
  exit 0
fi
echo "Hay pruebas E2E de Storage fallidas."
exit 1
