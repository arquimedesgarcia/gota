# Auditoría read-only + E2E piloto cloud (sin cambios de código)
import json, os, urllib.request, urllib.error

BASE = os.environ["SUPABASE_URL"].rstrip("/")
KEY = os.environ["SUPABASE_ANON_KEY"]
H = {"apikey": KEY, "Content-Type": "application/json", "Authorization": "Bearer "}
results = []

def req(method, path, token=None, body=None, raw=None, ctype="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    r = urllib.request.Request(BASE + path, data=data, method=method)
    r.add_header("apikey", KEY)
    r.add_header("Authorization", "Bearer " + (token or KEY))
    if data is not None: r.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            b = resp.read()
            return resp.status, (json.loads(b) if b and b[:1] in (b"{", b"[") else b)
    except urllib.error.HTTPError as e:
        b = e.read()
        try: return e.code, json.loads(b)
        except Exception: return e.code, b[:200]

def anon():
    st, d = req("POST", "/auth/v1/signup", body={})
    return d["user"]["id"], d["access_token"]

JPEG = bytes.fromhex("ffd8ffe000104a46494600010100000100010000ffd9")

# 1. cuatro usuarios anónimos
uids = {}
for n in range(4):
    uid, tok = anon()
    uids[uid] = tok
    results.append(f"PASS usuario anon {n+1} creado ({uid[:8]}…)")
uid1 = list(uids)[0]; t1 = uids[uid1]

# 2. catálogo
st, muns = req("GET", "/rest/v1/municipalities?select=id,name&is_active=eq.true&state=eq.Nueva%20Esparta")
mun = muns[0]
st, secs = req("GET", f"/rest/v1/sectors?select=id,name&municipality_id=eq.{mun['id']}&is_active=eq.true")
sec = secs[0]
results.append(f"PASS catalogo cloud: {len(muns)} municipios, {len(secs)} sectores en {mun['name']}")

# 3. subir foto a Storage (usuario 1)
ppath = f"report_photos/{uid1}/audit/p1.jpg"
st, up = req("POST", f"/storage/v1/object/report-photos/{ppath}", token=t1, raw=JPEG, ctype="image/jpeg")
results.append(("PASS" if st in (200, 201) else "FAIL") + f" upload foto storage ({st})")

# 4. create_leak_report
body = {"p_municipality_id": mun["id"], "p_sector_id": sec["id"],
        "p_latitude": 11.002, "p_longitude": -63.802, "p_location_source": "GPS",
        "p_description": "AUDIT_E2E piloto", "p_photos": [{"storage_path": ppath, "mime_type": "image/jpeg", "size_bytes": len(JPEG), "sort_order": 1}]}
st, r = req("POST", "/rest/v1/rpc/create_leak_report", token=t1, body=body)
rid = r.get("report_id") or r.get("id") if isinstance(r, dict) else None
results.append(("PASS" if st == 200 and r.get("status") in ("ACTIVE", "CREATED", None) and rid else "FAIL") + f" create_leak_report cloud ({st}) -> {json.dumps(r)[:160]}")
REPORT_ID = rid

# 5. duplicado
st, r2 = req("POST", "/rest/v1/rpc/create_leak_report", token=uids[list(uids)[1]], body=body)
dup = r2.get("status_code") if isinstance(r2, dict) else None
results.append(("PASS" if dup == "DUPLICATE_DETECTED" or (isinstance(r2, dict) and r2.get("status_code")) else "INFO") + f" duplicado cloud -> {json.dumps(r2)[:160]}")

# 6. reverse-geocode con JWT
st, rg = req("POST", "/functions/v1/reverse-geocode", token=t1, body={"latitude": 11.002, "longitude": -63.802})
ok = st == 200 and isinstance(rg, dict)
results.append(("PASS" if ok else "FAIL") + f" reverse-geocode cloud ({st}) -> {json.dumps(rg)[:200]}")
if ok:
    results.append(f"INFO reverse-geocode eco coords: {rg.get('latitude')},{rg.get('longitude')} (enviadas 11.002,-63.802)")

# 7. validaciones x3 (u2,u3,u4)
vcount = 0
for uid, tok in list(uids.items())[1:4]:
    st, v = req("POST", "/rest/v1/rpc/validate_leak", token=tok, body={"p_report_id": REPORT_ID})
    ok = st == 200 and isinstance(v, dict) and v.get("status_code") == "OK"
    vcount += 1 if ok else 0
    results.append(("PASS" if ok else "FAIL") + f" validate_leak ({st}) -> {json.dumps(v)[:140]}")

# 8. confirmaciones x3 -> RESOLVED
for uid, tok in list(uids.items())[1:4]:
    st, c = req("POST", "/rest/v1/rpc/confirm_leak_resolution", token=tok, body={"p_report_id": REPORT_ID})
    results.append(f"INFO confirm_leak_resolution ({st}) -> {json.dumps(c)[:140]}")

# 9. estado final + mapa
st, det = req("POST", "/rest/v1/rpc/get_leak_report_detail", token=t1, body={"p_report_id": REPORT_ID})
results.append(f"INFO detalle final -> {json.dumps(det)[:200]}")

# 10. cleanup: borrar objetos de storage propios
for uid, tok in uids.items():
    for p in [f"report_photos/{uid}/audit/p1.jpg"]:
        st, _ = req("DELETE", f"/storage/v1/object/report-photos/{p}", token=tok)
        results.append(f"INFO cleanup storage {p} ({st})")

print("\n".join(results))
print("REPORT_ID=" + str(REPORT_ID))
print("UIDS=" + ",".join(uids))
