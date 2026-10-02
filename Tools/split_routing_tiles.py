#!/usr/bin/env python3
"""Splits a Valhalla tile directory into asset packs per 1° × 1° area, so the app downloads only
the areas a route needs. Called by Tools/build_routing_tiles.sh; see docs/ROUTING.md.

    split_routing_tiles.py <tile dir> <name> <staging dir> <index json>

Valhalla's tiles come in three levels: 0 (main roads, 4° × 4°), 1 (through roads, 1° × 1°) and
2 (local roads and paths, 0.25° × 0.25°). Each area pack "routing-<name>-n51e005" holds the level-1
tile of that degree and the 16 level-2 tiles inside it; the base pack "routing-<name>-base" holds
the level-0 tiles. File paths stay as Valhalla names them ("2/000/791/223.gph"), so the app can put
links to them in one tile directory. All packs come from one build, so their roads connect.

The index lists every pack with its area, size and files; the app bundles it.
"""
import json
import os
import shutil
import sys

TILE_SIZE = {0: 4.0, 1: 1.0, 2: 0.25}

tiles, name, staging, index_path = sys.argv[1:5]


def tile_corner(level, tile_id):
    size = TILE_SIZE[level]
    row, col = divmod(tile_id, int(360 / size))
    return -90 + row * size, -180 + col * size  # south-west corner


def cell_id(lat, lon):
    return f"{'n' if lat >= 0 else 's'}{abs(lat):02d}{'e' if lon >= 0 else 'w'}{abs(lon):03d}"


packs = {}  # pack id -> {"lat", "lon", "bytes", "files"}
for root, _, files in os.walk(tiles):
    for f in files:
        if not f.endswith(".gph"):
            continue
        path = os.path.relpath(os.path.join(root, f), tiles)
        parts = path.split(os.sep)
        level, tile_id = int(parts[0]), int("".join(parts[1:])[:-4])
        if level == 0:
            pack = f"routing-{name}-base"
            entry = packs.setdefault(pack, {"bytes": 0, "files": []})
        else:
            lat, lon = tile_corner(level, tile_id)
            lat, lon = int(lat // 1), int(lon // 1)
            pack = f"routing-{name}-{cell_id(lat, lon)}"
            entry = packs.setdefault(pack, {"lat": lat, "lon": lon, "bytes": 0, "files": []})
        entry["files"].append(path.replace(os.sep, "/"))
        entry["bytes"] += os.path.getsize(os.path.join(tiles, path))
        # Stage the file under the pack (hard link: no copy).
        target = os.path.join(staging, pack, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.exists(target):
            os.remove(target)
        try:
            os.link(os.path.join(tiles, path), target)
        except OSError:
            shutil.copy2(os.path.join(tiles, path), target)

for entry in packs.values():
    entry["files"].sort()
index = {
    "name": name,
    "base": f"routing-{name}-base",
    "areas": sorted(({"pack": p, **{k: v for k, v in e.items()}} for p, e in packs.items() if "lat" in e),
                    key=lambda a: (a["lat"], a["lon"])),
    "baseFiles": packs.get(f"routing-{name}-base", {"files": []})["files"],
    "baseBytes": packs.get(f"routing-{name}-base", {"bytes": 0})["bytes"],
}
with open(index_path, "w") as f:
    json.dump(index, f, separators=(",", ":"))
print(f"{len(index['areas'])} area packs + base pack; index {os.path.getsize(index_path) / 1000:.0f} KB")
