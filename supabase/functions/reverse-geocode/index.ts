const NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse";
const BDC_URL = "https://api.bigdatacloud.net/data/reverse-geocode-client";

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
    // Primary: Nominatim (3.5s window).
    const nominatimRaw = await tryFetch(
      buildNominatimUrl(body.latitude, body.longitude),
      {
        signal: controller.signal,
        headers: {
          "Accept": "application/json",
          "User-Agent": "Gota/0.2 reverse-geocoding",
        },
      },
      3500,
    );
    if (nominatimRaw) {
      return json(normalizeNominatim(nominatimRaw, body));
    }

    // Fallback: BigDataCloud (remaining time up to abort).
    const bdcRaw = await tryFetch(
      buildBdcUrl(body.latitude, body.longitude),
      { signal: controller.signal },
    );
    if (bdcRaw) {
      return json(normalizeBDC(bdcRaw, body));
    }

    // All providers failed — return 200 with incomplete flag so the Flutter
    // client does not throw FunctionException and shows no error message.
    return json({
      latitude: body.latitude,
      longitude: body.longitude,
      provider: "none",
      incomplete: true,
    });
  } catch {
    return json({
      latitude: body.latitude,
      longitude: body.longitude,
      provider: "none",
      incomplete: true,
    });
  } finally {
    clearTimeout(timeout);
  }
});

// ---------- URL builders ----------

function buildNominatimUrl(lat: number, lon: number): URL {
  const url = new URL(NOMINATIM_URL);
  url.searchParams.set("lat", String(lat));
  url.searchParams.set("lon", String(lon));
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("zoom", "18");
  return url;
}

function buildBdcUrl(lat: number, lon: number): URL {
  const url = new URL(BDC_URL);
  url.searchParams.set("latitude", String(lat));
  url.searchParams.set("longitude", String(lon));
  url.searchParams.set("localityLanguage", "es");
  return url;
}

// ---------- Generic fetch helper ----------

/** Fetches a URL and returns its JSON body, or null on any failure.
 *  An optional `maxMs` cap races a timer against the fetch so that a slow
 *  provider doesn't consume the entire budget before the fallback runs.
 */
async function tryFetch(
  url: URL | string,
  options: RequestInit,
  maxMs?: number,
): Promise<Record<string, unknown> | null> {
  try {
    const fetchPromise = fetch(url, options).then(async (r) => {
      if (!r.ok) return null;
      const data = await r.json();
      return isRecord(data) ? data : null;
    });

    if (maxMs === undefined) return await fetchPromise;

    const cap = new Promise<null>((resolve) =>
      setTimeout(() => resolve(null), maxMs)
    );
    return await Promise.race([fetchPromise, cap]);
  } catch {
    return null;
  }
}

// ---------- Normalizers ----------

function normalizeNominatim(
  raw: Record<string, unknown>,
  request: ReverseRequest,
) {
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
    incomplete:
      display == null &&
      locality == null &&
      city == null &&
      municipality == null,
  };
}

function normalizeBDC(
  raw: Record<string, unknown>,
  request: ReverseRequest,
) {
  const locality = text(raw.locality);
  const city = text(raw.city);
  const state = text(raw.principalSubdivision);
  // In Venezuela, BDC 'city' typically matches the municipality name.
  const municipality = city;

  const parts = [locality, city, state].filter((v): v is string => v !== null);
  const display = parts.length > 0 ? parts.join(", ") : null;

  return {
    latitude: request.latitude,
    longitude: request.longitude,
    display_text: display,
    locality,
    neighborhood: locality,
    city,
    municipality,
    state,
    provider: "bigdatacloud",
    incomplete: display == null,
  };
}

// ---------- Utilities ----------

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
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}
