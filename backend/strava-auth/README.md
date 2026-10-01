# Tileroam Strava token service

A Cloudflare Worker that exchanges and refreshes Strava tokens for the Tileroam
app, so the Strava **Client Secret never ships inside the app**. The app talks to
the Strava API directly; only the two token requests go through this Worker. It
stores and logs nothing.

## Set up in the Cloudflare dashboard (no tools needed)

1. Sign in at [dash.cloudflare.com](https://dash.cloudflare.com) (a free account is enough).
2. **Workers & Pages → Create → Create Worker**, name it `tileroam-strava-auth`, and deploy the example.
3. **Edit code**, replace everything with the contents of [`worker.js`](worker.js), and **Deploy**.
4. **Settings → Variables and Secrets → Add**:
   - `STRAVA_CLIENT_ID`: your Strava Client ID (type *Text* is fine)
   - `STRAVA_CLIENT_SECRET`: your Strava Client Secret (type **Secret**)
5. Copy the Worker URL, for example `https://tileroam-strava-auth.<your-subdomain>.workers.dev`.
6. In the app project, put that URL followed by `/token` in `Tileroam/StravaConfig.plist`
   as `TokenServiceURL` (see `StravaConfig.example.plist`).

## Or with wrangler

```bash
npx wrangler login
npx wrangler deploy
npx wrangler secret put STRAVA_CLIENT_ID
npx wrangler secret put STRAVA_CLIENT_SECRET
```

## Test

```bash
curl -s -X POST https://tileroam-strava-auth.<your-subdomain>.workers.dev/token \
  -H 'content-type: application/json' -d '{"grant_type":"refresh_token","refresh_token":"invalid0000"}'
```

Strava answers with an error for an invalid token, which shows the Worker reaches Strava with your
credentials. Anything other than `/token` with a JSON body returns 400/404.

## Strava application settings

On [strava.com/settings/api](https://www.strava.com/settings/api), the *Authorization Callback
Domain* must be `localhost` (the app uses `tileroam://localhost` as redirect URI).
