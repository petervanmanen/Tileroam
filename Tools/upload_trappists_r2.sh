#!/bin/zsh
# Uploads the Trappist Challenge's data to Cloudflare R2, where the app downloads it (see
# TrappistData in Tileroam/Geo/Trappist.swift): AssetPacks/Trappist (trappists.json and a logo per
# brewery, <id>.png) to <bucket>/Trappist/.
#
#   Tools/upload_trappists_r2.sh
#
# To add or change a brewery: edit AssetPacks/Trappist/trappists.json (id, name, abbey, place,
# country, lat, lon), put its logo next to it as <id>.png (black on white, square), and upload.
# Apps pick up the new list within a day. Files no longer in the folder are removed from R2.
#
# Same R2 settings as Tools/upload_routing_r2.sh: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
# R2_SECRET_ACCESS_KEY, optionally R2_BUCKET (default tileroam-routing) and R2_PUBLIC_URL (to
# check the list downloads afterwards). Nothing is written to disk.
set -euo pipefail
ROOT=${0:A:h:h}
: ${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID} ${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID} ${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}
BUCKET=${R2_BUCKET:-tileroam-routing}
command -v rclone >/dev/null || { echo "Install rclone first: brew install rclone" >&2; exit 1 }

SOURCE=$ROOT/AssetPacks/Trappist
# Every brewery needs its logo, and the list must be valid.
python3 - $SOURCE <<'EOF'
import json, os, sys
folder = sys.argv[1]
breweries = json.load(open(os.path.join(folder, "trappists.json")))
keys = {"id", "name", "abbey", "place", "country", "lat", "lon"}
for b in breweries:
    missing = keys - b.keys()
    assert not missing, f"{b.get('id')}: missing {missing}"
    assert os.path.exists(os.path.join(folder, b["id"] + ".png")), f"no logo {b['id']}.png"
print(f"{len(breweries)} breweries")
EOF

export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export RCLONE_CONFIG_R2_ENDPOINT=https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true # a token for one bucket can't list buckets

# The list changes now and then: an hour of caching, so the daily check in the app sees it.
rclone sync $SOURCE r2:$BUCKET/Trappist --include 'trappists.json' --include '*.png' --checksum \
  --header-upload "Cache-Control: public, max-age=3600"
echo "Uploaded to $BUCKET/Trappist: $(rclone lsf --files-only r2:$BUCKET/Trappist | wc -l | tr -d ' ') files."

if [[ -n ${R2_PUBLIC_URL:-} ]]; then
  url=${R2_PUBLIC_URL%/}/Trappist/trappists.json
  code=$(curl -s -o /dev/null -w '%{http_code}' $url)
  [[ $code == 200 ]] && echo "Check: $url downloads." || { echo "Check failed: $url answered $code" >&2; exit 1 }
fi
