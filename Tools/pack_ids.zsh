# Sourced by the asset pack scripts (after they set ROOT): pack_id <CC> prints a country's boundary pack ID, from
# RegionAssets.packID in Tileroam/Geo/RegionAssets.swift ("regions-<CC>", or the new ID of a
# country whose first pack was archived, from RegionAssets.renamedPacks).
pack_id() {
  [[ $1 == klompenpaden ]] && { print -r -- klompenpaden; return }
  local id
  id=$(grep -m1 'static let renamedPacks' $ROOT/Tileroam/Geo/RegionAssets.swift 2>/dev/null \
    | grep -o "\"$1\": \"[^\"]*\"" | sed -E 's/.*: "(.*)"/\1/' || true)
  print -r -- ${id:-regions-$1}
}
