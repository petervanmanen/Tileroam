#!/bin/zsh
# Packages the municipality/postcode boundaries into Apple-hosted asset packs, one per country:
# AssetPacks/build/<pack ID>.aar (regions-<CC>, see Tools/pack_ids.zsh), to upload to App Store Connect (Transporter or the
# App Store Connect API). The app downloads them on demand; see Tileroam/Geo/RegionAssets.swift.
# For iPhone, iPad and the Mac app (Mac Catalyst).
#
#   Tools/build_asset_packs.sh            # all countries
#   Tools/build_asset_packs.sh NL BE      # some countries
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
source $ROOT/Tools/pack_ids.zsh
SRC=$ROOT/AssetPacks/Regions
OUT=$ROOT/AssetPacks/build
mkdir -p $OUT/manifests

countries=("$@")
if (( ${#countries} == 0 )); then
  countries=(${(u)$(ls $SRC/*.fmr | xargs -n1 basename | cut -d- -f1)})
fi

for cc in $countries; do
  files=($SRC/$cc-*.fmr(N))
  (( ${#files} )) || { echo "no files for $cc" >&2; exit 1 }
  selectors=$(for f in $files; do printf '{ "file": "%s" },' ${f:t}; done)
  id=$(pack_id $cc)
  manifest=$OUT/manifests/$id.json
  cat > $manifest <<JSON
{
  "assetPackID": "$id",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [ ${selectors%,} ],
  "platforms": [ "iOS", "macOS" ]
}
JSON
  rm -f $OUT/$id.aar
  (cd $SRC && xcrun ba-package package $manifest --output-path $OUT/$id.aar --quiet)
  echo "$id  $(du -h $OUT/$id.aar | cut -f1)"
done
