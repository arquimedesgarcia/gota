const NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse";

interface ReverseRequest {
  latitude: number;
  longitude: number;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  let body: ReverseRequest;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (!validCoordinate(body.latitude) || !validCoordinate(body.longitude)) {
    return json({ error: "invalid_coordinates" }, 400);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 7000);
  try {
    const url = new URL(NOMINATIM_URL);
    url.searchParams.set("lat", String(body.latitude));
    url.searchParams.set("lon", String(body.longitude));
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("addressdetails", "1");
    url.searchParams.set("zoom", "18");

    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        "Accept": "application/json",
        "User-Agent": "Gota/0.2 reverse-geocoding",
      },
    });
    if (!response.ok) return json({ error: "provider_unavailable" }, 502);

    const raw = await response.json();
    return json(normalize(raw, body));
  } catch {
    return json({ error: "provider_unavailable" }, 502);
  } finally {
    clearTimeout(timeout);
  }
});

function normalize(raw: Record<string, unknown>, request: ReverseRequest) {
  const address = isRecord(raw.address) ? raw.address : {};
  const locality = text(address.neighbourhood) ?? text(address.quarter);
  const city = text(address.city) ?? text(address.town) ?? text(address.village);
  const municipality = text(address.county) ?? text(address.municipality);
  const state = text(address.state);
  const display = text(raw.display_name);

  return {
    latitude: request.latitude,
    longitude: request.longitude,
    display_text: display,
    locality,
    neighborhood: text(address.neighbourhood),
    city,
    municipality,
    state,
    provider: "nominatim",
    incomplete: display == null && locality == null && city == null && municipality == null,
  };
}

function validCoordinate(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}
