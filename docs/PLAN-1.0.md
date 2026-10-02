# Plan to version 1.0

Based on `TODO.md` and the decisions of 2 October 2026:
- **Countries:** tiles, routes and statistics work everywhere. Municipalities and postcodes only cover the Netherlands, Belgium and Luxembourg, the same as route planning.
- **In 1.0:**
  - the Wi-Fi rule for large downloads;
  - the Storage screen;
  - choosing a starting point, without saved places (map and search, plus recent starts);
  - ~~the Apple Maps routing app~~ (skipped, after 1.0).
- **Unused asset packs:** removed with a reusable cleanup script, built first.

Each phase gets its own branch and a pull request into `main`, and ends with tests and a TestFlight build. You install it from TestFlight via Actions → TestFlight → Run workflow on the branch. Estimates are working time on my side; your steps are marked **(you)**.

## Phase 0: Finish what's in progress
1. **(you)** Test `feature/valhalla-routing` via TestFlight:
   - a route near home;
   - a route across a border;
   - planning in airplane mode in an area downloaded before;
   - a start outside the Benelux.
2. Merge `feature/valhalla-routing` into `main`.
3. **(you)** Finish the Strava webhook in Cloudflare:
   - add the KV binding `EVENTS` and the secrets `STRAVA_VERIFY_TOKEN` and `EVENTS_SECRET`;
   - run `backend/strava-auth/subscribe.sh create`;
   - I verify the endpoints afterwards.

## Phase 1: Municipalities and postcodes for the Benelux only (½ day)
Branch `feature/benelux-areas`.
1. **Countries:** reduce `Country.all` to NL, BE and LU, and rebuild `Resources/countries.fmr`.
   - Country detection then only finds those three. Elsewhere activities still give tiles, routes and statistics, just no municipalities or postcodes.
2. **Statistics:** check the overview and the per-country section with activities outside the Benelux (shown as 0 countries or nothing, not as an error).
3. **Tests:** update `GeoTests`, which check all 22 countries, and the country-outline tests (Paris, Vaduz, Reykjavík become "outside").
4. **Texts:** the introduction ("22 European countries"), Sources & Licenses (keep only NL/BE/LU), translations in five languages.
5. **Data:**
   - remove the 19 other countries' files from `AssetPacks/Regions`;
   - shrink `DATA-LICENSES.md` and the README tables accordingly;
   - mark the dropped boundary packs for phase 2.

## Phase 2: Asset pack cleanup script (½–1 day)
Branch `feature/asset-pack-cleanup`.
1. **Research first:** which App Store Connect API calls Apple offers for asset packs (listing, versions, removing or archiving), and what happens to a pack that a released app version still uses.
2. **`Tools/clean_asset_packs.sh`:**
   - **Wanted:** collects the packs the current app needs: the boundary countries from `Country.all` and the routing packs from `Resources/routing-*.json`.
   - **Present:** lists the packs in App Store Connect via the API, authenticated with the API key. A small Swift script signs the token with CryptoKit, so nothing needs installing.
   - **Shows the difference** and only removes after confirmation. It has a `--dry-run` mode.
3. **First run:** the 19 boundary packs of the dropped countries. No released app version uses them yet.
4. Document it in `docs/appstore/README.md` and `docs/ROUTING.md` (old routing builds).

## Phase 3: Downloads on Wi-Fi and the Storage screen (1 day)
Branch `feature/storage`. These belong together: both work with what's downloaded and how big it is.
1. **Download decision in one place** (`MapDataDownloads`):
   - adds up what a plan or a country would download;
   - checks the connection (`NWPathMonitor`: expensive or constrained means not Wi-Fi);
   - decides "download", "wait for Wi-Fi" or "ask".
2. **Wi-Fi rule:** over 25 MB on mobile data, the planning panel says "Map data for this area (73 MB) downloads on Wi-Fi", with **Download Anyway**. The same applies to boundary downloads.
3. **Setting:** "Download map data over mobile data", default off.
4. **Check** how Background Assets itself handles mobile data for on-demand packs, so the app doesn't promise something the system blocks.
5. **Storage screen** in Settings → Storage:
   - routing areas on the device, with a readable name ("Utrecht area"), size and **Remove**, which removes the pack and its tile links;
   - boundaries per country, with Remove (they reload when needed);
   - activity caches, with **Clear**, which rebuilds them;
   - a total at the top.
6. **Tests and translations;** add it to the user guide.

## Phase 4: Choose a starting point (1 day)
Branch `feature/start-point`.
1. The planning panel shows **"Start: My Location"**. Tapping it opens:
   - **Search** (`MKLocalSearch`, places and addresses);
   - **Pick on the map** (long-press);
   - **Recent starting points** (the last 5, kept on the device);
   - **My Location.**
2. The start gets its own pin. The round trip begins and ends there.
3. The start must lie in the Benelux, with the existing clear message otherwise. The area download follows the start.
4. `PlanStore`: the start is part of the plan instead of always `CurrentLocation`. The demo, screenshots and preview keep working.
5. **Tests:** planning with a fixed start (engine test on the Luxembourg build), and saving recent starts.

## Phase 5: Apple Maps routing app (½–1 day): skipped for 1.0
Skipped on 2 October 2026; it stays in TODO.md for a later version. Until then, don't upload the Routing App Coverage File: App Store Connect only accepts it for routing apps.

Branch `feature/routing-app`.
1. **Info.plist:** `MKDirectionsApplicationSupportedModes` = bike.
2. **Receiving requests:** handle Maps' directions request via the scene's URL handling (`MKDirections.Request(contentsOf:)`).
3. **One-way routes:** the planner now only makes round trips through targets. It gets an A → B mode: Valhalla route from Maps' start to destination, without targets.
4. **Showing the result:** the route on the map, with "New: n tiles…" (the same coverage calculation), Share GPX and Save.
5. **Outside the Benelux:** the existing message.
6. **(you)** Upload `docs/appstore/routing-coverage.geojson` as the Routing App Coverage File on the version page.
7. **Test** in the simulator: open a directions request in Maps and choose Tileroam.

## Phase 6: Release preparation (1 day, plus your steps)
Branch `release/1.0`.
1. **READMEs in five languages:**
   - on-device route planning instead of OSRM;
   - the Benelux scope;
   - "no server" → the Strava event queue;
   - the project structure.
2. **App Store texts in English and Dutch:**
   - route planning in the Benelux, on the device;
   - no "22 countries";
   - the new features (starting point, Apple Maps);
   - check the limits with `check_metadata.py`.
3. **Privacy:**
   - re-read `PRIVACY.md`, `app-privacy.md` and the privacy manifest against the final app;
   - **(you)** fill in App Privacy in App Store Connect: add User ID, remove Precise Location.
4. **User guide, support page and review notes:**
   - the new features;
   - the Benelux;
   - how to test routing in review (location in the Netherlands).
5. **Screenshots and app previews:** retake them with the skills. The preview tour gets the starting point if it fits in 30 seconds.
6. **(you)** Strava demo account for App Review, in the review notes.
7. **(you)** Final checks:
   - App Store Connect accepts the asset packs for the version;
   - Strava API terms and rate limits;
   - trademark "Tileroam";
   - optionally rotate the Strava secret.
8. Version 1.0, tag `v1.0.0`, TestFlight, then submit.

## Order and dependencies
- **Phase 0** comes first; the rest builds on `main` with the routing.
- **Phase 1 before phase 2:** the cleanup needs the final country list.
- **Phases 3, 4 and 5** are independent of each other. Phase 4 before 5 is easiest, because both change how a plan starts.
- **Phase 6** comes last: texts and screenshots reflect the final app.

**Total:** about 5–6 working days on my side, plus your TestFlight tests and App Store Connect steps.
