#!/bin/zsh
# Builds and uploads the region asset packs to App Store Connect with iTMSTransporter.
#
#   Tools/upload_asset_packs.sh            # all countries
#   Tools/upload_asset_packs.sh NL BE      # some countries
#
# Needs an App Store Connect API key (Admin or App Manager):
#   ASC_KEY_ID, ASC_ISSUER_ID  key and issuer IDs
#   ASC_KEY_P8                 contents of the .p8 file (CI); otherwise the key is read from
#                              ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
#   ASC_APP_ID                 the app's numeric Apple ID (defaults to Tileroam's)
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
: ${ASC_KEY_ID:?set ASC_KEY_ID} ${ASC_ISSUER_ID:?set ASC_ISSUER_ID}
ASC_APP_ID=${ASC_APP_ID:-6818280181}
[[ $ASC_APP_ID == <-> ]] || { echo "Set ASC_APP_ID to the app's numeric Apple ID" >&2; exit 1 }

# iTMSTransporter looks for the key in ./private_keys first.
WORK=$(mktemp -d)
trap 'rm -rf $WORK' EXIT
mkdir -p $WORK/private_keys
if [[ -n ${ASC_KEY_P8:-} ]]; then
  printf '%s\n' "$ASC_KEY_P8" > $WORK/private_keys/AuthKey_$ASC_KEY_ID.p8
else
  cp ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 $WORK/private_keys/
fi
chmod 600 $WORK/private_keys/*

$ROOT/Tools/build_asset_packs.sh "$@"
packs=($ROOT/AssetPacks/build/regions-*.aar)
if (( $# )); then packs=(${^@/#/$ROOT/AssetPacks/build/regions-}.aar); fi

failed=()
for pack in $packs; do
  echo "Uploading ${pack:t}…"
  if (cd $WORK && xcrun iTMSTransporter -m uploadAssetPack -assetFile $pack -apple_id $ASC_APP_ID \
        -apiKey $ASC_KEY_ID -apiIssuer $ASC_ISSUER_ID -v informational > $WORK/upload.log 2>&1); then
    echo "  done"
  else
    failed+=${pack:t}
    errors=$(grep -E "ERROR|rror Messages|\"(title|detail|code)\"" $WORK/upload.log | grep -v "DEBUG" | tail -8 || true)
    # No recognizable error lines: show how the log ends instead.
    [[ -n $errors ]] || errors=$(grep -vE "DEBUG|DBG-X" $WORK/upload.log | tail -15 || true)
    print -r -- "$errors" >&2
    if [[ -n ${GITHUB_ACTIONS:-} ]]; then
      # As an annotation, so the error shows on the run's summary page.
      print -r -- "::error title=Upload of ${pack:t} failed::${${errors//\%/%25}//$'\n'/%0A}"
    fi
    (( ${#failed} < 3 )) || break # the rest would most likely fail the same way
  fi
done
(( ${#failed} == 0 )) || { echo "Failed: $failed" >&2; exit 1 }
echo "Uploaded ${#packs} asset pack(s)."
