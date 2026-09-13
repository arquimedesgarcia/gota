// notify-push — Edge Function de entrega FCM para Sprint 06 (Gota).
//
// Disparada por un Database Webhook sobre `public.notifications` (INSERT):
//
//   water_events INSERT → trigger notify_water_event → notifications INSERT
//   → Database Webhook (supabase_functions.http_request vía pg_net)
//   → esta función → FCM HTTP v1 → dispositivo.
//
// La fila de `notifications` es la fuente de verdad. Esta función es un
// efecto posterior: cualquier fallo de FCM (sin credenciales, red, tokens
// inválidos) se registra y responde 200 — NUNCA se revierte ni elimina
// la notification persistente.
//
// Autenticación: FCM HTTP v1 (obligatorio; el endpoint Legacy está
// prohibido por el contrato de Sprint 06). OAuth2 con Service Account:
//   - FCM_SERVICE_ACCOUNT_JSON: JSON completo de la cuenta de servicio
//     Firebase (secreto SOLO server-side, docs/SETUP.md). El project_id
//     se lee del propio JSON.
// El token OAuth se firma con RS256 usando WebCrypto (sin dependencias).
//
// Correcciones Sprint 06 (post-auditoría):
//   - FCM HTTP v1 con OAuth2 (antes: Legacy + server key).
//   - data payload obligatorio: notification_id, type, water_event_id
//     (water_event_id habilita la navegación al evento desde el tap).
//   - Eliminado el uso de supabase-js: las dos consultas a la API REST
//     interna se hacen con fetch (robustez en self-hosted).

// ---------- Configuración ----------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://kong:8000";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";

// Tokens OAuth reutilizables en memoria durante la vida del worker.
let cachedToken: { value: string; expiresAt: number } | null = null;

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface WebhookRecord {
  id: string;
  user_id: string;
  water_event_id: string;
  type: string;
  title: string;
  body: string;
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: WebhookRecord | null;
  old_record: WebhookRecord | null;
}

// Errores de FCM v1 que confirman que el token ya no existe o no es de
// esta app: se desactiva para no volver a enviarle (docs/API_SPEC.md §7).
// INVALID_ARGUMENT puede deberse a payload mal formado, configuración
// incorrecta o credenciales ausentes: no indica invalidez del token.
const FCM_FATAL_ERROR_CODES = new Set([
  "UNREGISTERED",
  "SENDER_ID_MISMATCH",
]);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ ok: false, reason: "payload no es JSON" }, 400);
  }

  // Solo INSERT en notifications nos interesa.
  if (payload.type !== "INSERT" || payload.table !== "notifications") {
    return jsonResponse({ ok: true, skipped: true });
  }

  const record = payload.record;
  if (
    record == null ||
    typeof record.id !== "string" ||
    typeof record.user_id !== "string" ||
    typeof record.water_event_id !== "string" ||
    typeof record.type !== "string" ||
    (record.type !== "WATER_ARRIVED" && record.type !== "WATER_LEFT") ||
    typeof record.title !== "string" ||
    typeof record.body !== "string"
  ) {
    return jsonResponse({ ok: false, reason: "record inválido" }, 400);
  }

  if (SERVICE_ACCOUNT_JSON === "") {
    // Push no configurado: la notification persistente ya existe; el push
    // simplemente no se entrega. 200 para que el webhook no reintente.
    console.warn("notify-push: FCM_SERVICE_ACCOUNT_JSON no configurado");
    return jsonResponse({ ok: true, pushed: false, reason: "sin credenciales FCM" });
  }

  let serviceAccount: ServiceAccount;
  try {
    serviceAccount = JSON.parse(SERVICE_ACCOUNT_JSON);
    if (
      !serviceAccount.project_id || !serviceAccount.client_email ||
      !serviceAccount.private_key
    ) throw new Error("campos faltantes");
  } catch (error) {
    console.error("notify-push: FCM_SERVICE_ACCOUNT_JSON inválido", error);
    return jsonResponse({ ok: true, pushed: false, reason: "credenciales FCM inválidas" });
  }

  // Tokens activos del destinatario (service role: lectura transversal
  // controlada, server-side, nunca desde Flutter).
  const tokens = await fetchActiveTokens(record.user_id);
  if (tokens == null) {
    console.error("notify-push: error leyendo tokens");
    return jsonResponse({ ok: true, pushed: false, reason: "error tokens" });
  }
  if (tokens.length === 0) {
    return jsonResponse({ ok: true, pushed: false, reason: "sin tokens activos" });
  }

  // Token OAuth (con caché y reintento ante 401).
  let accessToken = await getAccessToken(serviceAccount);
  if (accessToken == null) {
    console.error("notify-push: no se pudo obtener token OAuth");
    return jsonResponse({ ok: true, pushed: false, reason: "oauth falló" });
  }

  let sent = 0;
  const deadTokens: string[] = [];
  for (const token of tokens) {
    const result = await sendFcmV1(
      serviceAccount.project_id,
      accessToken,
      token,
      record,
    );
    if (result === "sent") {
      sent++;
      continue;
    }
    if (result === "unauthorized") {
      // El access token expiró/revocado: refrescar una vez y reintentar.
      cachedToken = null;
      accessToken = await getAccessToken(serviceAccount);
      if (accessToken == null) break;
      if (await sendFcmV1(serviceAccount.project_id, accessToken, token, record) === "sent") {
        sent++;
      }
      continue;
    }
    if (result === "fatal") {
      deadTokens.push(token);
    }
    // "retryable": se registra y se continúa; la notification persistente
    // ya está guardada, el push se pierde sin consecuencias.
  }

  if (deadTokens.length > 0) {
    const ok = await deactivateTokens(deadTokens);
    if (!ok) console.error("notify-push: no se pudieron desactivar tokens");
  }

  return jsonResponse({
    ok: true,
    pushed: sent > 0,
    sent,
    deactivated: deadTokens.length,
  });
});

// ---------- FCM HTTP v1 ----------

type SendResult = "sent" | "unauthorized" | "fatal" | "retryable";

async function sendFcmV1(
  projectId: string,
  accessToken: string,
  deviceToken: string,
  record: WebhookRecord,
): Promise<SendResult> {
  let response: Response;
  try {
    response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            notification: { title: record.title, body: record.body },
            // data llega intacta a la app: habilita la navegación al Water
            // Event correspondiente al tocar la notificación.
            data: {
              notification_id: record.id,
              type: record.type,
              water_event_id: record.water_event_id,
            },
          },
        }),
      },
    );
  } catch (error) {
    console.error("notify-push: FCM no respondió", error);
    return "retryable";
  }

  if (response.status === 401 || response.status === 403) {
    return "unauthorized";
  }
  if (response.ok) {
    return "sent";
  }

  let errorCode = "";
  try {
    const body = await response.json();
    errorCode = body?.error?.details?.[0]?.errorCode ?? body?.error?.status ?? "";
  } catch { /* cuerpo no JSON */ }

  if (FCM_FATAL_ERROR_CODES.has(errorCode)) {
    console.warn(`notify-push: token inválido (${errorCode})`);
    return "fatal";
  }
  console.error(`notify-push: FCM respondió ${response.status}`, errorCode);
  return "retryable";
}

// ---------- OAuth2 (Service Account, RS256 con WebCrypto) ----------

async function getAccessToken(sa: ServiceAccount): Promise<string | null> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.value;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const signingInput = `${header}.${claim}`;

  let signature: string;
  try {
    const privateKey = sa.private_key.replace(/\\n/g, "\n");
    const key = await crypto.subtle.importKey(
      "pkcs8",
      pemToDer(privateKey),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const sig = await crypto.subtle.sign(
      { name: "RSASSA-PKCS1-v1_5" },
      key,
      new TextEncoder().encode(signingInput),
    );
    signature = b64url(new Uint8Array(sig));
  } catch (error) {
    console.error("notify-push: no se pudo firmar el JWT", error);
    return null;
  }

  let response: Response;
  try {
    response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: `${signingInput}.${signature}`,
      }),
    });
  } catch (error) {
    console.error("notify-push: oauth2.googleapis.com no respondió", error);
    return null;
  }

  if (!response.ok) {
    console.error("notify-push: OAuth2 respondió", response.status);
    return null;
  }
  const body = await response.json();
  if (typeof body.access_token !== "string") return null;

  cachedToken = {
    value: body.access_token,
    expiresAt: Date.now() + (body.expires_in ?? 3600) * 1000,
  };
  return cachedToken.value;
}

// ---------- API REST interna de Supabase (sin supabase-js) ----------

async function fetchActiveTokens(userId: string): Promise<string[] | null> {
  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/notification_tokens?select=token&user_id=eq.${userId}&is_active=eq.true`,
      { headers: restHeaders() },
    );
    if (!response.ok) return null;
    const rows: Array<{ token: string }> = await response.json();
    return rows.map((row) => row.token).filter((token) => token.length > 0);
  } catch {
    return null;
  }
}

async function deactivateTokens(tokens: string[]): Promise<boolean> {
  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/notification_tokens?token=in.(${tokens.join(",")})`,
      {
        method: "PATCH",
        headers: { ...restHeaders(), "Content-Type": "application/json" },
        body: JSON.stringify({ is_active: false }),
      },
    );
    return response.ok;
  } catch {
    return false;
  }
}

function restHeaders(): Record<string, string> {
  return {
    apikey: SUPABASE_SERVICE_KEY,
    Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
  };
}

// ---------- utilidades ----------

function b64url(data: string | Uint8Array): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
