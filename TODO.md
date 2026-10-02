# To do

## Features
- **Apple Maps can hand cycling directions to Tileroam (routing app).** Declare `MKDirectionsApplicationSupportedModes` (bike) in Info.plist and handle the incoming `MKDirections.Request`: plan a cycling route from Maps' start to destination with Valhalla on the device, show it on the map, and offer it as GPX. Then upload `docs/appstore/routing-coverage.geojson` as the Routing App Coverage File; App Store Connect only uses it for routing apps. About half a day.
- **GitHub workflow for the routing data** (optional): build the Valhalla tiles on a runner, upload the area packs and open a pull request with the new `Tileroam/Resources/routing-benelux.json`. For now the routing data is built and uploaded from a Mac (docs/ROUTING.md).

## Before release
- **Upload the 36 routing packs:**
  ```bash
  Tools/upload_asset_packs.sh routing-benelux
  ```
  Check that App Store Connect accepts the total of 58 asset packs, including the 22 boundary packs; Apple may limit the number per app. If not, combine routing areas.
- **Merge `feature/valhalla-routing`** into `main` after testing on a device via TestFlight: plan near home, across a border, and offline in an area downloaded before.
- **Strava webhook:** in the Cloudflare Worker, add the KV binding `EVENTS` and the secrets `STRAVA_VERIFY_TOKEN` and `EVENTS_SECRET` (`/events` still answered "not_configured"). Then register the webhook:
  ```bash
  backend/strava-auth/subscribe.sh create
  ```
- **App Store Connect, App Privacy:** add *Identifiers → User ID*, and remove *Precise Location* (route planning no longer sends it); see `docs/appstore/app-privacy.md`.
- **Strava demo account** for App Review, filled in in `docs/appstore/review-notes.md`.
- **Screenshots and app preview:** check whether they need refreshing after the routing changes (status texts while planning).

## Check
- **Strava API terms:** data deletion via the webhook queue, rate limits granted for the app.
- **Trademark check** for the name "Tileroam".
- **Strava Client Secret:** preferably rotate it, since it used to be in local development builds (`StravaSecrets.plist`, now deleted); then update the Worker.
