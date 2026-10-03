#!/bin/zsh
# Builds the on-device routing data: Valhalla tiles from OpenStreetMap for a group of countries,
# gzipped per tile for Cloudflare R2, where the app downloads only the tiles a route needs. See
# docs/ROUTING.md.
#
#   Tools/build_routing_tiles.sh west netherlands belgium luxembourg germany
#
# The first argument names the build (keep "west"; see docs/ROUTING.md, "Versions"); the rest are
# Geofabrik extract names under europe/ (https://download.geofabrik.de/europe.html). Countries
# routed across each other's borders must be in the same build.
#
# Output:
#   AssetPacks/build/routing/r2/<name>/v<version>/…: the gzipped tiles to upload
#     (Tools/upload_routing_r2.sh <name>)
#   Tileroam/Resources/routing-<name>.json: the index of tiles the app bundles (commit it)
#   AssetPacks/build/routing/routing-<name>.tar: all tiles in one file, for the simulator
#     (-RoutingTar) and the engine tests
#
# ROUTING_REPACK=1 only redoes step 5 (gzip and index) from the last build's tile extract.
# ROUTING_CONCURRENCY limits the build threads (default: all cores), for Macs with little memory.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
# Must match the Valhalla version inside valhalla-mobile (Tileroam.xcodeproj pins valhalla-mobile
# 0.6.3, which contains Valhalla 3.6.3): tiles from another version may not load.
VALHALLA_VERSION=3.6.3
ROOT=${0:A:h:h}
# ROUTING_WORKDIR puts the build (tens of GB) elsewhere, for example on an external disk formatted
# for Mac; the index still goes into the app's resources.
OUT=${ROUTING_WORKDIR:-$ROOT/AssetPacks/build/routing}
# Elevation tiles (Valhalla's "skadi" layout, N52/N52E005.hgt; Tools/download_elevation.sh): with
# them, every road gets its gradient, so bicycle routes take hills into account.
ELEVATION=${ROUTING_ELEVATION:-$ROOT/AssetPacks/build/elevation}
NAME=${1:?pack name, e.g. benelux}; shift
(( $# )) || [[ -n ${ROUTING_REPACK:-} ]] || { echo "usage: build_routing_tiles.sh <name> <geofabrik europe extract>…" >&2; exit 1 }
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

TILES=$OUT/tiles-$NAME
TAR=$OUT/routing-$NAME.tar
R2=$OUT/r2

if [[ -n ${ROUTING_REPACK:-} ]]; then
  # Only step 5 again, from the last build's tile extract (for example after changing which
  # countries are covered): no download and no tile build.
  [[ -s $TAR ]] || { echo "No earlier build: $TAR is missing" >&2; exit 1 }
  rm -rf $TILES; mkdir -p $TILES
  tar -xf $TAR -C $TILES
else

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
rm -rf $TILES; mkdir -p $TILES
# Cycling only: no car-only roads, driveways or car shortcuts (about 10% smaller). Footpaths stay,
# so routes can cross pedestrian zones with the bike pushed; ROUTING_PEDESTRIAN=False drops them
# too (about 25% smaller in total).
python -m valhalla.valhalla_build_config --mjolnir-tile-dir $TILES --mjolnir-tile-extract $TAR \
  --mjolnir-timezone "" --mjolnir-admin "" --mjolnir-traffic-extract "" \
  --additional-data-elevation "$([[ -d $ELEVATION ]] && echo $ELEVATION)" \
  --mjolnir-include-driving False --mjolnir-include-driveways False --mjolnir-shortcuts False \
  --mjolnir-include-pedestrian ${ROUTING_PEDESTRIAN:-True} \
  --mjolnir-concurrency ${ROUTING_CONCURRENCY:-$(sysctl -n hw.ncpu)} > $OUT/config-$NAME.json 2>/dev/null
echo "Building tiles for $*…"
valhalla_build_tiles -c $OUT/config-$NAME.json $pbfs > $OUT/build-$NAME.log 2>&1 || {
  tail -20 $OUT/build-$NAME.log >&2; exit 1 }
# The merged extract is only an input; it's made again on the next build (saves several GB).
[[ -n ${MERGED:-} ]] && rm -f $MERGED

# 4. All tiles in one file (simulator and tests).
# (valhalla_build_extract refuses to overwrite and still exits 0, so remove the old one first.)
rm -f $TAR
python $ROOT/Tools/valhalla_build_extract.py -c $OUT/config-$NAME.json -v >> $OUT/build-$NAME.log 2>&1
[[ -s $TAR ]] || { echo "No tile extract written; see $OUT/build-$NAME.log" >&2; exit 1 }
echo "Tile extract: $TAR ($(du -h $TAR | cut -f1))"
fi

# 5. Gzipped tiles for R2, and the index the app bundles. Only the tiles within reach of the
#    covered countries (RoutingData.countries, or ROUTING_COUNTRIES).
# The index goes into the app's resources, except for test builds ("<name>-test").
INDEX=$ROOT/Tileroam/Resources/routing-$NAME.json
[[ $NAME == *-test ]] && INDEX=$OUT/routing-$NAME.json
# Every new build of the same name is the next version of its data (its own folder on R2); a
# repack keeps the version. ROUTING_VERSION overrides it.
previous=$( [[ -f $INDEX ]] && python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('version', 1))" $INDEX || echo 0 )
if [[ -n ${ROUTING_VERSION:-} ]]; then :
elif [[ -n ${ROUTING_REPACK:-} ]]; then ROUTING_VERSION=$(( previous > 0 ? previous : 1 ))
else ROUTING_VERSION=$(( previous + 1 )); fi
export ROUTING_VERSION
python3 $ROOT/Tools/pack_routing_tiles.py $TILES $NAME $R2 $INDEX
rm -rf $TILES
