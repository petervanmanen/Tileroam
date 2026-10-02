# Tileroam Strava service

A Cloudflare Worker with two jobs:

1. **Token exchange.** It exchanges and refreshes Strava tokens for the Tileroam app, so the Strava **Client Secret never ships inside the app**. The app talks to the Strava API directly; only the token requests go through this Worker, and nothing about tokens is stored or logged.
2. **Webhook event queue.** Strava tells the Worker when an athlete revokes Tileroam's access, and when activities are created or deleted.
   - The app keeps Strava data only on the user's device, so the Worker keeps these events (athlete id, activity id, type, time) for 30 days in Cloudflare KV.
   - The app reads them on launch. It deletes its copies of deleted activities, and everything it saved from Strava when access was revoked.
   - Each athlete can read only their own events, using a key the Worker hands out at login: an HMAC of the athlete id.

Endpoints:

| Endpoint | What it does |
|---|---|
| `POST /token` | Exchanges a login code or refresh token; adds `tileroam_events_key` at login |
| `GET /webhook` | Strava's subscription check |
| `POST /webhook` | Receives an event from Strava |
| `GET /events?athlete=…&key=…&since=…` | Returns the athlete's events after `since` |
| `POST /events-key` | Hands out an events key for logins made before keys existed (the app sends its Strava access token, which is checked with Strava once) |

## Set up in the Cloudflare dashboard

1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com) (a free account is enough).
2. **Workers & Pages → Create → Create Worker**, name it `tileroam-strava-auth`, and deploy the example.
3. **Edit code**, replace everything with the contents of [`worker.js`](worker.js), and **Deploy**.
4. **Storage & Databases → KV → Create**, named `tileroam-events`.
5. In the Worker: **Settings → Bindings → Add → KV namespace**. Use variable name `EVENTS` and pick `tileroam-events`.
6. In the Worker: **Settings → Variables and Secrets → Add**:
   - `STRAVA_CLIENT_ID`: your Strava Client ID (type *Text* is fine).
   - `STRAVA_CLIENT_SECRET`: your Strava Client Secret (type **Secret**).
   - `STRAVA_VERIFY_TOKEN`: any random string, for example from `openssl rand -hex 16` (type **Secret**).
   - `EVENTS_SECRET`: a long random string, for example from `openssl rand -hex 32` (type **Secret**). Changing it later invalidates the events keys; the app then fetches a new one.
7. **Give the Worker its own domain:** Workers & Pages → the Worker → Settings → Domains & Routes → Add → Custom domain, for example `tileroam.petervanmanen.nl` (the domain's DNS must be on Cloudflare). Put that URL, without a path, in `Tileroam/Servers.plist` as `StravaServiceURL`; the app adds `/token`, `/events-key` and `/events`. Keep the `workers.dev` address enabled while app versions that use it are around.
8. **Register the webhook with Strava** (once per Strava application). From the repository folder:
   ```bash
   STRAVA_CLIENT_ID=<id> STRAVA_CLIENT_SECRET=<secret> STRAVA_VERIFY_TOKEN=<same as step 6> WORKER_URL=https://tileroam-strava-auth.<your-subdomain>.workers.dev backend/strava-auth/subscribe.sh create
   ```
   Strava calls the Worker right away to check the verify token. The answer contains the subscription `id`.
9. Optional: add `STRAVA_SUBSCRIPTION_ID` (that id) as a variable. The Worker then ignores events that aren't from your subscription.

The Worker is backwards compatible. Without the KV binding and the two new secrets, `/token` works as before and the app simply gets no events.

## Or with wrangler

```bash
npx wrangler login
npx wrangler kv namespace create EVENTS        # put the printed id in wrangler.toml
npx wrangler deploy
npx wrangler secret put STRAVA_CLIENT_ID
npx wrangler secret put STRAVA_CLIENT_SECRET
npx wrangler secret put STRAVA_VERIFY_TOKEN
npx wrangler secret put EVENTS_SECRET
```

## Test

Token exchange: Strava answers with an error for an invalid token, which shows the Worker reaches Strava with your credentials:
```bash
curl -s -X POST https://tileroam-strava-auth.<your-subdomain>.workers.dev/token -H 'content-type: application/json' -d '{"grant_type":"refresh_token","refresh_token":"invalid0000"}'
```

Subscription check: the Worker should answer `{"hub.challenge":"test"}`:
```bash
curl -s "https://tileroam-strava-auth.<your-subdomain>.workers.dev/webhook?hub.mode=subscribe&hub.verify_token=<your verify token>&hub.challenge=test"
```

Current subscription:
```bash
STRAVA_CLIENT_ID=<id> STRAVA_CLIENT_SECRET=<secret> backend/strava-auth/subscribe.sh view
```

## Strava application settings

On [strava.com/settings/api](https://www.strava.com/settings/api), the *Authorization Callback Domain* must be `localhost`; the app uses `tileroam://localhost` as redirect URI.
