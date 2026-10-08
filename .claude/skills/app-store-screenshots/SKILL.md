---
name: app-store-screenshots
description: Capture Tileroam's App Store screenshots (iPhone 6.9″/6.5″ and iPad 13″) and the README images in the simulator with the sample rides, and check them. Use when the user asks for new or updated screenshots, or after UI changes that affect the screenshots.
---

# App Store screenshots

The screenshots live in `docs/appstore/screenshots/`. They come from the simulator with the bundled sample rides around Utrecht. App Store Connect accepts these sets:

| Folder | Device simulator | Size |
|---|---|---|
| `iphone-6.9` | iPhone 18 Pro Max | 1320 × 2868 |
| `iphone-6.5` | scaled from the 6.9″ captures | 1284 × 2778 (the slot the user uploads to) |
| `ipad-13` | iPad Pro 13-inch (M5) | 2064 × 2752 |

The seven shots are (there is no `04`: the Climbs shot went when the challenge was switched off in 1.15, `FeatureFlags.climbs`):
- `00-intro`
- `01-tiles`
- `02-towns`
- `03-postcodes`
- `05-trappists` (Belgium and the south of the Netherlands)
- `06-plan`
- `07-badges` (Statistics with Badges open)

**The Mac** (`mac`, 2880 × 1800, a Mac App Store size): the same shots except the plan (the Mac app has no route planning). (No Klompenpaden shot: their routes aren't licensed for redistribution, issue #69.) `Tools/capture_screenshots.sh mac` (in `capture_screenshots_mac.sh`) builds a copy of the Debug app under its own bundle ID (`nl.petervanmanen.Tileroam.screenshots`), signed ad hoc with `Tools/screenshots-mac.entitlements`: its own sandbox container with the sample rides and copies of the boundaries and the challenge files, no iCloud, no location, so the real app's data is never touched. It fixes the window at 1440 × 900 points (`-WindowSize`) and captures it with `screencapture -l`, which needs **Screen Recording permission** for the app running the script (Terminal, or Claude): System Settings → Privacy & Security → Screen Recording. Without it the script stops with "allow Screen Recording". The Mac's own light or dark appearance is used: set it to Light first.

A `settings` shot is also taken, for the README only. The README images in `docs/screenshots/` (iPhone 644 × 1400, iPad 1050 × 1400, and the `overview.jpg` strip) are made from the same captures.

## Quick way

```bash
Tools/update_screenshots.sh          # build, iPhone, iPad and Mac captures, README images (about 25 minutes)
Tools/update_screenshots.sh iphone   # only iPhone and the README
Tools/update_screenshots.sh mac      # only the Mac
```
Run it in the background with a long timeout, then check the images (step 3) and commit them. The steps below are what it does.

## Steps

1. **Build the Debug app for the simulator.** The Debug-only launch arguments are needed:
   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   xcodebuild build -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath build -quiet
   ```
2. **Capture.** Each run takes about 3–4 minutes, so run it in the background with a long timeout:
   ```bash
   Tools/capture_screenshots.sh iphone
   Tools/capture_screenshots.sh ipad
   ```
   The script does the setup itself:
   - switches the simulator to English;
   - sets the status bar to 9:41 and a full battery, and the location to Utrecht;
   - reinstalls the app and copies the sample rides into its container;
   - launches the app once per shot, then converts the captures to JPEG in the right folders.
3. **Check every image yourself.** Make 600 px previews and look at them:
   ```bash
   sips -Z 600 docs/appstore/screenshots/iphone-6.5/06-plan.jpg --out /tmp/p.jpg
   ```
   Things to look for:
   - **Not blank or white:** a white screen means the launch was still running. Raise that shot's wait in the script.
   - **The right tab is selected** for each shot.
   - **The plan shot** shows the purple route and the "Tileroam route" panel.
   - **The badges shot** shows the Statistics sheet with the badge grid open (colour and grey badges).
   - **The Trappists shot** shows the breweries as 🍺 places (from `challenges/trappist-breweries.geojson`; there are no brewery logos since 1.13).
   - **iPad status bar:** the date is in English ("Thu 1 Oct"), not Dutch.
4. **Check the sizes** (the script prints them). The JPEGs must have no transparency:
   ```bash
   sips -g hasAlpha <file>
   ```
5. Commit the changed JPEGs.

## Launch arguments (Debug builds only)

| Argument | Effect |
|---|---|
| `-RegionsDir <repo>/AssetPacks/Regions` | Reads municipality and postcode boundaries from the repo instead of asset packs. Without it, the Towns and Postcodes tabs are empty in the simulator. |
| `-mapMode squares\|gemeenten\|postcodes\|custom:<id>` | Opens on that tab (a challenge's tab is turned on with it) |
| `-challenges gemeenten,postcodes,custom:trappist-breweries` | The challenges shown at the top of the map (all off by default) |
| `-MapCenter "lat,lon,span"` | Opens the map there (span in degrees), for the Trappists shot |
| `-StatisticsOpen "badges"` | Opens those Statistics categories (with `-ShowStatistics YES`) |
| `-FocusZoom 9` | Zooms the map out one step (default 10); the Towns shot uses one less |
| `-PlanDemo YES` | Selects tiles near Utrecht and plans a route, on the device with Valhalla |
| `-PlanDemoStart "lat,lon"` | The same demo from another start, for example on a border |
| `-RoutingTar <repo>/AssetPacks/build/routing/routing-west.tar` | Routing data for the plan shot (the script passes it only when the file is there; otherwise the plan downloads its tiles from R2). Build it with `Tools/build_routing_tiles.sh west netherlands belgium luxembourg germany france switzerland austria` (see docs/ROUTING.md). |
| `-ShowStatistics YES` / `-ShowSettings YES` | Opens that screen at launch |
| `-hasSeenIntro NO` | Shows the introduction |

## Pitfalls learned
- **Slow launches:** the simulator takes 5–15 s to launch the app, because it loads system libraries on demand; the first open of a sheet is slow too. That's why the waits are 16–40 s. It isn't an app bug.
- **Launch arguments override settings:** `-mapMode` overrides `@AppStorage`, so the app can't change the tab while it's set. Don't use it when the app has to switch tabs itself; see the app-store-previews skill.
- **The 6.5″ set:** scale the 6.9″ capture to 1284 wide, then crop the height to 2778. Don't stretch it.
- **Simulator UI tool:** `mcp__Claude_Code_iOS_Simulator__control` needs the user's approval per device. `xcrun simctl io <device> screenshot` doesn't, so the script uses that.
