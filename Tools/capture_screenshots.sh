#!/bin/zsh
# Captures the App Store screenshots in the simulator with the bundled sample rides and writes
# them as JPEG to docs/appstore/screenshots:
#
#   Tools/capture_screenshots.sh iphone   # iPhone 18 Pro Max → iphone-6.9 (1320×2868) and iphone-6.5 (1284×2778)
#   Tools/capture_screenshots.sh ipad     # iPad Pro 13-inch (M5) → ipad-13 (2064×2752)
#   Tools/capture_screenshots.sh mac      # the Mac app → mac (2880×1800); see capture_screenshots_mac.sh
#
# Build the Debug app for the simulator first (build/Build/Products/Debug-iphonesimulator).
# Uses the Debug-only launch arguments -RegionsDir, -challenges, -mapMode, -FocusZoom, -MapCenter,
# -PlanDemo, -ShowStatistics, -StatisticsOpen, -ShowSettings and -hasSeenIntro. Climbs and the
# Trappist breweries come from R2 (tiles.petervanmanen.nl), so it needs an internet connection.
# The README images are made from these captures by Tools/update_screenshots.sh, which runs it all.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
KIND=${1:?iphone, ipad or mac}
case $KIND in
  mac)    exec $ROOT/Tools/capture_screenshots_mac.sh ;;
  iphone) D="iPhone 18 Pro Max"; FOCUS=9 ;;
  ipad)   D="iPad Pro 13-inch (M5)"; FOCUS=10 ;;
  *) echo "iphone, ipad or mac" >&2; exit 1 ;;
esac
BID=nl.petervanmanen.Tileroam
APP=$ROOT/build/Build/Products/Debug-iphonesimulator/Tileroam.app
SHOTS=$ROOT/docs/appstore/screenshots
# Raw PNG captures stay here for Tools/update_screenshots.sh (the README images).
RAW=$ROOT/AssetPacks/build/screenshots/$KIND
rm -rf $RAW; mkdir -p $RAW
[[ -d $APP ]] || { echo "Build the Debug app for the simulator first" >&2; exit 1 }

# English system language, so the iPad status bar date isn't localized.
xcrun simctl boot "$D" 2>/dev/null || true
xcrun simctl bootstatus "$D" -b >/dev/null
if [[ $(xcrun simctl spawn "$D" defaults read "Apple Global Domain" AppleLocale 2>/dev/null) != en_GB ]]; then
  xcrun simctl spawn "$D" defaults write "Apple Global Domain" AppleLanguages -array en-GB en
  xcrun simctl spawn "$D" defaults write "Apple Global Domain" AppleLocale en_GB
  xcrun simctl shutdown "$D"; xcrun simctl boot "$D"; xcrun simctl bootstatus "$D" -b >/dev/null
fi
xcrun simctl ui "$D" appearance light
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
# All challenges on, so the bar at the top shows every tab.
COMMON=(-RegionsDir $ROOT/AssetPacks/Regions -KlompenpadenFile $ROOT/AssetPacks/Klompenpaden/klompenpaden.json -MTBRoutesFile $ROOT/AssetPacks/MTB/mtb-routes.json -BoscafesFile $ROOT/AssetPacks/Boscafes/boscafes.json -FerriesFile $ROOT/AssetPacks/Ferries/ferries.json -RoutingTar $ROOT/AssetPacks/build/routing/routing-west.tar -AppleLanguages "(en)" -AppleLocale en_GB
        -challenges gemeenten,postcodes,climbs,trappists,boscafes,ferries,klompenpaden,mtb)

# The simulator is slow to launch apps (system libraries load lazily), so the waits are long.
shot() { # name, wait, args…
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$D" $BID 2>/dev/null || true
  xcrun simctl launch "$D" $BID $COMMON "$@" >/dev/null
  sleep $wait
  xcrun simctl io "$D" screenshot --type=png $RAW/$name.png >/dev/null 2>&1
  echo "$name"
}
# Warm-ups: import the rides, then download the climbs around Valkenburg (South Limburg) and the
# Trappist breweries' logos.
shot warmup       25 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS
shot warmup2      25 -hasSeenIntro YES -mapMode climbs -MapCenter 50.85,5.84,0.22
shot warmup3      20 -hasSeenIntro YES -mapMode trappists -MapCenter 50.8,4.2,3.9
shot 01-tiles     16 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS
shot 02-towns     16 -hasSeenIntro YES -mapMode gemeenten -FocusZoom $(( FOCUS - 1 ))
shot 03-postcodes 16 -hasSeenIntro YES -mapMode postcodes -FocusZoom $FOCUS
shot 04-climbs    18 -hasSeenIntro YES -mapMode climbs -MapCenter 50.85,5.84,0.22
shot 05-trappists 16 -hasSeenIntro YES -mapMode trappists -MapCenter 50.8,4.2,3.9
shot 06-plan      35 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS -PlanDemo YES
shot 07-badges    40 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS -ShowStatistics YES -StatisticsOpen badges
shot 00-intro     15 -hasSeenIntro NO
# Not for the App Store (only the README uses it).
shot settings     30 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS -ShowSettings YES
xcrun simctl terminate "$D" $BID 2>/dev/null || true
rm $RAW/warmup*.png
# Shots of earlier sets that are gone (Routes, removed in 1.5.3).
old=($SHOTS/*/(04-routes|05-plan|06-statistics).jpg(N))
(( ${#old} )) && rm -f $old

jpeg() { sips -s format jpeg -s formatOptions 90 $1 --out $2 >/dev/null; }
for f in $RAW/*.png; do
  n=${f:t:r}
  [[ $n == settings || $n == *-65 ]] && continue # README only / scaled copies
  if [[ $KIND == iphone ]]; then
    mkdir -p $SHOTS/iphone-6.9 $SHOTS/iphone-6.5
    jpeg $f $SHOTS/iphone-6.9/$n.jpg
    # 6.5″: scale to 1284 wide, then crop the height to 2778 (a few px top and bottom).
    sips --resampleWidth 1284 $f --out $RAW/$n-65.png >/dev/null
    sips -c 2778 1284 $RAW/$n-65.png >/dev/null
    jpeg $RAW/$n-65.png $SHOTS/iphone-6.5/$n.jpg
  else
    mkdir -p $SHOTS/ipad-13
    jpeg $f $SHOTS/ipad-13/$n.jpg
  fi
done
echo "Raw captures: $RAW"
for f in $SHOTS/${KIND}*/*.jpg; do echo "$(sips -g pixelWidth -g pixelHeight $f | awk '/pixel/ {printf "%s ", $2}')${f#$ROOT/}"; done
