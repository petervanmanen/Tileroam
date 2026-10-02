#!/usr/bin/env python3
"""Prepares a Valhalla tile directory for Cloudflare R2, where the app downloads the tiles a route
needs. Called by Tools/build_routing_tiles.sh; see docs/ROUTING.md.

    pack_routing_tiles.py <tile dir> <name> <out dir> <index json>

Each tile is gzipped to <out dir>/<name>/v<version>/<tile path>.gph.gz, for example
west/v2/2/000/791/223.gph.gz, and uploaded with Content-Encoding: gzip by
Tools/upload_routing_r2.sh. Valhalla's three levels are kept as they are: 0 (main roads,
4° × 4°), 1 (through roads, 1° × 1°) and 2 (local roads and paths, 0.25° × 0.25°). The app takes the
tiles of every level that overlap a plan, so a plan downloads only its own surroundings.

The index lists every tile with its compressed and uncompressed size; the app bundles it.

Versions: every build is one version of the data (ROUTING_VERSION, set by build_routing_tiles.sh).
Tiles of different builds don't connect, so each version has its own folder; old folders stay on
R2 as long as app versions that use them are around.

Only tiles within reach of the covered countries are packed (see routing_area_filter.py): the
countries in ROUTING_COUNTRIES (for example "NL BE LU DE"), by default those in
RoutingData.countries in Tileroam/Planning/RoutingData.swift.
"""
import gzip
import json
import os
import re
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from routing_area_filter import load_outlines, needed  # noqa: E402

TILE_SIZE = {0: 4.0, 1: 1.0, 2: 0.25}

tiles, name, out, index_path = sys.argv[1:5]
version = int(os.environ.get("ROUTING_VERSION", "1"))


def tile_corner(level, tile_id):
    size = TILE_SIZE[level]
    row, col = divmod(tile_id, int(360 / size))
    return -90 + row * size, -180 + col * size  # south-west corner


def covered_countries():
    if os.environ.get("ROUTING_COUNTRIES"):
        return set(os.environ["ROUTING_COUNTRIES"].split())
    source = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "Tileroam", "Planning", "RoutingData.swift")
    match = re.search(r"static let countries: Set<String> = \[([^\]]*)\]", open(source).read())
    return set(re.findall(r'"([A-Z]{2})"', match.group(1)))


countries = covered_countries()
rings = load_outlines(countries)
assert rings, f"no country outlines for {countries}"

target = os.path.join(out, name, f"v{version}")


def pack(job):
    """Gzips one tile; returns [key, compressed size, size]. Runs in a worker process."""
    key, source = job
    raw = open(source, "rb").read()
    packed = os.path.join(target, key + ".gph.gz")
    os.makedirs(os.path.dirname(packed), exist_ok=True)
    with open(packed, "wb") as g:
        g.write(gzip.compress(raw, compresslevel=6, mtime=0))
    return [key, os.path.getsize(packed), len(raw)]


if __name__ == "__main__":
    print(f"Packing the tiles within reach of {' '.join(sorted(countries))}, version {version}")
    shutil.rmtree(target, ignore_errors=True)
    jobs, skipped = [], 0
    for root, _, files in os.walk(tiles):
        for f in files:
            if not f.endswith(".gph"):
                continue
            path = os.path.relpath(os.path.join(root, f), tiles)
            parts = path.split(os.sep)
            level, tile_id = int(parts[0]), int("".join(parts[1:])[:-4])
            lat, lon = tile_corner(level, tile_id)
            if not needed(lat, lon, TILE_SIZE[level], rings):
                skipped += 1
                continue
            jobs.append((path.replace(os.sep, "/")[:-4], os.path.join(tiles, path)))  # "2/000/791/223"
    # Every core: compressing 6 GB of tiles on one takes most of an hour.
    with ProcessPoolExecutor() as pool:
        entries = sorted(pool.map(pack, jobs, chunksize=4))
    with open(index_path, "w") as f:
        json.dump({"name": name, "version": version, "tiles": entries}, f, separators=(",", ":"))
    total = sum(e[1] for e in entries)
    print(f"Left out {skipped} tiles beyond reach; {len(entries)} tiles, {total / 1e6:.0f} MB compressed, "
          f"in {target}; index {os.path.getsize(index_path) / 1000:.0f} KB")
