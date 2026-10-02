# To do

## Features
- **Apple Maps can hand cycling directions to Tileroam (routing app).** Declare `MKDirectionsApplicationSupportedModes` (bike) in Info.plist and handle the incoming `MKDirections.Request`: plan a cycling route from Maps' start to destination with Valhalla on the device, show it on the map, and offer it as GPX. Then upload `docs/appstore/routing-coverage.geojson` as the Routing App Coverage File; App Store Connect only uses it for routing apps. About half a day.
- **Municipalities and postcodes only where route maps exist** (now the Netherlands, Belgium and Luxembourg). Keeps the app consistent and the asset packs few.
  - Limit `Country.all` and the region files to the routing countries.
  - Rebuild `Tileroam/Resources/countries.fmr` (`Tools/build_country_outlines.py`) and the boundary packs.
  - Update the statistics, the texts that mention 22 countries (App Store description, user guide, READMEs, introduction, review notes) and the screenshots.
  - Decide what users with activities elsewhere see: tiles still work everywhere, municipalities and postcodes only in the routing countries.
- **Script to remove asset packs from App Store Connect** that the app no longer uses, for example the boundary packs of dropped countries and the routing packs of old builds.
  - Lists the packs in App Store Connect and compares them with what the current app version needs (the boundary countries and the routing index).
  - Asks before removing anything.
  - Transporter has no remove mode (only upload, status and list), so this needs the App Store Connect API with the existing API key. Check first which calls Apple offers for asset packs, and that a pack still used by an older app version on users' devices isn't removed too early.
- **Storage in Settings:** a "Storage" screen showing what Tileroam keeps on the device and letting users remove downloaded map data.
  - Per downloaded routing area (for example "Utrecht area, 52°N 5°E, 52 MB") and per country's boundaries, with sizes and a remove action: `AssetPackManager.remove(assetPackWithID:)`, plus clearing the matching links in `Application Support/Routing/tiles-<build>`.
  - The activity caches, also removable (they're rebuilt from the files).
  - Removed data downloads again the next time it's needed.
  - Show this in the user guide too.
- **Large map downloads only on Wi-Fi:** routing areas and boundaries above 25 MB in total are downloaded only on Wi-Fi.
  - Before downloading, check the connection with `NWPathMonitor`. Mobile data and personal hotspots count as `isExpensive`; Low Data Mode counts as `isConstrained`.
  - On mobile data with more than 25 MB to download, don't start. Say "Map data for this area (73 MB) downloads on Wi-Fi", with a "Download Anyway" button.
  - Add a setting to allow large downloads over mobile data.
  - Check how Apple's Background Assets already handle mobile data for on-demand packs, so the app doesn't contradict the system.
  - Also applies to boundary downloads (France is about 10 MB, so mostly routing).
- **GitHub workflow for the routing data** (optional): build the Valhalla tiles on a runner, upload the area packs and open a pull request with the new `Tileroam/Resources/routing-benelux.json`. For now the routing data is built and uploaded from a Mac (docs/ROUTING.md).

## Before release
- **Asset pack count:** the 36 routing packs are uploaded (2 October 2026), 58 packs in total with the boundaries. Confirm that App Store Connect accepts them for the version under review; if not, combine routing areas.
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
