#!/bin/zsh
# Compares Tileroam's asset packs in App Store Connect with what the current app needs:
#   - missing: needed by the app but not in App Store Connect (upload with Tools/upload_asset_packs.sh)
#   - unused:  in App Store Connect but no longer needed (archive them on the App Store Connect
#              website; Apple's API can list asset packs but not delete or archive them)
#
#   ASC_KEY_ID=<KeyID> ASC_ISSUER_ID=<IssuerID> Tools/clean_asset_packs.sh
#   OFFLINE=1 Tools/clean_asset_packs.sh     # only list what the app needs (no API key)
#
# Uses the same API key as the upload script: ~/.appstoreconnect/private_keys/AuthKey_<KeyID>.p8,
# or its contents in ASC_KEY_P8. What the app needs comes from Country.all (boundaries) and the
# bundled routing indexes (Tileroam/Resources/routing-*.json). Exits with 1 when packs are missing.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
[[ ${OFFLINE:-} == 1 ]] || : ${ASC_KEY_ID:?set ASC_KEY_ID} ${ASC_ISSUER_ID:?set ASC_ISSUER_ID}
export ASC_APP_ID=${ASC_APP_ID:-6818280181}
export TILEROAM_ROOT=$ROOT
exec swift $ROOT/Tools/asset_packs.swift
