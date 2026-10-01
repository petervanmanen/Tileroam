#!/bin/zsh
# CI runners have no signing certificate. The archive is built with CODE_SIGNING_ALLOWED=NO;
# this signs its bundles ad hoc with their entitlements, so that `xcodebuild -exportArchive`
# (cloud signing with an App Store Connect API key) keeps iCloud and the App Group.
#
#   Tools/ci_sign_archive.sh build/Tileroam.xcarchive
set -euo pipefail
ROOT=${0:A:h:h}
ARCHIVE=$1
TEAM=$(grep -m1 'DEVELOPMENT_TEAM = ' $ROOT/Tileroam.xcodeproj/project.pbxproj | sed -E 's/.*= ([A-Z0-9]+);/\1/')
APP=$ARCHIVE/Products/Applications/Tileroam.app
WORK=$(mktemp -d)

expand() { # entitlements file, bundle id
  sed -e "s/\$(TeamIdentifierPrefix)/$TEAM./g" -e "s/\$(CFBundleIdentifier)/$2/g" $1 > $WORK/${1:t}
  if grep -q '\$(' $WORK/${1:t}; then echo "unexpanded variable in $1" >&2; exit 1; fi
  echo $WORK/${1:t}
}

# Inside out: extensions first, then the app.
codesign -f -s - --entitlements $(expand $ROOT/TileroamWidget/TileroamWidget.entitlements nl.petervanmanen.Tileroam.Widget) \
  $APP/PlugIns/TileroamWidget.appex
codesign -f -s - --entitlements $(expand $ROOT/TileroamAssets/TileroamAssets.entitlements nl.petervanmanen.Tileroam.Assets) \
  $APP/Extensions/TileroamAssets.appex
codesign -f -s - --entitlements $(expand $ROOT/Tileroam/Tileroam.entitlements nl.petervanmanen.Tileroam) $APP
codesign --verify --deep --strict $APP
echo "Signed $APP ad hoc (team $TEAM)"
