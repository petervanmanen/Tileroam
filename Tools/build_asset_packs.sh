#!/bin/zsh
# Packages the municipality/postcode boundaries into Apple-hosted asset packs, one per country:
# AssetPacks/build/<pack ID>.aar (regions-<CC>, see Tools/pack_ids.zsh), to upload to App Store Connect (Transporter or the
# App Store Connect API). The app downloads them on demand; see Tileroam/Geo/RegionAssets.swift.
#
#   Tools/build_asset_packs.sh            # all countries
#   Tools/build_asset_packs.sh NL BE      # some countries
#   Tools/build_asset_packs.sh klompenpaden   # the Klompenpaden list (AssetPacks/Klompenpaden)
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
source $ROOT/Tools/pack_ids.zsh
SRC=$ROOT/AssetPacks/Regions
OUT=$ROOT/AssetPacks/build
mkdir -p $OUT/manifests

countries=("$@")
if (( ${#countries} == 0 )); then
  countries=(${(u)$(ls $SRC/*.fmr | xargs -n1 basename | cut -d- -f1)} klompenpaden)
fi

for cc in $countries; do
  if [[ $cc == klompenpaden ]]; then
    # The Klompenpaden challenge's list (Tools/build_klompenpaden.py), one small pack.
    cat > $OUT/manifests/klompenpaden.json <<JSON
{
  "assetPackID": "klompenpaden",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [ { "file": "klompenpaden.json" } ],
  "platforms": [ "iOS" ]
}
JSON
    rm -f $OUT/klompenpaden.aar
    (cd $ROOT/AssetPacks/Klompenpaden && xcrun ba-package package $OUT/manifests/klompenpaden.json --output-path $OUT/klompenpaden.aar --quiet)
    echo "klompenpaden  $(du -h $OUT/klompenpaden.aar | cut -f1)"
    continue
  fi
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
  "platforms": [ "iOS" ]
}
JSON
  rm -f $OUT/$id.aar
  (cd $SRC && xcrun ba-package package $manifest --output-path $OUT/$id.aar --quiet)
  echo "$id  $(du -h $OUT/$id.aar | cut -f1)"
done
