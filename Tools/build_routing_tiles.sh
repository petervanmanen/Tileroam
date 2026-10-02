#!/bin/zsh
# Builds the on-device routing data: Valhalla tiles from OpenStreetMap for a group of countries,
# packed as one tile extract (.tar) in an Apple-hosted asset pack. See docs/ROUTING.md.
#
#   Tools/build_routing_tiles.sh benelux netherlands belgium luxembourg
#
# The first argument names the pack (asset pack "routing-<name>", file "routing-<name>.tar"); the
# rest are Geofabrik extract names under europe/ (https://download.geofabrik.de/europe.html).
# Countries routed across each other's borders must be in the same build.
#
# Output in AssetPacks/build/routing (not in Git):
#   routing-<name>.tar        the tile extract the app loads (also for the simulator: -RoutingTar)
#   ../routing-<name>.aar     the asset pack to upload (Tools/upload_asset_packs.sh routing-<name>)
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
# Must match the Valhalla version inside valhalla-mobile (Tileroam.xcodeproj pins valhalla-mobile
# 0.6.3, which contains Valhalla 3.6.3): tiles from another version may not load.
VALHALLA_VERSION=3.6.3
ROOT=${0:A:h:h}
OUT=$ROOT/AssetPacks/build/routing
NAME=${1:?pack name, e.g. benelux}; shift
(( $# )) || { echo "usage: build_routing_tiles.sh <name> <geofabrik europe extract>…" >&2; exit 1 }
mkdir -p $OUT/osm

# Valhalla's tools (pyvalhalla, Python 3.12+) in a local environment.
VENV=$OUT/venv
if [[ ! -x $VENV/bin/valhalla_build_tiles ]]; then
  PYTHON=$(command -v python3.12 || command -v python3.13 || true)
  [[ -n $PYTHON ]] || { echo "Install Python 3.12 or newer first: brew install python@3.12" >&2; exit 1 }
  $PYTHON -m venv $VENV
  $VENV/bin/pip install -q pyvalhalla==$VALHALLA_VERSION
fi
export PATH=$VENV/bin:$PATH

# 1. OpenStreetMap extracts from Geofabrik (re-downloaded when older than a week).
pbfs=()
for extract in "$@"; do
  pbf=$OUT/osm/$extract-latest.osm.pbf
  if [[ ! -f $pbf || -n $(find $pbf -mtime +7) ]]; then
    echo "Downloading $extract…"
    curl -fL --progress-bar -o $pbf.part https://download.geofabrik.de/europe/$extract-latest.osm.pbf
    mv $pbf.part $pbf
  fi
  pbfs+=$pbf
done

# 2. One merged extract: country extracts overlap at the borders, and Valhalla would otherwise
#    build those ways twice (brew install osmium-tool).
if (( ${#pbfs} > 1 )); then
  command -v osmium >/dev/null || { echo "Install osmium first: brew install osmium-tool" >&2; exit 1 }
  MERGED=$OUT/osm/$NAME-merged.osm.pbf
  echo "Merging $*…"
  osmium merge $pbfs -o $MERGED --overwrite --no-progress
  pbfs=($MERGED)
fi

# 3. Tiles, in one build so the countries connect.
TILES=$OUT/tiles-$NAME
TAR=$OUT/routing-$NAME.tar
rm -rf $TILES; mkdir -p $TILES
# Cycling only: no car-only roads, driveways or car shortcuts (about 10% smaller). Footpaths stay,
# so routes can cross pedestrian zones with the bike pushed; ROUTING_PEDESTRIAN=False drops them
# too (about 25% smaller in total).
python -m valhalla.valhalla_build_config --mjolnir-tile-dir $TILES --mjolnir-tile-extract $TAR \
  --mjolnir-timezone "" --mjolnir-admin "" --mjolnir-traffic-extract "" \
  --mjolnir-include-driving False --mjolnir-include-driveways False --mjolnir-shortcuts False \
  --mjolnir-include-pedestrian ${ROUTING_PEDESTRIAN:-True} \
  --mjolnir-concurrency $(sysctl -n hw.ncpu) > $OUT/config-$NAME.json 2>/dev/null
echo "Building tiles for $*…"
valhalla_build_tiles -c $OUT/config-$NAME.json $pbfs > $OUT/build-$NAME.log 2>&1 || {
  tail -20 $OUT/build-$NAME.log >&2; exit 1 }

# 4. One tile extract with an index, which the app opens directly.
# (valhalla_build_extract refuses to overwrite and still exits 0, so remove the old one first.)
rm -f $TAR
python $ROOT/Tools/valhalla_build_extract.py -c $OUT/config-$NAME.json -v >> $OUT/build-$NAME.log 2>&1
[[ -s $TAR ]] || { echo "No tile extract written; see $OUT/build-$NAME.log" >&2; exit 1 }
rm -rf $TILES
echo "Tile extract: $TAR ($(du -h $TAR | cut -f1))"

# 5. Asset pack (on demand: downloaded when the user first plans a route).
MANIFEST=$OUT/routing-$NAME.manifest.json
cat > $MANIFEST <<JSON
{
  "assetPackID": "routing-$NAME",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [ { "file": "routing-$NAME.tar" } ],
  "platforms": [ "iOS" ]
}
JSON
rm -f $ROOT/AssetPacks/build/routing-$NAME.aar
(cd $OUT && xcrun ba-package package $MANIFEST --output-path $ROOT/AssetPacks/build/routing-$NAME.aar --quiet)
echo "Asset pack: AssetPacks/build/routing-$NAME.aar ($(du -h $ROOT/AssetPacks/build/routing-$NAME.aar | cut -f1))"
