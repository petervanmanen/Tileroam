# To do

The plan and order for version 1.0 are in [docs/PLAN-1.0.md](docs/PLAN-1.0.md). Decisions of 2 October 2026:
- **In 1.0:** all features below except the GitHub routing workflow.
- **Countries:** tiles everywhere, municipalities and postcodes only in the routing countries.
- **Starting points:** no saved places.
- **Cleanup:** script first.

## Features
- **After 1.0: Apple Maps can hand cycling directions to Tileroam (routing app).** Skipped for 1.0 (decision of 2 October 2026), so don't upload the coverage file yet. Declare `MKDirectionsApplicationSupportedModes` (bike) in Info.plist and handle the incoming `MKDirections.Request`: plan a cycling route from Maps' start to destination with Valhalla on the device, show it on the map, and offer it as GPX. Then upload `docs/appstore/routing-coverage.geojson` as the Routing App Coverage File; App Store Connect only uses it for routing apps. About half a day.
- ~~Choose a different starting point~~: done on `feature/start-point` (phase 4). "Start: My Location" in the planning panel opens a picker with search (`MKLocalSearchCompleter`), My Location and the last five starts; long-pressing the map sets the start there, as a green flag that can be dragged. The start is checked against the routing countries right away.
- ~~Municipalities and postcodes only where route maps exist~~: done on `feature/benelux-areas` (phase 1). The boundary packs of the 19 dropped countries are still in App Store Connect; they're removed with the cleanup script (phase 2).
- ~~Script to remove asset packs from App Store Connect~~: done as `Tools/clean_asset_packs.sh` (phase 2). Apple's API can't delete or archive packs, so the script lists missing and unused packs and archiving happens on the website. Archiving the 19 dropped boundary packs (`regions-DE`, `regions-FR`, …) is skipped for now: the app doesn't request them, so they do no harm.
- ~~Storage in Settings~~: done on `feature/storage` (phase 3). Settings → Storage lists the downloaded routing areas (named after a nearby town, with size; swipe or "Remove All" to delete), the boundaries per country (info only, they reload automatically) and the activity cache with "Clear Cache & Re-import".
- ~~Large map downloads only on Wi-Fi~~: done on `feature/storage` (phase 3). Above 25 MB, routing areas wait for Wi-Fi (`NWPathMonitor`: not expensive, not constrained), with "Download Anyway" and a setting "Download Map Data over Mobile Data". Background Assets has no mobile-data policy for on-demand packs, so the rule lives in the app. Boundary packs are under 1 MB, so they're left out of the rule.
- **GitHub workflow for the routing data** (optional): build the Valhalla tiles on a runner, upload the area packs and open a pull request with the new `Tileroam/Resources/routing-benelux.json`. For now the routing data is built and uploaded from a Mac (docs/ROUTING.md).

## Before release
- **Asset pack count:** the 36 routing packs are uploaded (2 October 2026), 58 packs in total with the boundaries. Confirm that App Store Connect accepts them for the version under review; if not, combine routing areas.
- **Test routing on a device** via TestFlight: plan near home, across a border, from a chosen starting point, and offline in an area downloaded before. (`feature/valhalla-routing` is already in `main`.)
- ~~Strava webhook~~: done (2 October 2026). Worker configured (KV binding `EVENTS`, `EVENTS_SECRET`, `STRAVA_VERIFY_TOKEN`), Strava subscription 375082. Optional: set `STRAVA_SUBSCRIPTION_ID` = 375082 in the Worker.
- **App Store Connect, App Privacy:** add *Identifiers → User ID*, and remove *Precise Location* (route planning no longer sends it); see `docs/appstore/app-privacy.md`.
- **Strava demo account** for App Review, filled in in `docs/appstore/review-notes.md`.
- ~~Update screenshots, privacy statements and texts~~: done on `release/1.0` (phase 6):
  - READMEs in five languages, `PRIVACY.md` (starting point search and address lookup via Apple's MapKit), `app-privacy.md`, App Store texts (en, nl), support FAQ, review notes (try planning by searching "Utrecht Centraal" as the starting point).
  - Screenshots (iPhone 6.9″ and 6.5″, iPad 13″) and app previews, with the starting point in the plan shot and the tour.
  - Left: the README images in `docs/screenshots/` are older captures; the App Store ones are current.
- **Release (you):** merge the open PRs, then push the tag `v1.0.0`. The TestFlight workflow builds version 1.0.0 and uploads it. Test it from TestFlight, then submit for review in App Store Connect.

## Check
- **Strava API terms:** data deletion via the webhook queue, rate limits granted for the app.
- **Trademark check** for the name "Tileroam".
- **Strava Client Secret:** preferably rotate it, since it used to be in local development builds (`StravaSecrets.plist`, now deleted); then update the Worker.
