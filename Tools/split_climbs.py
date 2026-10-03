#!/usr/bin/env python3
"""Splits the climbs of Tools/build_climbs.py into 1° areas for Cloudflare R2, where the app
downloads the areas it needs (around the user's activities, the map and plans). See docs/CLIMBS.md.

    split_climbs.py <climbs.json> <name> <out dir> <index json>

Each area (by the climb's bottom) becomes <out>/<name>/climbs/v<version>/<area>.json.gz, for
example west/climbs/v1/n50e005.json.gz; the index lists the areas with their number of climbs and
download size. CLIMBS_VERSION is the version (set by build_climbs.sh).
"""
import gzip
import json
import os
import shutil
import sys
from collections import defaultdict

source, name, out, index_path = sys.argv[1:5]
version = int(os.environ.get("CLIMBS_VERSION", "1"))
climbs = json.load(open(source))["climbs"]


def area(lat, lon):
    lat, lon = int(lat // 1), int(lon // 1)
    return f"{'n' if lat >= 0 else 's'}{abs(lat):02d}{'e' if lon >= 0 else 'w'}{abs(lon):03d}"


by_area = defaultdict(list)
for c in climbs:
    by_area[area(*c["start"])].append(c)
target = os.path.join(out, name, "climbs", f"v{version}")
shutil.rmtree(target, ignore_errors=True)
os.makedirs(target)
areas = []
for key, items in sorted(by_area.items()):
    path = os.path.join(target, key + ".json.gz")
    with open(path, "wb") as f:
        f.write(gzip.compress(json.dumps(items, ensure_ascii=False, separators=(",", ":")).encode(), mtime=0))
    areas.append([key, len(items), os.path.getsize(path)])
with open(index_path, "w") as f:
    json.dump({"name": name, "version": version, "areas": areas}, f, separators=(",", ":"))
print(f"Climbs version {version}: {len(climbs)} in {len(areas)} areas, "
      f"{sum(a[2] for a in areas) / 1e6:.1f} MB compressed, in {target}")
