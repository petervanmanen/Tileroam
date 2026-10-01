/**
 * Tileroam Strava token service (Cloudflare Worker).
 *
 * Keeps the Strava Client Secret out of the app: the app sends the one-time
 * authorization code (or a refresh token) here, the Worker adds the client id
 * and secret and forwards the request to Strava. Nothing is stored or logged.
 *
 *   POST /token  {"grant_type": "authorization_code", "code": "..."}
 *   POST /token  {"grant_type": "refresh_token", "refresh_token": "..."}
 *
 * Secrets (Settings → Variables and Secrets, or `wrangler secret put`):
 *   STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET
 */

const TOKEN_PATTERN = /^[A-Za-z0-9]{10,200}$/;

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/token") return json({ error: "not_found" }, 404);
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET) return json({ error: "not_configured" }, 500);

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

    const params = new URLSearchParams({
      client_id: env.STRAVA_CLIENT_ID,
      client_secret: env.STRAVA_CLIENT_SECRET,
    });
    if (body.grant_type === "authorization_code" && TOKEN_PATTERN.test(body.code ?? "")) {
      params.set("grant_type", "authorization_code");
      params.set("code", body.code);
    } else if (body.grant_type === "refresh_token" && TOKEN_PATTERN.test(body.refresh_token ?? "")) {
      params.set("grant_type", "refresh_token");
      params.set("refresh_token", body.refresh_token);
    } else {
      return json({ error: "invalid_request" }, 400);
    }

    const response = await fetch("https://www.strava.com/oauth/token", { method: "POST", body: params });
    return new Response(await response.text(), {
      status: response.status,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  },
};
