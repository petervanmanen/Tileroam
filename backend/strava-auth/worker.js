/**
 * Tileroam Strava service (Cloudflare Worker).
 *
 * 1. Token exchange. Keeps the Strava Client Secret out of the app: the app sends the one-time
 *    authorization code (or a refresh token) here, the Worker adds the client id and secret and
 *    forwards the request to Strava. Nothing about tokens is stored or logged.
 *
 *      POST /token  {"grant_type": "authorization_code", "code": "..."}
 *      POST /token  {"grant_type": "refresh_token", "refresh_token": "..."}
 *
 *    At login the response gets an extra "tileroam_events_key": an HMAC of the athlete id that
 *    lets the app read that athlete's events below.
 *
 * 2. Strava webhook events. Strava reports when an athlete revokes access and when activities are
 *    created or deleted. The app keeps Strava data only on the user's device, so the
 *    Worker keeps a short queue of these events (athlete id, activity id, type, time; 30 days)
 *    that the app reads on launch to delete what it must delete.
 *
 *      GET  /webhook  Strava's subscription check (hub.challenge)
 *      POST /webhook  an event from Strava
 *      GET  /events?athlete=<id>&key=<events key>&since=<unix time>
 *      POST /events-key  (Authorization: Bearer <Strava access token>) → key, for logins made
 *                        before the events key existed; checks the token with Strava once.
 *
 * Settings (Settings → Variables and Secrets, or `wrangler secret put`):
 *   STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET  the Strava application
 *   STRAVA_VERIFY_TOKEN                      any random string, also given to Strava when subscribing
 *   EVENTS_SECRET                            any long random string, signs the events keys
 *   STRAVA_SUBSCRIPTION_ID                   (optional) only accept events of this subscription
 * KV namespace binding: EVENTS
 */

const TOKEN_PATTERN = /^[A-Za-z0-9]{10,200}$/;
const EVENT_TTL = 30 * 24 * 3600;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function hmac(secret, message) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sameString(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const eventsKey = (env, athlete) => hmac(env.EVENTS_SECRET, `athlete:${athlete}`);

async function token(request, env) {
  if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET) return json({ error: "not_configured" }, 500);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const params = new URLSearchParams({ client_id: env.STRAVA_CLIENT_ID, client_secret: env.STRAVA_CLIENT_SECRET });
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
  const text = await response.text();
  if (response.ok && env.EVENTS_SECRET) {
    try {
      const data = JSON.parse(text);
      if (data.athlete?.id) {
        data.tileroam_events_key = await eventsKey(env, data.athlete.id);
        return json(data, response.status);
      }
    } catch { /* pass Strava's answer through unchanged */ }
  }
  return new Response(text, {
    status: response.status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

/** The events key for an athlete who logged in before it existed: checks the token with Strava. */
async function issueEventsKey(request, env) {
  if (!env.EVENTS_SECRET) return json({ error: "not_configured" }, 500);
  const auth = request.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9]{10,200}$/.test(auth)) return json({ error: "invalid_request" }, 400);
  const response = await fetch("https://www.strava.com/api/v3/athlete", { headers: { authorization: auth } });
  if (!response.ok) return json({ error: "unauthorized" }, 401);
  const athlete = await response.json();
  return json({ athlete: athlete.id, key: await eventsKey(env, athlete.id) });
}

/** Strava's check when the subscription is created. */
function verifySubscription(url, env) {
  const mode = url.searchParams.get("hub.mode");
  const verify = url.searchParams.get("hub.verify_token");
  const challenge = url.searchParams.get("hub.challenge");
  if (mode !== "subscribe" || !challenge || !env.STRAVA_VERIFY_TOKEN || !sameString(verify, env.STRAVA_VERIFY_TOKEN)) {
    return json({ error: "forbidden" }, 403);
  }
  return json({ "hub.challenge": challenge });
}

/** Stores the events the app needs. Strava expects a 200 within two seconds. */
async function receiveEvent(request, env) {
  let event;
  try {
    event = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (env.STRAVA_SUBSCRIPTION_ID && String(event.subscription_id) !== String(env.STRAVA_SUBSCRIPTION_ID)) {
    return json({ error: "forbidden" }, 403);
  }
  const athlete = Number(event.owner_id), time = Number(event.event_time), object = Number(event.object_id);
  if (!Number.isSafeInteger(athlete) || !Number.isSafeInteger(time) || !Number.isSafeInteger(object)) {
    return json({ ok: true }); // not one of ours to store
  }
  let type = null;
  if (event.object_type === "athlete" && String(event.updates?.authorized) === "false") type = "deauthorized";
  else if (event.object_type === "activity" && event.aspect_type === "delete") type = "deleted";
  else if (event.object_type === "activity" && event.aspect_type === "create") type = "created";
  if (type && env.EVENTS) {
    const value = { type, time, ...(event.object_type === "activity" ? { activity: object } : {}) };
    const id = crypto.randomUUID().slice(0, 8);
    await env.EVENTS.put(`ev:${athlete}:${String(time).padStart(12, "0")}:${id}`, JSON.stringify(value),
      { expirationTtl: EVENT_TTL });
  }
  return json({ ok: true });
}

/** The athlete's events after `since`, oldest first. */
async function listEvents(url, env) {
  if (!env.EVENTS || !env.EVENTS_SECRET) return json({ error: "not_configured" }, 500);
  const athlete = url.searchParams.get("athlete") ?? "";
  const key = url.searchParams.get("key") ?? "";
  const since = Number(url.searchParams.get("since") ?? "0");
  if (!/^\d{1,15}$/.test(athlete) || !sameString(key, await eventsKey(env, athlete))) {
    return json({ error: "forbidden" }, 403);
  }
  const events = [];
  let cursor;
  do {
    const page = await env.EVENTS.list({ prefix: `ev:${athlete}:`, cursor });
    for (const k of page.keys) {
      const time = Number(k.name.split(":")[2]);
      if (time <= since) continue;
      const value = await env.EVENTS.get(k.name);
      if (value) events.push(JSON.parse(value));
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return json({ events });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const route = `${request.method} ${url.pathname}`;
    switch (route) {
      case "POST /token": return token(request, env);
      case "GET /webhook": return verifySubscription(url, env);
      case "POST /webhook": return receiveEvent(request, env);
      case "GET /events": return listEvents(url, env);
      case "POST /events-key": return issueEventsKey(request, env);
      default:
        return json({ error: "not_found" }, ["/token", "/webhook", "/events", "/events-key"].includes(url.pathname) ? 405 : 404);
    }
  },
};
