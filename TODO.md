# To do

The plan and order for version 1.0 are in [docs/PLAN-1.0.md](docs/PLAN-1.0.md). Decisions of 2 October 2026:
- **In 1.0:** all features below except the GitHub routing workflow.
- **Countries:** tiles everywhere, municipalities and postcodes only in the routing countries.
- **Starting points:** no saved places.
- **Cleanup:** script first.

## Features
- **Apple Maps can hand cycling directions to Tileroam (routing app).** Declare `MKDirectionsApplicationSupportedModes` (bike) in Info.plist and handle the incoming `MKDirections.Request`: plan a cycling route from Maps' start to destination with Valhalla on the device, show it on the map, and offer it as GPX. Then upload `docs/appstore/routing-coverage.geojson` as the Routing App Coverage File; App Store Connect only uses it for routing apps. About half a day.
- **Choose a different starting point for route planning,** instead of always the current location. For example, plan from home tonight for tomorrow's ride, or from a station or car park.
  - In planning mode: "Start: My Location", which can be changed by long-pressing the map or searching an address or place (`MKLocalSearch`). No saved places; recent starting points are remembered.
  - The route still makes a round trip back to that start.
  - The start must lie in the routing countries; the area download follows the chosen start.
  - Show the start on the map with its own pin. Remember recent starting points.
  - `PlanStore.plan(with:)` now always uses `CurrentLocation`; `plan(from:with:)` already takes any start.
- ~~Municipalities and postcodes only where route maps exist~~: done on `feature/benelux-areas` (phase 1). The boundary packs of the 19 dropped countries are still in App Store Connect; they're removed with the cleanup script (phase 2).
- ~~Script to remove asset packs from App Store Connect~~: done as `Tools/clean_asset_packs.sh` (phase 2). Apple's API can't delete or archive packs, so the script lists missing and unused packs and archiving happens on the website. **(you)** Run it and archive the 19 dropped boundary packs (`regions-DE`, `regions-FR`, …).
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
- ~~Strava webhook~~: done (2 October 2026). Worker configured (KV binding `EVENTS`, `EVENTS_SECRET`, `STRAVA_VERIFY_TOKEN`), Strava subscription 375082. Optional: set `STRAVA_SUBSCRIPTION_ID` = 375082 in the Worker.
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
