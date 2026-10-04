#!/bin/zsh
# Compares Tileroam's asset packs in App Store Connect with what the current app needs:
#   - missing: needed by the app but not in App Store Connect (upload with Tools/upload_asset_packs.sh)
#   - unused:  in App Store Connect but no longer needed
#
# With ARCHIVE it archives unused packs whose IDs start with the given prefixes, after you confirm
# by typing "archive" (in the terminal):
#   ARCHIVE="regions-" Tools/clean_asset_packs.sh
#   ARCHIVE="routing-" Tools/clean_asset_packs.sh   # the routing packs from before R2
# Archiving can't be undone, not even with the API: a country that comes back needs a new pack
# ID (RegionAssets.renamedPacks in Tileroam/Geo/RegionAssets.swift).
# "Unused" is decided by the checkout you run it in (Country.all), so run it
# on the branch that matches the app versions in use.
#
#   ASC_KEY_ID=<KeyID> ASC_ISSUER_ID=<IssuerID> Tools/clean_asset_packs.sh
#   OFFLINE=1 Tools/clean_asset_packs.sh     # only list what the app needs (no API key)
#
# Uses the same API key as the upload script: ~/.appstoreconnect/private_keys/AuthKey_<KeyID>.p8,
# or its contents in ASC_KEY_P8. What the app needs comes from Country.all (boundaries); routing
# data is on Cloudflare R2, not in asset packs. Exits with 1 when packs are missing.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
[[ ${OFFLINE:-} == 1 ]] || : ${ASC_KEY_ID:?set ASC_KEY_ID} ${ASC_ISSUER_ID:?set ASC_ISSUER_ID}
export ASC_APP_ID=${ASC_APP_ID:-6818280181}
export TILEROAM_ROOT=$ROOT
exec swift $ROOT/Tools/asset_packs.swift
