#!/bin/zsh
# Builds and uploads the region asset packs to App Store Connect with iTMSTransporter: the one
# inside Transporter.app (Mac App Store) or Apple's standalone installer in /usr/local/itms
# (what the GitHub workflow installs). Xcode's own iTMSTransporter is only a stub.
#
#   Tools/upload_asset_packs.sh                   # all countries' boundaries
#   Tools/upload_asset_packs.sh NL BE             # some countries' boundaries
#   Tools/upload_asset_packs.sh routing-west      # all routing packs of a build (its areas and
#                                                 # base), built first with Tools/build_routing_tiles.sh
#                                                 # (docs/ROUTING.md)
#   Tools/upload_asset_packs.sh --resume routing-west
#                                                 # only the packs App Store Connect doesn't have yet:
#                                                 # to continue an interrupted upload of a new build.
#                                                 # Don't use it after rebuilding an existing build:
#                                                 # then every pack needs its new version.
#
# Needs an App Store Connect API key (Admin or App Manager):
#   ASC_KEY_ID, ASC_ISSUER_ID  key and issuer IDs
#   ASC_KEY_P8                 contents of the .p8 file; if unset, the key is read from
#                              ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
#   ASC_APP_ID                 the app's numeric Apple ID (defaults to Tileroam's)
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
source $ROOT/Tools/pack_ids.zsh
: ${ASC_KEY_ID:?set ASC_KEY_ID} ${ASC_ISSUER_ID:?set ASC_ISSUER_ID}
ASC_APP_ID=${ASC_APP_ID:-6818280181}
[[ $ASC_APP_ID == <-> ]] || { echo "Set ASC_APP_ID to the app's numeric Apple ID" >&2; exit 1 }
TRANSPORTER=
for t in /Applications/Transporter.app/Contents/itms/bin/iTMSTransporter /usr/local/itms/bin/iTMSTransporter; do
  [[ -x $t ]] && { TRANSPORTER=$t; break }
done
[[ -n $TRANSPORTER ]] || { echo "Install Transporter from the Mac App Store first" >&2; exit 1 }

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

resume=
if [[ ${1:-} == --resume ]]; then resume=1; shift; fi
countries=(${@:#routing-*})
routing=(${(M)@:#routing-*})
packs=()
if (( ${#countries} || ! $# )); then
  $ROOT/Tools/build_asset_packs.sh $countries
  (( ${#countries} )) || countries=(${(u)$(ls $ROOT/AssetPacks/Regions/*.fmr | xargs -n1 basename | cut -d- -f1)})
  for cc in $countries; do packs+=($ROOT/AssetPacks/build/$(pack_id $cc).aar); done
fi
for r in $routing; do
  built=($ROOT/AssetPacks/build/$r-*.aar(N))
  (( ${#built} )) || { echo "Build $r first: Tools/build_routing_tiles.sh ${r#routing-} …" >&2; exit 1 }
  packs+=($built)
done

if [[ -n $resume ]]; then
  uploaded=(${(f)"$(LIST=1 TILEROAM_ROOT=$ROOT ASC_APP_ID=$ASC_APP_ID swift $ROOT/Tools/asset_packs.swift)"})
  before=${#packs}
  packs=(${packs:#*/(${(j:|:)~uploaded}).aar})
  echo "Resuming: $(( before - ${#packs} )) of $before already in App Store Connect."
fi
# The base pack first: every plan needs it.
packs=(${(M)packs:#*-base.aar} ${packs:#*-base.aar})

failed=()
n=0
for pack in $packs; do
  n=$(( n + 1 ))
  echo "[$n/${#packs}] Uploading ${pack:t} ($(du -h $pack | cut -f1 | tr -d ' '))…"
  if (cd $WORK && $TRANSPORTER -m uploadAssetPack -assetFile $pack -apple_id $ASC_APP_ID \
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
    (( ${#failed} < 3 )) || { echo "Stopping after 3 failures. Fix the cause, then continue with --resume." >&2; break }
  fi
done
(( ${#failed} == 0 )) || { echo "Failed: $failed. Run again with --resume to upload what's missing." >&2; exit 1 }
echo "Uploaded ${#packs} asset pack(s)."
