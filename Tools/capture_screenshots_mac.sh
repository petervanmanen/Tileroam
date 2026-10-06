#!/bin/zsh
# Captures the Mac App Store screenshots of the Mac app (Mac Catalyst) with the bundled sample rides
# and writes them as JPEG (2880 × 1800) to docs/appstore/screenshots/mac. Called by
# Tools/capture_screenshots.sh mac (and Tools/update_screenshots.sh).
#
# It builds a separate copy of the Debug app under its own bundle ID
# (nl.petervanmanen.Tileroam.screenshots), signed ad hoc with Tools/screenshots-mac.entitlements:
# its own sandbox container, no iCloud and no location, so the real app's data is never touched.
# Boundaries and the Klompenpaden are copied from the repository into its container; climbs and
# the Trappist breweries come from R2.
#
# Needs Screen Recording permission for the app that runs it (Terminal, or Claude): System
# Settings → Privacy & Security → Screen Recording. The window is captured with screencapture -l.
# Route planning isn't in the Mac app, so there's no plan shot.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
BID=nl.petervanmanen.Tileroam.screenshots
DERIVED=$ROOT/build-mac-screenshots
APP=$DERIVED/Build/Products/Debug-maccatalyst/Tileroam.app
SHOTS=$ROOT/docs/appstore/screenshots/mac
RAW=$ROOT/AssetPacks/build/screenshots/mac
CONTAINER=$HOME/Library/Containers/$BID
rm -rf $RAW; mkdir -p $RAW $SHOTS

echo "Building the screenshot app…"
xcodebuild build -project $ROOT/Tileroam.xcodeproj -scheme Tileroam -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath $DERIVED -quiet CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=$BID
codesign -f -s - --entitlements $ROOT/Tools/screenshots-mac.entitlements $APP/Contents/Extensions/TileroamAssets.appex
codesign -f -s - --entitlements $ROOT/Tools/screenshots-mac.entitlements $APP

# English, like the iPhone and iPad shots (the Mac's own light or dark appearance is used);
# 1440 × 900 points (2880 × 1800 on Retina), one of the Mac App Store sizes. Boundaries and the
# Klompenpaden are read from copies in the app's container (reading ~/Documents from a sandboxed
# app would ask for permission).
COMMON=(-AppleLanguages "(en)" -AppleLocale en_GB -WindowSize 1440x900
        -RegionsDir $CONTAINER/Data/Regions -KlompenpadenFile $CONTAINER/Data/klompenpaden.json
        -MTBRoutesFile $CONTAINER/Data/mtb-routes.json -BoscafesFile $CONTAINER/Data/boscafes.json -FerriesFile $CONTAINER/Data/ferries.json
        -challenges gemeenten,postcodes,climbs,trappists,boscafes,ferries,klompenpaden,mtb)

pid=
quit() { [[ -n $pid ]] && kill $pid 2>/dev/null || true; pid=; sleep 2 }
window_id() { # the app's main window, by process ID
  swift - $1 <<'EOF'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
let biggest = windows.max { a, b in
    let ra = a[kCGWindowBounds as String] as? [String: Double] ?? [:], rb = b[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (ra["Width"] ?? 0) * (ra["Height"] ?? 0) < (rb["Width"] ?? 0) * (rb["Height"] ?? 0)
}
if let id = biggest?[kCGWindowNumber as String] as? Int { print(id) }
EOF
}
shot() { # name, wait, args…
  local name=$1 wait=$2; shift 2
  quit
  $APP/Contents/MacOS/Tileroam $COMMON "$@" >/dev/null 2>&1 &
  pid=$!
  sleep $wait
  local id=$(window_id $pid)
  [[ -n $id ]] || { echo "No window for $name (is Screen Recording allowed?)" >&2; quit; exit 1 }
  screencapture -x -o -l $id $RAW/$name.png || { echo "screencapture failed: allow Screen Recording for this app" >&2; quit; exit 1 }
  echo "$name"
}

# Launch once so the system creates the container, then copy the sample rides and the data in.
# (The container is kept between runs: removing another app's container asks for permission.)
quit
shot warmup 15 -hasSeenIntro YES -mapMode squares
mkdir -p "$CONTAINER/Data/Documents/Import/Sample Rides" $CONTAINER/Data/Regions
cp $ROOT/Tileroam/SampleRides/*.fit "$CONTAINER/Data/Documents/Import/Sample Rides/"
cp $ROOT/AssetPacks/Regions/* $CONTAINER/Data/Regions/
cp $ROOT/AssetPacks/Klompenpaden/klompenpaden.json $ROOT/AssetPacks/MTB/mtb-routes.json $ROOT/AssetPacks/Boscafes/boscafes.json $ROOT/AssetPacks/Ferries/ferries.json $CONTAINER/Data/
shot warmup2 30 -hasSeenIntro YES -mapMode squares                                # imports the rides
shot warmup3 25 -hasSeenIntro YES -mapMode climbs -MapCenter 50.85,5.84,0.22
shot warmup4 20 -hasSeenIntro YES -mapMode trappists -MapCenter 50.8,4.2,3.9
shot 01-tiles     16 -hasSeenIntro YES -mapMode squares -FocusZoom 10
shot 02-towns     16 -hasSeenIntro YES -mapMode gemeenten -FocusZoom 9
shot 03-postcodes 16 -hasSeenIntro YES -mapMode postcodes -FocusZoom 10
shot 04-climbs    18 -hasSeenIntro YES -mapMode climbs -MapCenter 50.85,5.84,0.22
shot 05-trappists 16 -hasSeenIntro YES -mapMode trappists -MapCenter 50.8,4.2,3.9
shot 06-klompenpaden 16 -hasSeenIntro YES -mapMode klompenpaden -MapCenter 52.05,5.65,0.7
shot 07-badges    30 -hasSeenIntro YES -mapMode squares -FocusZoom 10 -ShowStatistics YES -StatisticsOpen badges
shot 00-intro     15 -hasSeenIntro NO
quit
rm $RAW/warmup*.png

# Exactly 2880 × 1800 (the capture is the window at Retina scale; the title bar can make it a few
# points off), as JPEG.
for f in $RAW/*.png; do
  n=${f:t:r}
  sips -z 1800 2880 $f --out $RAW/$n-sized.png >/dev/null
  sips -s format jpeg -s formatOptions 90 $RAW/$n-sized.png --out $SHOTS/$n.jpg >/dev/null
  rm $RAW/$n-sized.png
done
for f in $SHOTS/*.jpg; do echo "$(sips -g pixelWidth -g pixelHeight $f | awk '/pixel/ {printf "%s ", $2}')${f#$ROOT/}"; done
