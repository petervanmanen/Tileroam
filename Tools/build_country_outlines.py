#!/usr/bin/env python3
"""Builds Tileroam/Resources/countries.fmr: simplified country outlines, bundled in the app to
tell which countries an activity was in before downloading that country's boundaries.

The outlines are the union of each country's municipalities from AssetPacks/Regions, so they
match the downloaded data. Same FMR format as the region files (see build_regions.py), one
area per country with code "<CC>:<CC>".

Usage:
    python3 -m venv venv && venv/bin/pip install shapely
    venv/bin/python Tools/build_country_outlines.py [meters]   # simplification, default 200
"""
import glob
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fmr import read_fmr  # noqa: E402

from shapely import make_valid
from shapely.geometry import MultiPolygon, Polygon, box
from shapely.ops import unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "AssetPacks", "Regions")
OUT = os.path.join(ROOT, "Tileroam", "Resources", "countries.fmr")
METERS = float(sys.argv[1]) if len(sys.argv) > 1 else 200
DEG = 1 / 111_000


def polygons(g):
    if isinstance(g, Polygon):
        return [g] if not g.is_empty else []
    return [p for part in getattr(g, "geoms", []) for p in polygons(part)]


def varint(n, out):
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def zigzag(n):
    return (n << 1) ^ (n >> 63)


body = bytearray(b"FMR1")
files = sorted(glob.glob(os.path.join(SRC, "*-municipalities.fmr")))
body += struct.pack("<I", len(files))
last = [0, 0]
total_points = 0
for path in files:
    country = os.path.basename(path).split("-")[0]
    parts = []
    for _, _, polys in read_fmr(path):
        for rings in polys:
            if len(rings[0]) >= 3:
                parts.append(make_valid(Polygon(rings[0], [r for r in rings[1:] if len(r) >= 3])))
    # Close the hairline gaps between municipalities, then simplify.
    gap = 50 * DEG
    outline = unary_union(parts).buffer(gap, join_style="mitre").buffer(-gap, join_style="mitre")
    outline = make_valid(outline.simplify(METERS * DEG, preserve_topology=True))
    # Keep islands of at least ~1.5 km × 1.5 km (a ride on a smaller one is rare), and the largest part.
    keep = sorted(polygons(outline), key=lambda p: -p.area)
    keep = keep[:1] + [p for p in keep[1:] if p.area >= (1500 * DEG) ** 2]
    # Cut into 1° × 1° pieces so a point-in-polygon test in the app only checks a small piece.
    pieces = []
    for p in keep:
        x0, y0, x1, y1 = p.bounds
        for gx in range(int(x0 // 1), int(x1 // 1) + 1):
            for gy in range(int(y0 // 1), int(y1 // 1) + 1):
                pieces += polygons(make_valid(p.intersection(box(gx, gy, gx + 1, gy + 1))))
    keep = [q for q in pieces if len(q.exterior.coords) >= 4]

    code = f"{country}:{country}".encode()
    body.append(len(code)); body += code
    body += struct.pack("<H", len(country)); body += country.encode()
    varint(len(keep), body)
    points = 0
    for p in keep:
        rings = [p.exterior]  # holes don't matter for "which country is this point in"
        varint(len(rings), body)
        for ring in rings:
            coords = list(ring.coords)[:-1]
            varint(len(coords), body)
            for x, y in coords:
                la, lo = round(y * 1e5), round(x * 1e5)
                varint(zigzag(la - last[0]), body)
                varint(zigzag(lo - last[1]), body)
                last = [la, lo]
                points += 1
    total_points += points
    print(f"{country}: {len(keep):5} pieces {points:6} points")

compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
data = compressor.compress(bytes(body)) + compressor.flush()
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "wb").write(data)
print(f"{OUT}: {total_points} points, {len(data) / 1e3:.0f} KB")
