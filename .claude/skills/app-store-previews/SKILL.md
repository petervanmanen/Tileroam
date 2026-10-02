---
name: app-store-previews
description: Record Tileroam's App Store app preview videos (iPhone 6.5″ and iPad 13″) in the simulator from the scripted in-app tour, convert them to App Store specs and check them. Use when the user asks for new or updated app previews or recordings, or after UI changes that affect the tour.
---

# App Store app previews

The videos live in `docs/appstore/previews/`.

| File | Size | Simulator | Focus zoom |
|---|---|---|---|
| `iphone-6.5.mov` | 886 × 1920 | iPhone 18 Pro Max | 9 |
| `ipad-13.mov` | 1200 × 1600 | iPad Pro 13-inch (M5) | 10 |

Apple's rules:
- 15–30 seconds;
- H.264 at 30 fps, no audio track needed;
- footage from the app only: no hands, devices or other apps.

## How it works
- **The tour:** the app plays it itself with the Debug-only `-PreviewTour YES`, in `runPreviewTour()` in `Tileroam/Views/ContentView.swift`:
  1. Tiles (3 s).
  2. Towns (2.5 s).
  3. Postcodes (2.5 s).
  4. Route planning: sets the starting point (Utrecht Centrum, green flag), selects 4 tiles, a municipality and a postcode at 0.4 s each (`PlanStore.planDemoRoute(with:pace:)`), plans, and shows the route for 3.5 s.
  5. Statistics (4 s).

  It prints `PREVIEW_TOUR_START <unix time>` and `PREVIEW_TOUR_END <unix time>`.
- **`Tools/record_app_preview.sh <device> <out.mov> <width> <height> <focus zoom>`:**
  1. Installs the app with the sample rides.
  2. Does a warm-up launch, so the rides are imported and cached.
  3. Records the screen with `simctl io recordVideo` while the tour runs.
  4. Cuts at the markers; the recording's start is its file creation time.
  5. Calls `Tools/make_app_preview.swift`, which trims, scales to fill, crops the middle and sets 30 fps H.264, using AVFoundation (no ffmpeg on this Mac).

## Steps
1. Build the Debug app for the simulator:
   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   xcodebuild build -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath build -quiet
   ```
2. Record both, in the background; each takes about a minute:
   ```bash
   Tools/record_app_preview.sh "iPhone 18 Pro Max" docs/appstore/previews/iphone-6.5.mov 886 1920 9
   Tools/record_app_preview.sh "iPad Pro 13-inch (M5)" docs/appstore/previews/ipad-13.mov 1200 1600 10
   ```
3. Check each video, then look at the contact sheet. The check prints size, frame rate, codec, duration and audio tracks:
   ```bash
   swift Tools/check_app_preview.swift docs/appstore/previews/iphone-6.5.mov /tmp/sheet.png
   ```
   Expect:
   - **Specs:** the exact size, `fps 30.0`, `codec avc1`, a duration of 15–30 s, and `audio tracks 0`.
   - **The sheet** shows the Tiles, Towns and Postcodes tabs in turn, then the planning panel with selected (orange) items, the purple route with the "Tileroam route" panel, and the Statistics sheet last.
4. Commit the videos.

## Pitfalls learned
- **Never pass `-mapMode`** to the tour: launch arguments override `@AppStorage`, and the tab switches silently don't happen. The tour sets `mode = .squares` itself.
- **Strip carriage returns:** `simctl launch --console-pty` output ends lines with `\r`, which breaks shell arithmetic. The script uses `tr -d '\r'`.
- **Duration varies:** route planning (Valhalla on the device; needs `AssetPacks/build/routing/routing-benelux.tar`, see docs/ROUTING.md) takes a little longer the first time, so the length varies by a few seconds. The script caps at 30 s and fails if the result is under 15 s. If Statistics gets cut off, shorten the waits in `runPreviewTour()`.
- **Blank start:** if the first frames show the map without tiles, raise the 6 s wait before `PREVIEW_TOUR_START`.
- **Route behind Statistics:** right after planning ends, the route can stay visible behind the Statistics sheet for a few seconds. That's MapKit redrawing slowly in the simulator, not a bug; it's gone after a few seconds.
- **Planning is slower on the iPad simulator** (about 8 s against 4 s on the iPhone), so the iPad video is the one closest to 30 s.
- **Contact sheet times:** make them fit the video's length; asking for a frame past the end crashes AVAssetImageGenerator.
- **Captions** (text over the video) aren't done here; that needs a video editor such as iMovie.
