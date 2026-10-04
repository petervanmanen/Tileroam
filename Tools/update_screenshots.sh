#!/bin/zsh
# Updates every screenshot in one go:
#   1. builds the Debug app for the simulator;
#   2. captures the App Store screenshots on iPhone and iPad (Tools/capture_screenshots.sh, with
#      the bundled sample rides): docs/appstore/screenshots/{iphone-6.9,iphone-6.5,ipad-13};
#   3. makes the README images from those captures: docs/screenshots/*.jpg (iPhone 644×1400,
#      iPad 1050×1400) and the overview strip.
#
#   Tools/update_screenshots.sh            # everything (about 10 minutes)
#   Tools/update_screenshots.sh iphone     # only the iPhone captures and the README
#
# Needs the routing tile extract for the plan shot (AssetPacks/build/routing/routing-west.tar,
# see docs/ROUTING.md) and an internet connection (climbs and Trappist breweries come from R2).
# Check the images afterwards (the skill app-store-screenshots lists what to look for), then
# commit them.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
KINDS=("$@")
(( ${#KINDS} )) || KINDS=(iphone ipad)
cd $ROOT

echo "Building…"
xcodebuild build -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -derivedDataPath build -quiet

for kind in $KINDS; do
  echo "Capturing $kind…"
  Tools/capture_screenshots.sh $kind
done

# README images, from the raw captures.
OUT=$ROOT/docs/screenshots
readme() { # raw capture, README name, width, height
  sips -z $4 $3 $1 --out $OUT/$2.png >/dev/null
  sips -s format jpeg -s formatOptions 80 $OUT/$2.png --out $OUT/$2.jpg >/dev/null
  rm $OUT/$2.png
}
RAW=$ROOT/AssetPacks/build/screenshots
if [[ -d $RAW/iphone ]]; then
  for pair in 01-tiles:tiles 02-towns:municipalities 03-postcodes:postcodes 04-climbs:climbs \
              05-trappists:trappists 06-plan:planning 07-badges:badges 00-intro:intro settings:settings; do
    readme $RAW/iphone/${pair%%:*}.png ${pair##*:} 644 1400
  done
  swift Tools/compose_images.swift $OUT/overview.jpg 1180 $OUT/tiles.jpg $OUT/municipalities.jpg $OUT/climbs.jpg $OUT/planning.jpg
fi
if [[ -d $RAW/ipad ]]; then
  readme $RAW/ipad/01-tiles.png ipad-tiles 1050 1400
  readme $RAW/ipad/06-plan.png ipad-planning 1050 1400
fi
# Images of views that are gone.
rm -f $OUT/squadratinhos.jpg $OUT/routes.jpg
echo "Done. Check docs/appstore/screenshots and docs/screenshots, then commit them."
