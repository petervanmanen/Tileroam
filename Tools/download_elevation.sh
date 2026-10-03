#!/bin/zsh
# Downloads elevation tiles for route planning and climbs (docs/CLIMBS.md): 1° × 1° tiles in
# Valhalla's "skadi" layout (N52/N52E005.hgt), from the Terrain Tiles open dataset on AWS
# (https://registry.opendata.aws/terrain-tiles/). In Europe they come from SRTM and EU-DEM.
#
#   Tools/download_elevation.sh <south> <north> <west> <east>   # whole degrees, e.g. 41 55 -5 17
#
# Into AssetPacks/build/elevation (or ROUTING_ELEVATION). Tiles already there are skipped; sea
# tiles don't exist and are skipped too. About 25 MB per tile.
set -euo pipefail
ROOT=${0:A:h:h}
E=${ROUTING_ELEVATION:-$ROOT/AssetPacks/build/elevation}
south=${1:?south} north=${2:?north} west=${3:?west} east=${4:?east}
n=0 missing=0
for lat in {$south..$north}; do
  for lon in {$west..$east}; do
    d=$(printf "%s%02d" $( (( lat < 0 )) && echo S || echo N) ${lat#-})
    f=$(printf "%s%03d" $( (( lon < 0 )) && echo W || echo E) ${lon#-})
    f=$d$f
    [[ -s $E/$d/$f.hgt ]] && continue
    mkdir -p $E/$d
    if curl -sf -o $E/$d/$f.hgt.gz https://elevation-tiles-prod.s3.amazonaws.com/skadi/$d/$f.hgt.gz; then
      gunzip -f $E/$d/$f.hgt.gz
      n=$((n + 1))
    else
      rm -f $E/$d/$f.hgt.gz
      missing=$((missing + 1))
    fi
  done
done
echo "Downloaded $n tiles ($missing without data, such as sea) into $E ($(du -sh $E | cut -f1))."
