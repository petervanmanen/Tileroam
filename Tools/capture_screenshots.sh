#!/bin/zsh
# Captures the App Store screenshots in the simulator with the bundled sample rides and writes
# them as JPEG to docs/appstore/screenshots:
#
#   Tools/capture_screenshots.sh iphone   # iPhone 18 Pro Max → iphone-6.9 (1320×2868) and iphone-6.5 (1284×2778)
#   Tools/capture_screenshots.sh ipad     # iPad Pro 13-inch (M5) → ipad-13 (2064×2752)
#
# Build the Debug app for the simulator first (build/Build/Products/Debug-iphonesimulator).
# Uses the Debug-only launch arguments -RegionsDir, -mapMode, -FocusZoom, -PlanDemo,
# -ShowStatistics and -hasSeenIntro.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
KIND=${1:?iphone or ipad}
case $KIND in
  iphone) D="iPhone 18 Pro Max"; FOCUS=9 ;;
  ipad)   D="iPad Pro 13-inch (M5)"; FOCUS=10 ;;
  *) echo "iphone or ipad" >&2; exit 1 ;;
esac
BID=nl.petervanmanen.Tileroam
APP=$ROOT/build/Build/Products/Debug-iphonesimulator/Tileroam.app
SHOTS=$ROOT/docs/appstore/screenshots
RAW=$(mktemp -d)
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
COMMON=(-RegionsDir $ROOT/AssetPacks/Regions -AppleLanguages "(en)" -AppleLocale en_GB -tileZoom 14)

# The simulator is slow to launch apps (system libraries load lazily), so the waits are long.
shot() { # name, wait, args…
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$D" $BID 2>/dev/null || true
  xcrun simctl launch "$D" $BID $COMMON "$@" >/dev/null
  sleep $wait
  xcrun simctl io "$D" screenshot --type=png $RAW/$name.png >/dev/null 2>&1
  echo "$name"
}
shot warmup       25 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS   # imports the rides
shot 01-tiles     16 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS
shot 02-towns     16 -hasSeenIntro YES -mapMode gemeenten -FocusZoom $(( FOCUS - 1 ))
shot 03-postcodes 16 -hasSeenIntro YES -mapMode postcodes -FocusZoom $FOCUS
shot 04-routes    16 -hasSeenIntro YES -mapMode activities -FocusZoom $FOCUS
shot 05-plan      35 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS -PlanDemo YES
shot 06-statistics 40 -hasSeenIntro YES -mapMode squares -FocusZoom $FOCUS -ShowStatistics YES
shot 00-intro     15 -hasSeenIntro NO
xcrun simctl terminate "$D" $BID 2>/dev/null || true
rm $RAW/warmup.png

jpeg() { sips -s format jpeg -s formatOptions 90 $1 --out $2 >/dev/null; }
for f in $RAW/*.png; do
  n=${f:t:r}
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
