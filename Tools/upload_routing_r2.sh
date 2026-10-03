#!/bin/zsh
# Uploads the routing tiles of a build to Cloudflare R2, where the app downloads them (see
# docs/ROUTING.md). Build them first with Tools/build_routing_tiles.sh.
#
#   Tools/upload_routing_r2.sh west
#
# Uploads AssetPacks/build/routing/r2/<name>/v<version>/ (the version of the bundled index
# Tileroam/Resources/routing-<name>.json) to <bucket>/<name>/v<version>/, with
# Content-Encoding: gzip, 16 files at a time. Files already there are skipped, so an interrupted
# upload continues where it stopped. Each version is a separate folder; old versions stay for the
# app versions that still use them.
#
# Needs rclone (brew install rclone) and an R2 API token with write access to the bucket
# (Cloudflare dashboard → R2 → Manage API tokens):
#   R2_ACCOUNT_ID         the Cloudflare account ID
#   R2_ACCESS_KEY_ID      the token's Access Key ID
#   R2_SECRET_ACCESS_KEY  the token's Secret Access Key
#   R2_BUCKET             the bucket (default: tileroam-routing)
#   R2_PUBLIC_URL         optional: the bucket's public URL (RoutingTilesURL in Tileroam/Servers.plist), to check
#                         that a tile downloads afterwards
# Nothing is written to disk: rclone reads these from the environment.
set -euo pipefail
ROOT=${0:A:h:h}
NAME=${1:?build name, e.g. west}
: ${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID} ${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID} ${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}
BUCKET=${R2_BUCKET:-tileroam-routing}
command -v rclone >/dev/null || { echo "Install rclone first: brew install rclone" >&2; exit 1 }

INDEX=$ROOT/Tileroam/Resources/routing-$NAME.json
[[ $NAME == *-test ]] && INDEX=$ROOT/AssetPacks/build/routing/routing-$NAME.json
[[ -f $INDEX ]] || { echo "No index $INDEX; build first: Tools/build_routing_tiles.sh $NAME …" >&2; exit 1 }
VERSION=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('version', 1))" $INDEX)
COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['tiles']))" $INDEX)
SOURCE=${ROUTING_WORKDIR:-$ROOT/AssetPacks/build/routing}/r2/$NAME/v$VERSION
[[ -d $SOURCE ]] || { echo "No tiles for version $VERSION in $SOURCE; build first" >&2; exit 1 }
local_count=$(find $SOURCE -name '*.gph.gz' | wc -l | tr -d ' ')
(( local_count == COUNT )) || { echo "$SOURCE has $local_count tiles, the index $COUNT: build again" >&2; exit 1 }

export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export RCLONE_CONFIG_R2_ENDPOINT=https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true # a token for one bucket can't list buckets

DEST=r2:$BUCKET/$NAME/v$VERSION
echo "Uploading $COUNT tiles of $NAME version $VERSION ($(du -sh $SOURCE | cut -f1)) to $BUCKET/$NAME/v$VERSION…"
# --size-only: a version's files never change, so a file of the right size is already done.
rclone copy $SOURCE $DEST --size-only --transfers 16 --checkers 32 --stats 15s --stats-one-line \
  --header-upload "Content-Encoding: gzip" \
  --header-upload "Content-Type: application/octet-stream" \
  --header-upload "Cache-Control: public, max-age=31536000, immutable"

uploaded=$(rclone lsf -R --files-only $DEST | grep -c '\.gph\.gz$' || true)
(( uploaded == COUNT )) || { echo "Only $uploaded of $COUNT tiles are on R2; run again to upload the rest" >&2; exit 1 }
echo "All $COUNT tiles of version $VERSION are on R2."

# The climbs of the bundled climbs index (Tools/build_climbs.sh), if any.
CLIMBS=$ROOT/Tileroam/Resources/climbs-$NAME.json
[[ $NAME == *-test ]] && CLIMBS=${INDEX:h}/climbs-$NAME.json
if [[ -f $CLIMBS ]]; then
  CV=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" $CLIMBS)
  AREAS=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['areas']))" $CLIMBS)
  CSOURCE=${SOURCE:h}/climbs/v$CV
  [[ -d $CSOURCE ]] || { echo "No climbs for version $CV in $CSOURCE; run Tools/build_climbs.sh $NAME …" >&2; exit 1 }
  echo "Uploading $AREAS climb areas, version $CV…"
  rclone copy $CSOURCE r2:$BUCKET/$NAME/climbs/v$CV --size-only --transfers 16 --stats 15s --stats-one-line \
    --header-upload "Content-Encoding: gzip" \
    --header-upload "Content-Type: application/json" \
    --header-upload "Cache-Control: public, max-age=31536000, immutable"
  up=$(rclone lsf --files-only r2:$BUCKET/$NAME/climbs/v$CV | grep -c '\.json\.gz$' || true)
  (( up == AREAS )) || { echo "Only $up of $AREAS climb areas are on R2; run again" >&2; exit 1 }
  echo "All $AREAS climb areas of version $CV are on R2."
fi

if [[ -n ${R2_PUBLIC_URL:-} ]]; then
  first=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['tiles'][0][0])" $INDEX)
  url=${R2_PUBLIC_URL%/}/$NAME/v$VERSION/$first.gph.gz
  status=$(curl -s -o /dev/null -w '%{http_code}' --compressed $url)
  [[ $status == 200 ]] && echo "Check: $url downloads." || { echo "Check failed: $url answered $status" >&2; exit 1 }
fi
