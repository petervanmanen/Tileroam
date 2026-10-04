#!/bin/zsh
# Uploads the Klompenpaden challenge's list to Cloudflare R2, where the app downloads it (see
# KlompenpadData in Tileroam/Geo/Klompenpad.swift): AssetPacks/Klompenpaden/klompenpaden.json to
# <bucket>/Klompenpaden/.
#
#   python3 Tools/build_klompenpaden.py     # after changing AssetPacks/Klompenpaden/source
#   Tools/upload_klompenpaden_r2.sh
#
# Apps pick up a new list within a day. Same R2 settings as Tools/upload_routing_r2.sh:
# R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, optionally R2_BUCKET (default
# tileroam-routing) and R2_PUBLIC_URL (to check the list downloads afterwards). Nothing is written
# to disk.
set -euo pipefail
ROOT=${0:A:h:h}
: ${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID} ${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID} ${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}
BUCKET=${R2_BUCKET:-tileroam-routing}
command -v rclone >/dev/null || { echo "Install rclone first: brew install rclone" >&2; exit 1 }

SOURCE=$ROOT/AssetPacks/Klompenpaden
# The list must be valid.
python3 - $SOURCE <<'EOF'
import json, os, sys
paths = json.load(open(os.path.join(sys.argv[1], "klompenpaden.json")))
keys = {"id", "name", "start", "lengths", "url", "lat", "lon", "length", "lines"}
for p in paths:
    missing = keys - p.keys()
    assert not missing, f"{p.get('id')}: missing {missing}"
    assert p["lines"], f"{p['id']}: no route"
print(f"{len(paths)} paths")
EOF

export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export RCLONE_CONFIG_R2_ENDPOINT=https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true # a token for one bucket can't list buckets

# The list changes now and then: an hour of caching, so the daily check in the app sees it.
rclone copy $SOURCE/klompenpaden.json r2:$BUCKET/Klompenpaden --checksum \
  --header-upload "Cache-Control: public, max-age=3600"
echo "Uploaded to $BUCKET/Klompenpaden/klompenpaden.json."

if [[ -n ${R2_PUBLIC_URL:-} ]]; then
  url=${R2_PUBLIC_URL%/}/Klompenpaden/klompenpaden.json
  code=$(curl -s -o /dev/null -w '%{http_code}' $url)
  [[ $code == 200 ]] && echo "Check: $url downloads." || { echo "Check failed: $url answered $code" >&2; exit 1 }
fi
