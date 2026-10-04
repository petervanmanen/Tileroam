#!/usr/bin/env python3
"""Builds Tileroam/Resources/world.fmr: simplified outlines of all countries of the world, bundled
in the app to count the countries of the user's activities (the Globetrotter badge) on the device.

Source: Natural Earth's admin-0 countries at 1:50 million (public domain,
https://www.naturalearthdata.com), from
https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
Countries are identified by ISO_A2_EH (ISO_A2 is "-99" for France, Norway and Kosovo);
Somaliland counts as Somalia and Northern Cyprus as Cyprus, disputed Siachen is left out.
Same FMR format as countries.fmr (see build_country_outlines.py): one area per country with
code "<CC>:<CC>", cut into 1° × 1° pieces so a lookup only tests a small piece.

Usage:
    python3 -m venv venv && venv/bin/pip install shapely
    curl -fsSL -o AssetPacks/build/world/ne_50m_admin_0_countries.geojson <URL above>
    venv/bin/python Tools/build_world_countries.py [metres]   # simplification, default 500
"""
import json
import os
import struct
import sys
import zlib
from collections import defaultdict

from shapely import make_valid
from shapely.geometry import Polygon, box, shape
from shapely.ops import unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "AssetPacks", "build", "world", "ne_50m_admin_0_countries.geojson")
OUT = os.path.join(ROOT, "Tileroam", "Resources", "world.fmr")
METERS = float(sys.argv[1]) if len(sys.argv) > 1 else 500
DEG = 1 / 111_000
SAME_AS = {"Somaliland": "SO", "Northern Cyprus": "CY"}


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


shapes = defaultdict(list)
for f in json.load(open(SRC))["features"]:
    p = f["properties"]
    code = SAME_AS.get(p["ADMIN"]) or p.get("ISO_A2_EH")
    if not code or code == "-99":
        print(f"left out: {p['ADMIN']}")
        continue
    shapes[code].append(make_valid(shape(f["geometry"])))

body = bytearray(b"FMR1")
body += struct.pack("<I", len(shapes))
last = [0, 0]
total = 0
for code in sorted(shapes):
    outline = make_valid(unary_union(shapes[code]).simplify(METERS * DEG, preserve_topology=True))
    pieces = []
    for p in polygons(outline):
        x0, y0, x1, y1 = p.bounds
        for gx in range(int(x0 // 1), int(x1 // 1) + 1):
            for gy in range(int(y0 // 1), int(y1 // 1) + 1):
                pieces += polygons(make_valid(p.intersection(box(gx, gy, gx + 1, gy + 1))))
    pieces = [q for q in pieces if len(q.exterior.coords) >= 4]
    key = f"{code}:{code}".encode()
    body.append(len(key)); body += key
    body += struct.pack("<H", len(code)); body += code.encode()
    varint(len(pieces), body)
    for q in pieces:
        varint(1, body)  # the outer ring only: holes don't matter for "which country is this"
        coords = list(q.exterior.coords)[:-1]
        varint(len(coords), body)
        for x, y in coords:
            la, lo = round(y * 1e5), round(x * 1e5)
            varint(zigzag(la - last[0]), body)
            varint(zigzag(lo - last[1]), body)
            last = [la, lo]
            total += 1

compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
data = compressor.compress(bytes(body)) + compressor.flush()
open(OUT, "wb").write(data)
print(f"{OUT}: {len(shapes)} countries, {total} points, {len(data) / 1e3:.0f} KB")
