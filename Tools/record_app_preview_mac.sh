#!/bin/zsh
# Records the Mac App Store app preview (1920 × 1080, 15–30 s, H.264 at 30 fps) of the Mac app
# (Mac Catalyst) with the bundled sample rides: plays the scripted tour (-PreviewTour YES; on the
# Mac it shows Tiles, Towns, Postcodes, the boscafés, ferries and MTB routes, then Statistics),
# records the app's window with screencapture -v and turns that into the App Store video with
# Tools/make_app_preview.swift.
#
#   Tools/record_app_preview_mac.sh                              # docs/appstore/previews/mac.mov
#   Tools/record_app_preview_mac.sh docs/appstore/previews/mac.mov
#
# Uses the same app copy as Tools/capture_screenshots_mac.sh (bundle ID
# nl.petervanmanen.Tileroam.screenshots, its own container, no iCloud or location), built here.
# The challenges come from challenges/ (Tools/make_challenges.py). Needs Screen Recording
# permission for the app that runs it (System Settings → Privacy & Security → Screen Recording);
# the window must stay in front while it records (75 s).
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
OUT=${${1:-$ROOT/docs/appstore/previews/mac.mov}:A}
BID=nl.petervanmanen.Tileroam.screenshots
DERIVED=$ROOT/build-mac-screenshots
APP=$DERIVED/Build/Products/Debug-maccatalyst/Tileroam.app
CONTAINER=$HOME/Library/Containers/$BID
WORK=$(mktemp -d)
# Keep the display awake while it runs: a sleeping or locked screen can't be captured.
caffeinate -d -w $$ &

echo "Building the screenshot app…"
xcodebuild build -project $ROOT/Tileroam.xcodeproj -scheme Tileroam -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath $DERIVED -quiet CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=$BID INFOPLIST_KEY_UIUserInterfaceStyle=Light 2>&1 | grep -E "error:" || true
codesign -f -s - --entitlements $ROOT/Tools/screenshots-mac.entitlements $APP/Contents/Extensions/TileroamAssets.appex 2>/dev/null
codesign -f -s - --entitlements $ROOT/Tools/screenshots-mac.entitlements $APP 2>/dev/null

# A window of 1600 × 900 Mac points, 16:9 like the video (3200 × 1800 on Retina, scaled down to
# 1920 × 1080). Mac Catalyst draws the app at 77% of its iPad size, so -WindowSize (iPad points)
# is 2078 × 1169. Light (the build sets UIUserInterfaceStyle) and English, like the other previews.
ARGS=(-AppleLanguages "(en)" -AppleLocale en_GB -ApplePersistenceIgnoreState YES -WindowSize 2078x1169
      -RegionsDir $CONTAINER/Data/Regions -ChallengesFolder $CONTAINER/Data/challenges
      -hasSeenIntro YES -tileZoom 14 -FocusZoom 10)

pid=
quit() { [[ -n $pid ]] && kill $pid 2>/dev/null || true; pid=; sleep 2
  rm -rf "$CONTAINER/Data/Library/Saved Application State" } # no "reopen windows?" alert after a kill
trap quit EXIT
window_bounds() { # x,y,w,h of the app's main window in points, by process ID
  swift - $1 <<'EOF'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let rects = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    .compactMap { $0[kCGWindowBounds as String] as? [String: Double] }
if let r = rects.max(by: { ($0["Width"] ?? 0) * ($0["Height"] ?? 0) < ($1["Width"] ?? 0) * ($1["Height"] ?? 0) }) {
    print("\(Int(r["X"]!)),\(Int(r["Y"]!)),\(Int(r["Width"]!)),\(Int(r["Height"]!))")
}
EOF
}

# The container, the sample rides and the data (as in capture_screenshots_mac.sh), then a warm-up
# launch that imports the rides and fills the caches.
$APP/Contents/MacOS/Tileroam $ARGS -mapMode squares >/dev/null 2>&1 &
pid=$!; sleep 15; quit
mkdir -p "$CONTAINER/Data/Documents/Import/Sample Rides" $CONTAINER/Data/Regions
cp $ROOT/Tileroam/SampleRides/*.fit "$CONTAINER/Data/Documents/Import/Sample Rides/"
cp $ROOT/AssetPacks/Regions/* $CONTAINER/Data/Regions/
rm -rf $CONTAINER/Data/challenges && cp -R $ROOT/challenges $CONTAINER/Data/challenges
# Not the Klompenpaden: their routes may not be redistributed (issue #69), and the tour turns on
# every challenge there is.
rm -f $CONTAINER/Data/challenges/klompenpaden.geojson
$APP/Contents/MacOS/Tileroam $ARGS -mapMode squares >/dev/null 2>&1 &
pid=$!; sleep 30; quit

# The recorded launch: find the window, record it, stop after the tour.
$APP/Contents/MacOS/Tileroam $ARGS -PreviewTour YES > $WORK/console.log 2>&1 &
pid=$!
sleep 3; open -b $BID # to the front: an inactive window has grey controls
bounds=
for i in {1..40}; do bounds=$(window_bounds $pid); [[ -n $bounds ]] && break; sleep 0.5; done
[[ -n $bounds ]] || { echo "No window (is Screen Recording allowed?)" >&2; exit 1 }
sleep 1 # the window settles at its size
bounds=$(window_bounds $pid)
# screencapture -v doesn't stop on a signal: it records a fixed time (-V), enough for the regions
# to load and the tour (about 25 s) to play.
# The pointer out of the way: to the right edge of the screen, beside the window.
swift - $bounds <<'EOF' 2>/dev/null || true
import CoreGraphics
let b = CommandLine.arguments[1].split(separator: ",").compactMap { Double($0) }
let screen = CGDisplayBounds(CGMainDisplayID())
CGWarpMouseCursorPosition(CGPoint(x: screen.maxX - 2, y: b[1] + b[3] / 2))
EOF
REC_START=$(python3 -c 'import time; print(time.time())')
screencapture -v -V 75 -x -R$bounds $WORK/raw.mov > $WORK/rec.log 2>&1 &
REC=$!
for i in {1..180}; do grep -q PREVIEW_TOUR_END $WORK/console.log && break; sleep 0.5; done
wait $REC 2>/dev/null || true
quit
grep -q PREVIEW_TOUR_END $WORK/console.log || { echo "tour didn't finish" >&2; exit 1 }
[[ -s $WORK/raw.mov ]] || { echo "no recording (is Screen Recording allowed?): $(cat $WORK/rec.log)" >&2; exit 1 }

TOUR_START=$(grep -m1 PREVIEW_TOUR_START $WORK/console.log | awk '{print $2}')
TOUR_END=$(grep -m1 PREVIEW_TOUR_END $WORK/console.log | awk '{print $2}')
read START END <<< $(python3 -c "s=$TOUR_START-$REC_START; e=min($TOUR_END-$REC_START+0.5, s+30); print(round(s,2), round(e,2))")
python3 -c "import sys; sys.exit(0 if $END - $START >= 15 else 1)" || { echo "tour shorter than 15 s" >&2; exit 1 }
mkdir -p ${OUT:h}
swift $ROOT/Tools/make_app_preview.swift $WORK/raw.mov $OUT $START $END 1920 1080 2>&1 | grep -v "warning\|^ *[0-9]* |\|^ *|\|^$" || true
