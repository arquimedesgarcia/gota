// notify-push — Edge Function de entrega FCM para Sprint 06 (Gota).
//
// Disparada por un Database Webhook sobre `public.notifications` (INSERT):
//
//   water_events INSERT → trigger notify_water_event → notifications INSERT
//   → Database Webhook → esta función → FCM → dispositivo.
//
// La fila de `notifications` es la fuente de verdad. Esta función es un
// efecto posterior: cualquier fallo de FCM (sin clave, red, tokens
// inválidos) se registra y responde 200 — NUNCA se revierte ni elimina
// la notification persistente.
//
// Configuración (secreto SOLO server-side, jamás en Flutter):
//   FCM_SERVER_KEY — clave de servidor del proyecto Firebase (Cloud Messaging).
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — inyectadas automáticamente.
//
// Nota (docs/MIGRATION_NOTES.md): se usa la API HTTP clásica de FCM con la
// clave de servidor por simplicidad operativa en una Edge Function. La
// migración a FCM HTTP v1 (OAuth2 con cuenta de servicio) queda documentada
// como trabajo futuro; el contrato de errores/tokens inválidos es idéntico.

import { createClient } from "jsr:@supabase/supabase-js@2";

interface WebhookRecord {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string;
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: WebhookRecord | null;
  old_record: WebhookRecord | null;
}

// Errores de FCM que confirman que el token ya no existe o no es para esta
// app: se desactiva para no volver a enviarle (docs/API_SPEC.md §7).
const FCM_FATAL_ERRORS = new Set([
  "NotRegistered",
  "InvalidRegistration",
  "MismatchSenderId",
  "InvalidPackageName",
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
    record == null || typeof record.id !== "string" ||
    typeof record.user_id !== "string" ||
    typeof record.title !== "string" || typeof record.body !== "string"
  ) {
    return jsonResponse({ ok: false, reason: "record inválido" }, 400);
  }

  const serverKey = Deno.env.get("FCM_SERVER_KEY");
  if (serverKey == null || serverKey === "") {
    // Push no configurado: la notification persistente ya existe; el push
    // simplemente no se entrega. No reintentar (200).
    console.warn("notify-push: FCM_SERVER_KEY no configurado; push omitido");
    return jsonResponse({ ok: true, pushed: false, reason: "sin FCM_SERVER_KEY" });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Tokens activos del destinatario (service role: lectura transversal
  // controlada, server-side).
  const { data: tokens, error: tokensError } = await supabase
    .from("notification_tokens")
    .select("token")
    .eq("user_id", record.user_id)
    .eq("is_active", true);

  if (tokensError) {
    console.error("notify-push: error leyendo tokens", tokensError);
    return jsonResponse({ ok: true, pushed: false, reason: "error tokens" });
  }

  const registrationIds = (tokens ?? [])
    .map((row) => row.token as string)
    .filter((token) => token.length > 0);

  if (registrationIds.length === 0) {
    return jsonResponse({ ok: true, pushed: false, reason: "sin tokens activos" });
  }

  let fcmResponse: Response;
  try {
    fcmResponse = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `key=${serverKey}`,
      },
      body: JSON.stringify({
        registration_ids: registrationIds,
        notification: {
          title: record.title,
          body: record.body,
        },
        data: {
          notification_id: record.id,
          type: record.type,
        },
      }),
    });
  } catch (error) {
    // Red/FCM caído: la notification persistente sigue intacta. 200 para
    // que el webhook no reintente en bucle.
    console.error("notify-push: FCM no respondió", error);
    return jsonResponse({ ok: true, pushed: false, reason: "fcm no disponible" });
  }

  if (!fcmResponse.ok) {
    console.error("notify-push: FCM respondió", fcmResponse.status);
    return jsonResponse(
      { ok: true, pushed: false, reason: `fcm status ${fcmResponse.status}` },
    );
  }

  // Limpieza de tokens inválidos (resultados en el mismo orden del envío).
  try {
    const result = await fcmResponse.json();
    const results: Array<{ error?: string }> = result?.results ?? [];
    const deadTokens: string[] = [];
    results.forEach((entry, index) => {
      if (entry?.error != null && FCM_FATAL_ERRORS.has(entry.error)) {
        const token = registrationIds[index];
        if (token != null) deadTokens.push(token);
      }
    });
    if (deadTokens.length > 0) {
      const { error } = await supabase
        .from("notification_tokens")
        .update({ is_active: false })
        .in("token", deadTokens);
      if (error) {
        console.error("notify-push: no se pudieron desactivar tokens", error);
      }
    }
    return jsonResponse({
      ok: true,
      pushed: true,
      sent: registrationIds.length,
      deactivated: deadTokens.length,
    });
  } catch (error) {
    console.error("notify-push: error procesando respuesta FCM", error);
    return jsonResponse({ ok: true, pushed: true, reason: "respuesta parcial" });
  }
});

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
