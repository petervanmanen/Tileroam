# To do

## Features
- **Apple Maps can hand cycling directions to Tileroam (routing app).** Declare `MKDirectionsApplicationSupportedModes` (bike) in Info.plist and handle the incoming `MKDirections.Request`: plan a cycling route from Maps' start to destination with Valhalla on the device, show it on the map, and offer it as GPX. Then upload `docs/appstore/routing-coverage.geojson` as the Routing App Coverage File; App Store Connect only uses it for routing apps. About half a day.
- **Choose a different starting point for route planning,** instead of always the current location. For example, plan from home tonight for tomorrow's ride, or from a station or car park.
  - In planning mode: "Start: My Location", which can be changed by long-pressing the map, searching an address or place (`MKLocalSearch`), or picking a saved place such as Home.
  - The route still makes a round trip back to that start.
  - The start must lie in the routing countries; the area download follows the chosen start.
  - Show the start on the map with its own pin. Remember recent starting points.
  - `PlanStore.plan(with:)` now always uses `CurrentLocation`; `plan(from:with:)` already takes any start.
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
- **Update screenshots, privacy statements and texts** after the routing, Strava webhook and country changes:
  - **Screenshots and app previews:** retake them with the skills (`app-store-screenshots`, `app-store-previews`) once the app is final.
  - **Privacy:**
    - Re-read `PRIVACY.md` against the final app: on-device routing, area downloads from Apple, the Strava event queue.
    - Fill in App Privacy in App Store Connect from `docs/appstore/app-privacy.md`.
    - Check `Tileroam/PrivacyInfo.xcprivacy`.
  - **READMEs:**
    - The Dutch, French, Spanish and German READMEs still describe OSRM/FOSSGIS route planning, and all five say "Planning/ … (OSRM)" in the project structure.
    - The privacy sections of all five still say "no server" (the Worker now keeps Strava events).
  - **App Store texts** (`docs/appstore/metadata-*.md`): route planning works in the Netherlands, Belgium and Luxembourg only and runs on the device. Also adjust the "22 countries" wording if the boundaries are limited to the routing countries.
  - **User guide, support page and review notes:** a final check against the app.

## Check
- **Strava API terms:** data deletion via the webhook queue, rate limits granted for the app.
- **Trademark check** for the name "Tileroam".
- **Strava Client Secret:** preferably rotate it, since it used to be in local development builds (`StravaSecrets.plist`, now deleted); then update the Worker.
