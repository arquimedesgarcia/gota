// get-report-photos — Edge Function de lectura de fotos de un reporte (Gota).
//
// Ver docs/PROMPT_15_FIX_FOTOS_SIGNED_URLS_2026-09-26.md.
//
// Reemplaza a la RPC public.get_report_photos (00033), que firmaba las URLs
// con storage.create_signed_url(...) — una función SQL que NO existe en
// Supabase. Aquí la firma se hace correctamente con service_role contra la API
// de Storage, y el cliente sigue recibiendo el MISMO contrato:
//
//   { status_code: 'OK',
//     photos: [{ id, sort_order, width, height, url, thumbnail_url }] }
//
// Flujo:
//   1. Verifica el JWT del llamador (GET /auth/v1/user) → auth_uid.
//   2. RPC get_report_photo_paths(auth_uid, report_id) con service_role
//      (gating: UNAUTHORIZED/FORBIDDEN/NOT_FOUND/RATE_LIMIT + rutas crudas).
//   3. Firma cada ruta con service_role (signed URL, TTL 900 s).
//
// Privacidad (contrato PROMPT 12): la ruta cruda (embebe el auth.uid del autor)
// NUNCA sale de esta función; el cliente solo ve signed URLs temporales.
//
// Patrón: fetch + service_role, sin supabase-js (igual que notify-push).

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://kong:8000";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// TTL de las signed URLs. Debe coincidir con _kSignedUrlTtlSeconds del cliente.
const SIGNED_URL_TTL_SECONDS = 900;
const BUCKET = "report-photos";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface RawPhoto {
  id: string;
  sort_order: number;
  width: number | null;
  height: number | null;
  storage_path: string;
  thumbnail_path: string | null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ status_code: "METHOD_NOT_ALLOWED" }, 405);
  }
  if (SERVICE_KEY === "") {
    console.error("get-report-photos: SUPABASE_SERVICE_ROLE_KEY no configurado");
    return jsonResponse({ status_code: "SERVER_ERROR" }, 500);
  }

  // ---------- 0. Entrada ----------
  let reportId: string;
  try {
    const body = await req.json();
    reportId = body?.report_id;
    if (typeof reportId !== "string" || reportId.trim() === "") {
      return jsonResponse({ status_code: "NOT_FOUND", message: "Reporte inválido." });
    }
  } catch {
    return jsonResponse({ status_code: "NOT_FOUND", message: "Solicitud inválida." });
  }

  // ---------- 1. Verificar el JWT del llamador ----------
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (token === "") {
    return jsonResponse({ status_code: "UNAUTHORIZED" });
  }

  const authUid = await resolveAuthUid(token);
  if (authUid == null) {
    return jsonResponse({ status_code: "UNAUTHORIZED" });
  }

  // ---------- 2. Gating + rutas crudas (service_role) ----------
  const rpc = await callPathsRpc(authUid, reportId);
  if (rpc == null) {
    return jsonResponse({ status_code: "SERVER_ERROR" }, 500);
  }
  const statusCode = rpc["status_code"];
  if (statusCode !== "OK") {
    // Propaga UNAUTHORIZED / FORBIDDEN / NOT_FOUND / RATE_LIMIT_EXCEEDED tal cual.
    return jsonResponse(rpc);
  }

  // ---------- 3. Firmar cada ruta ----------
  const rawPhotos: RawPhoto[] = Array.isArray(rpc["photos"]) ? rpc["photos"] : [];
  const photos: Array<Record<string, unknown>> = [];
  for (const p of rawPhotos) {
    const url = await signPath(p.storage_path);
    if (url == null) {
      // Si no podemos firmar la foto principal, la omitimos (no reventamos
      // toda la respuesta); el carrusel simplemente mostrará las que sí.
      console.error("get-report-photos: no se pudo firmar", p.storage_path);
      continue;
    }
    const thumbUrl = p.thumbnail_path != null
      ? await signPath(p.thumbnail_path)
      : null;

    photos.push({
      id: p.id,
      sort_order: p.sort_order,
      width: p.width,
      height: p.height,
      url,
      thumbnail_url: thumbUrl,
    });
  }

  return jsonResponse({ status_code: "OK", photos });
});

// ---------- Verificación del JWT del usuario ----------

async function resolveAuthUid(userToken: string): Promise<string | null> {
  try {
    const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        Authorization: `Bearer ${userToken}`,
        apikey: ANON_KEY !== "" ? ANON_KEY : SERVICE_KEY,
      },
    });
    if (!response.ok) return null;
    const user = await response.json();
    return typeof user?.id === "string" ? user.id : null;
  } catch (error) {
    console.error("get-report-photos: error verificando JWT", error);
    return null;
  }
}

// ---------- RPC (service_role) ----------

async function callPathsRpc(
  authUid: string,
  reportId: string,
): Promise<Record<string, unknown> | null> {
  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/get_report_photo_paths`,
      {
        method: "POST",
        headers: {
          apikey: SERVICE_KEY,
          Authorization: `Bearer ${SERVICE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_auth_uid: authUid, p_report_id: reportId }),
      },
    );
    if (!response.ok) {
      console.error("get-report-photos: RPC respondió", response.status);
      return null;
    }
    const data = await response.json();
    return data && typeof data === "object" ? data : null;
  } catch (error) {
    console.error("get-report-photos: RPC falló", error);
    return null;
  }
}

// ---------- Firma de una ruta de Storage (service_role) ----------

async function signPath(path: string): Promise<string | null> {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  try {
    const response = await fetch(
      `${SUPABASE_URL}/storage/v1/object/sign/${BUCKET}/${encoded}`,
      {
        method: "POST",
        headers: {
          apikey: SERVICE_KEY,
          Authorization: `Bearer ${SERVICE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ expiresIn: SIGNED_URL_TTL_SECONDS }),
      },
    );
    if (!response.ok) return null;
    const body = await response.json();
    const signed = body?.signedURL ?? body?.signedUrl;
    if (typeof signed !== "string" || signed === "") return null;
    // signedURL es relativa ("/object/sign/bucket/path?token=..."); se compone
    // con el prefijo público de Storage para que el cliente pueda descargarla.
    return `${SUPABASE_URL}/storage/v1${signed}`;
  } catch (error) {
    console.error("get-report-photos: error firmando ruta", error);
    return null;
  }
}

// ---------- utilidades ----------

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
