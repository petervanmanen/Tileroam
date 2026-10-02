#!/bin/zsh
# Records the App Store app preview in the simulator: installs the Debug app with the sample
# rides, plays the scripted tour (-PreviewTour YES, see ContentView), records the screen and
# turns the recording into an App Store video with Tools/make_app_preview.swift.
#
#   Tools/record_app_preview.sh "iPhone 18 Pro Max" docs/appstore/previews/iphone-6.5.mov 886 1920 9
#   Tools/record_app_preview.sh "iPad Pro 13-inch (M5)" docs/appstore/previews/ipad-13.mov 1200 1600 10
#
# Build the Debug app for the simulator first (it uses build/Build/Products/Debug-iphonesimulator).
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
D=$1; OUT=${2:A}; W=$3; H=$4; FOCUS=${5:-9}
BID=nl.petervanmanen.Tileroam
APP=$ROOT/build/Build/Products/Debug-iphonesimulator/Tileroam.app
WORK=$(mktemp -d)

xcrun simctl boot "$D" 2>/dev/null || true
xcrun simctl bootstatus "$D" -b >/dev/null
xcrun simctl status_bar "$D" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl location "$D" set 52.0907,5.1214
xcrun simctl terminate "$D" $BID 2>/dev/null || true
xcrun simctl uninstall "$D" $BID
xcrun simctl install "$D" $APP
xcrun simctl privacy "$D" grant location-always $BID
C=$(xcrun simctl get_app_container "$D" $BID data)
mkdir -p "$C/Documents/Import/Sample Rides"
cp $ROOT/Tileroam/SampleRides/*.fit "$C/Documents/Import/Sample Rides/"
ARGS=(-RegionsDir $ROOT/AssetPacks/Regions -RoutingTar $ROOT/AssetPacks/build/routing/routing-west.tar -hasSeenIntro YES -AppleLanguages "(en)" -AppleLocale en_GB
      -tileZoom 14 -FocusZoom $FOCUS)

# Warm-up launch: import the rides and fill the caches, so the recorded launch is quick.
xcrun simctl launch "$D" $BID $ARGS >/dev/null
sleep 25
xcrun simctl terminate "$D" $BID

xcrun simctl io "$D" recordVideo --codec=h264 --force $WORK/raw.mov 2>/dev/null &
REC=$!
sleep 2
xcrun simctl launch --console-pty "$D" $BID $ARGS -PreviewTour YES > $WORK/console.log 2>&1 &
for i in {1..120}; do grep -q PREVIEW_TOUR_END $WORK/console.log && break; sleep 1; done
sleep 1
kill -INT $REC; wait $REC 2>/dev/null || true
xcrun simctl terminate "$D" $BID 2>/dev/null || true

grep -q PREVIEW_TOUR_END $WORK/console.log || { echo "tour didn't finish" >&2; exit 1 }
# The markers are wall-clock times; the recording's start is its file creation time.
REC_START=$(stat -f %B $WORK/raw.mov)
TOUR_START=$(grep -m1 PREVIEW_TOUR_START $WORK/console.log | awk '{print $2}' | tr -d '\r')
TOUR_END=$(grep -m1 PREVIEW_TOUR_END $WORK/console.log | awk '{print $2}' | tr -d '\r')
START=$(( TOUR_START - REC_START )); END=$(( TOUR_END - REC_START + 0.5 ))
(( END - START <= 30 )) || END=$(( START + 30 ))
(( END - START >= 15 )) || { echo "tour shorter than 15 s" >&2; exit 1 }
mkdir -p ${OUT:h}
swift $ROOT/Tools/make_app_preview.swift $WORK/raw.mov $OUT $START $END $W $H
