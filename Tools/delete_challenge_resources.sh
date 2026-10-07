#!/bin/zsh
# Deletes what the challenges built into the app until 1.12 used on the servers, now that they're
# challenge files (challenges/README.md):
#   1. Cloudflare R2: the Trappist breweries' list and logos (<bucket>/Trappist/) and the boscafés'
#      list (<bucket>/Boscafes/).
#   2. App Store Connect: the asset packs "ferries", "klompenpaden" and "mtbroutes" (archived with
#      Tools/clean_asset_packs.sh).
#
#   Tools/delete_challenge_resources.sh           # lists what would be deleted, deletes nothing
#   DELETE=1 Tools/delete_challenge_resources.sh  # deletes, after you confirm each part
#   ONLY=r2 / ONLY=packs                          # one of the two parts
#
# Run it only when no app version in use still needs them: 1.12 and older (App Store and TestFlight)
# download these lists, and lose the Trappist, boscafé, ferry, Klompenpaden and MTB challenges
# when they're gone. Neither part can be undone: R2 has no recycle bin, and archived asset packs
# can't be brought back (a new pack would need a new ID). Make the challenge files first
# (Tools/make_challenges.py), from the lists in AssetPacks/ or git.
#
# R2: the settings of Tools/upload_routing_r2.sh: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
# R2_SECRET_ACCESS_KEY, optionally R2_BUCKET (default tileroam-routing); needs rclone.
# App Store Connect: ASC_KEY_ID and ASC_ISSUER_ID, as for Tools/clean_asset_packs.sh.
set -euo pipefail
ROOT=${0:A:h:h}
ONLY=${ONLY:-}
DELETE=${DELETE:-}

confirm() {
  [[ $DELETE == 1 ]] || return 1
  print -n "$1 Type \"delete\" to go on: "
  read -r answer
  [[ $answer == delete ]]
}

if [[ -z $ONLY || $ONLY == r2 ]]; then
  : ${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID} ${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID} ${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}
  BUCKET=${R2_BUCKET:-tileroam-routing}
  command -v rclone >/dev/null || { echo "Install rclone first: brew install rclone" >&2; exit 1 }
  export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
  export RCLONE_CONFIG_R2_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
  export RCLONE_CONFIG_R2_ENDPOINT=https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com
  export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true # a token for one bucket can't list buckets

  for folder in Trappist Boscafes; do
    files=$(rclone lsf --files-only r2:$BUCKET/$folder 2>/dev/null || true)
    if [[ -z $files ]]; then
      echo "R2 $BUCKET/$folder: empty or not there."
      continue
    fi
    echo "R2 $BUCKET/$folder: $(print -r -- $files | wc -l | tr -d ' ') files:"
    print -r -- $files | sed 's/^/  /'
    if confirm "Delete $BUCKET/$folder?"; then
      rclone purge r2:$BUCKET/$folder
      echo "Deleted $BUCKET/$folder."
    fi
  done
fi

if [[ -z $ONLY || $ONLY == packs ]]; then
  # clean_asset_packs.sh lists the packs the app no longer needs (these three are no longer in
  # Tools/asset_packs.swift) and archives those with these IDs after asking "archive".
  if [[ $DELETE == 1 ]]; then
    ARCHIVE="ferries klompenpaden mtbroutes" $ROOT/Tools/clean_asset_packs.sh
  else
    echo "App Store Connect: the packs ferries, klompenpaden and mtbroutes are archived with DELETE=1 (Tools/clean_asset_packs.sh)."
    $ROOT/Tools/clean_asset_packs.sh || true
  fi
fi

[[ $DELETE == 1 ]] || echo "Nothing was deleted. Run with DELETE=1 to delete."
