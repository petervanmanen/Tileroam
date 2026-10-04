#!/usr/bin/env python3
"""Builds AssetPacks/Klompenpaden/klompenpaden.json, the Klompenpaden challenge's list for the
`klompenpaden` asset pack (Tools/upload_asset_packs.sh klompenpaden, or the Asset packs workflow
when it changes on main), from the GPX files and the list in AssetPacks/Klompenpaden/source
(fetched from www.klompenpaden.nl by source/fetch_klompenpaden.py: the paths longer than 5 km).

Per path: id (the GPX file name), name, start (village), lengths (km, of its variants), url,
lat/lon (the start) and lines: its main route ("mainRoute" tracks, often in several pieces) as
encoded polylines (precision 5), simplified to about 5 m. Shortcuts, extensions and approaches
are left out: a path counts as walked when its main route is.

    python3 Tools/build_klompenpaden.py
"""
import csv
import json
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "AssetPacks", "Klompenpaden", "source")
OUT = os.path.join(ROOT, "AssetPacks", "Klompenpaden", "klompenpaden.json")


def simplify(points, tolerance=5.0):
    """Douglas–Peucker in metres (local flat approximation)."""
    if len(points) < 3:
        return points
    k = math.cos(math.radians(points[0][0])) * 111_320

    def dist(p, a, b):
        ax, ay, bx, by = (a[1] - p[1]) * k, (a[0] - p[0]) * 110_574, (b[1] - p[1]) * k, (b[0] - p[0]) * 110_574
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        t = max(0, min(1, -(ax * dx + ay * dy) / l2)) if l2 else 0
        return math.hypot(ax + t * dx, ay + t * dy)

    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        best, index = 0, None
        for m in range(i + 1, j):
            d = dist(points[m], points[i], points[j])
            if d > best:
                best, index = d, m
        if index is not None and best > tolerance:
            keep[index] = True
            stack += [(i, index), (index, j)]
    return [p for p, k_ in zip(points, keep) if k_]


def encode(points):
    out, plat, plon = [], 0, 0
    for lat, lon in points:
        ilat, ilon = int(round(lat * 1e5)), int(round(lon * 1e5))
        for d in (ilat - plat, ilon - plon):
            d = ~(d << 1) if d < 0 else d << 1
            while d >= 0x20:
                out.append(chr((0x20 | (d & 0x1F)) + 63))
                d >>= 5
            out.append(chr(d + 63))
        plat, plon = ilat, ilon
    return "".join(out)


def length(points):
    return sum(math.hypot((b[0] - a[0]) * 110_574, (b[1] - a[1]) * 111_320 * math.cos(math.radians(a[0])))
               for a, b in zip(points, points[1:]))


rows = {r["gpx"]: r for r in csv.DictReader(open(os.path.join(SRC, "klompenpaden_all.csv"), encoding="utf-8"))}
paths = []
for gpx_name in sorted(os.listdir(os.path.join(SRC, "gpx"))):
    row = rows.get(f"gpx/{gpx_name}")
    assert row, f"{gpx_name} is not in klompenpaden_all.csv"
    xml = open(os.path.join(SRC, "gpx", gpx_name), encoding="utf-8").read()
    lines, metres = [], 0.0
    for seg in re.findall(r"<type>mainRoute</type>\s*<trkseg>(.*?)</trkseg>", xml, re.S):
        pts = [(float(a), float(b)) for a, b in re.findall(r'<trkpt lat="([-\d.]+)" lon="([-\d.]+)"', seg)]
        if len(pts) >= 2:
            metres += length(pts)
            lines.append(encode(simplify(pts)))
    assert lines, f"{gpx_name}: no main route"
    paths.append({
        "id": os.path.splitext(gpx_name)[0],
        "name": row["name"],
        "start": row["start"],
        "lengths": [float(x) for x in row["lengths_km"].split(",")],
        "url": row["url"],
        "lat": round(float(row["lat"]), 6),
        "lon": round(float(row["lon"]), 6),
        "length": round(metres),
        "lines": lines,
    })

json.dump(paths, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
print(f"{OUT}: {len(paths)} paths, {sum(len(l) for p in paths for l in p['lines']) / 1e3:.0f} KB of lines, "
      f"{os.path.getsize(OUT) / 1e3:.0f} KB")
