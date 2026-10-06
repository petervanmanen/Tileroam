#!/bin/zsh
# Uploads the Boscafé Challenge's list to Cloudflare R2, where the app downloads it (see
# BoscafeData in Tileroam/Geo/Boscafe.swift): AssetPacks/Boscafes/boscafes.json to
# <bucket>/Boscafes/.
#
#   Tools/upload_boscafes_r2.sh
#
# To add or change a boscafé: Tools/import_boscafes.py <list in the editor's format>, or edit
# AssetPacks/Boscafes/boscafes.json (id, name, place, emoji, lat,
# lon) and upload. Apps pick up the new list within a day.
#
# Same R2 settings as Tools/upload_trappists_r2.sh: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
# R2_SECRET_ACCESS_KEY, optionally R2_BUCKET (default tileroam-routing) and R2_PUBLIC_URL (to
# check the list downloads afterwards).
set -euo pipefail
ROOT=${0:A:h:h}
: ${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID} ${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID} ${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}
BUCKET=${R2_BUCKET:-tileroam-routing}
command -v rclone >/dev/null || { echo "Install rclone first: brew install rclone" >&2; exit 1 }

SOURCE=$ROOT/AssetPacks/Boscafes
python3 - $SOURCE/boscafes.json <<'PY'
import json, sys
cafes = json.load(open(sys.argv[1]))
keys = {"id", "name", "place", "emoji", "lat", "lon"}
for c in cafes:
    missing = keys - c.keys()
    assert not missing, f"{c.get('id')}: missing {missing}"
assert len({c["id"] for c in cafes}) == len(cafes), "duplicate ids"
print(f"{len(cafes)} boscafés")
PY

export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export RCLONE_CONFIG_R2_ENDPOINT=https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true # a token for one bucket can't list buckets

# The list changes now and then: an hour of caching, so the daily check in the app sees it.
rclone copyto $SOURCE/boscafes.json r2:$BUCKET/Boscafes/boscafes.json --checksum \
  --header-upload "Cache-Control: public, max-age=3600"
echo "Uploaded to $BUCKET/Boscafes/boscafes.json."

if [[ -n ${R2_PUBLIC_URL:-} ]]; then
  url=${R2_PUBLIC_URL%/}/Boscafes/boscafes.json
  code=$(curl -s -o /dev/null -w '%{http_code}' $url)
  [[ $code == 200 ]] && echo "Check: $url downloads." || { echo "Check failed: $url answered $code" >&2; exit 1 }
fi
