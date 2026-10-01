#!/bin/zsh
# Packages the municipality/postcode boundaries into Apple-hosted asset packs, one per country:
# AssetPacks/build/regions-<CC>.aar, to upload to App Store Connect (Transporter or the
# App Store Connect API). The app downloads them on demand; see Tileroam/Geo/RegionAssets.swift.
#
#   Tools/build_asset_packs.sh            # all countries
#   Tools/build_asset_packs.sh NL BE      # some countries
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ROOT=${0:A:h:h}
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
  manifest=$OUT/manifests/regions-$cc.json
  cat > $manifest <<JSON
{
  "assetPackID": "regions-$cc",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [ ${selectors%,} ],
  "platforms": [ "iOS" ]
}
JSON
  rm -f $OUT/regions-$cc.aar
  (cd $SRC && xcrun ba-package package $manifest --output-path $OUT/regions-$cc.aar --quiet)
  echo "regions-$cc  $(du -h $OUT/regions-$cc.aar | cut -f1)"
done
