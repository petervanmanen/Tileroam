#!/bin/zsh
# Finds the climbs of a group of countries from OpenStreetMap and an elevation model, and prepares
# them for Cloudflare R2. See docs/CLIMBS.md.
#
#   Tools/build_climbs.sh west netherlands belgium luxembourg germany
#
# The first argument is the build name (the same as the routing build); the rest are Geofabrik
# extract names under europe/, downloaded by Tools/build_routing_tiles.sh (or downloaded here when
# missing). Elevation: Tools/download_elevation.sh first.
#
# Output:
#   AssetPacks/build/routing/r2/<name>/climbs/v<version>/<area>.json.gz: upload with
#     Tools/upload_routing_r2.sh <name>
#   Tileroam/Resources/climbs-<name>.json: the index the app bundles (commit it)
# Every build raises the version (CLIMBS_VERSION overrides it).
set -euo pipefail
ROOT=${0:A:h:h}
OUT=${ROUTING_WORKDIR:-$ROOT/AssetPacks/build/routing}
ELEVATION=${ROUTING_ELEVATION:-$ROOT/AssetPacks/build/elevation}
NAME=${1:?build name, e.g. west}; shift
(( $# )) || { echo "usage: build_climbs.sh <name> <geofabrik europe extract>…" >&2; exit 1 }
[[ -d $ELEVATION ]] || { echo "No elevation tiles in $ELEVATION: run Tools/download_elevation.sh first" >&2; exit 1 }
command -v osmium >/dev/null || { echo "Install osmium first: brew install osmium-tool" >&2; exit 1 }

VENV=$ROOT/AssetPacks/build/climbs/venv
if [[ ! -x $VENV/bin/python ]]; then
  mkdir -p ${VENV:h}
  $(command -v python3.12 || command -v python3) -m venv $VENV
  $VENV/bin/pip install -q numpy
fi

pbfs=()
mkdir -p $OUT/osm
for extract in "$@"; do
  pbf=$OUT/osm/$extract-latest.osm.pbf
  if [[ ! -f $pbf ]]; then
    echo "Downloading $extract…"
    curl -fL --progress-bar -o $pbf.part https://download.geofabrik.de/europe/$extract-latest.osm.pbf
    mv $pbf.part $pbf
  fi
  pbfs+=$pbf
done

INDEX=$ROOT/Tileroam/Resources/climbs-$NAME.json
[[ $NAME == *-test ]] && INDEX=$OUT/climbs-$NAME.json
previous=$( [[ -f $INDEX ]] && python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('version', 0))" $INDEX || echo 0 )
export CLIMBS_VERSION=${CLIMBS_VERSION:-$(( previous + 1 ))}

WORK=$OUT/climbs-$NAME.json
$VENV/bin/python $ROOT/Tools/build_climbs.py $ELEVATION $WORK $pbfs
python3 $ROOT/Tools/split_climbs.py $WORK $NAME $OUT/r2 $INDEX
