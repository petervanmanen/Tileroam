#!/usr/bin/env python3
"""Builds AssetPacks/MTB/mtb-routes.json, the mountain bike routes' list (Tools/make_challenges.py
mtb-routes makes the challenge file from it; until 1.12 it was the `mtbroutes` asset pack), from OpenStreetMap: the signposted MTB routes of the routing countries.

Signposted: relations with route=mtb and type=route that belong to a network (network=lcn, rcn,
ncn, icn or mtb: in OpenStreetMap the routes of a network are the signposted ones). Left out:
networks, superroutes and collections (groupings of routes), routes without a network (often a
GPS track someone shared), and routes tagged unsigned, signed_route=no, proposed or disused.

Per route: id ("osm-<relation id>"), name (or the ref), ref, network, country, length (metres),
url (the relation on openstreetmap.org), website if tagged, lat/lon (its first point) and
lines: its ways, chained where they meet, simplified to about 10 m, as encoded polylines
(precision 5). © OpenStreetMap contributors, ODbL.

How hard it is (issue #57): grade 0–3 (easy, moderate, hard, very hard: green, blue, red, black),
- signposted, when the route says so: mtb:difficulty, mtb:scale:imba, or in France, Switzerland
  and Austria its colour (green/blue/red/black is the official grading there; in the Netherlands,
  Belgium and Germany a colour only tells routes apart);
- otherwise estimated from the effort (km + metres of climbing / 100) and, where the paths are
  tagged, their technical grade (mtb:scale, weighted by length).
Also ascent (metres of climbing, from the elevation model in AssetPacks/build/elevation, as for
the climbs) and technical (the average mtb:scale, when at least a third of the route is tagged).

    AssetPacks/build/climbs/venv/bin/pip install osmium numpy
    AssetPacks/build/climbs/venv/bin/python Tools/build_mtb_routes.py netherlands belgium …
        (the Geofabrik extracts in AssetPacks/build/routing/osm, as for the routing data)
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
import osmium

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OSM = os.path.join(ROOT, "AssetPacks", "build", "routing", "osm")
WORK = os.path.join(ROOT, "AssetPacks", "build", "mtb")
OUT = os.path.join(ROOT, "AssetPacks", "MTB", "mtb-routes.json")
NETWORKS = {"lcn", "rcn", "ncn", "icn", "mtb"}
ELEVATION = os.path.join(ROOT, "AssetPacks", "build", "elevation")
# Countries where a route's colour is its difficulty.
COLOUR_GRADES = {"FR", "CH", "AT"}
COLOURS = {"green": 0, "blue": 1, "red": 2, "black": 3}
DIFFICULTY = {"easy": 0, "novice": 0, "noviced": 0, "beginner": 0, "green": 0, "intermediate": 1, "blue": 1,
              "advanced": 2, "red": 2, "difficult": 3, "expert": 3, "heavy": 3, "singletrail": 3, "black": 3}
COUNTRY = {"netherlands": "NL", "belgium": "BE", "luxembourg": "LU", "germany": "DE", "france": "FR",
           "switzerland": "CH", "austria": "AT"}


def signposted(tags):
    if tags.get("type") != "route" or tags.get("route") != "mtb":
        return False
    if tags.get("network") not in NETWORKS:
        return False
    if tags.get("unsigned") == "yes" or tags.get("signed_route") == "no":
        return False
    if tags.get("state") == "proposed" or "disused" in tags.get("state", "") or tags.get("disused") == "yes":
        return False
    return bool(tags.get("name") or tags.get("ref"))


def scale(value):
    """mtb:scale ("0".."6", also "1+", "2-") as a number, or None."""
    try:
        return float(value.rstrip("+-")) + (0.3 if value.endswith("+") else -0.3 if value.endswith("-") else 0)
    except (AttributeError, ValueError):
        return None


class Collect(osmium.SimpleHandler):
    """Ways with their coordinates (and technical grade), then the signposted MTB relations
    (relations come last)."""

    def __init__(self):
        super().__init__()
        self.ways = {}
        self.scales = {}
        self.routes = []

    def way(self, w):
        try:
            self.ways[w.id] = [(n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        s = scale(w.tags.get("mtb:scale"))
        if s is not None:
            self.scales[w.id] = s

    def relation(self, r):
        tags = {t.k: t.v for t in r.tags}
        if signposted(tags):
            self.routes.append((r.id, tags, [m.ref for m in r.members if m.type == "w"]))


def chain(pieces):
    """Joins pieces whose ends meet (in either direction) into longer lines."""
    lines = []
    for p in pieces:
        if len(p) < 2:
            continue
        for line in lines:
            if line[-1] == p[0]:
                line.extend(p[1:]); break
            if line[-1] == p[-1]:
                line.extend(reversed(p[:-1])); break
            if line[0] == p[-1]:
                line[:0] = p[:-1]; break
            if line[0] == p[0]:
                line[:0] = list(reversed(p[1:])); break
        else:
            lines.append(list(p))
    return lines


def length(points):
    return sum(math.hypot((b[0] - a[0]) * 110_574, (b[1] - a[1]) * 111_320 * math.cos(math.radians(a[0])))
               for a, b in zip(points, points[1:]))


def simplify(points, tolerance=10.0):
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


class Elevation:
    """Bilinear samples from 1° hgt tiles (as in Tools/build_climbs.py)."""

    def __init__(self, folder):
        self.folder, self.tiles = folder, {}

    def tile(self, lat, lon):
        if (lat, lon) not in self.tiles:
            name = f"{'N' if lat >= 0 else 'S'}{abs(lat):02d}{'E' if lon >= 0 else 'W'}{abs(lon):03d}"
            path = os.path.join(self.folder, name[:3], name + ".hgt")
            grid = None
            if os.path.exists(path):
                data = np.memmap(path, dtype=">i2", mode="r")
                n = int(round(math.sqrt(data.size)))
                grid = data.reshape(n, n)
            self.tiles[(lat, lon)] = grid
        return self.tiles[(lat, lon)]

    def sample(self, lats, lons):
        out = np.full(len(lats), np.nan)
        cells = np.floor(lats).astype(int), np.floor(lons).astype(int)
        for lat, lon in set(zip(cells[0].tolist(), cells[1].tolist())):
            grid = self.tile(lat, lon)
            if grid is None:
                continue
            mask = (cells[0] == lat) & (cells[1] == lon)
            n = grid.shape[0] - 1
            y, x = (lat + 1 - lats[mask]) * n, (lons[mask] - lon) * n
            y0, x0 = np.clip(np.floor(y).astype(int), 0, n - 1), np.clip(np.floor(x).astype(int), 0, n - 1)
            fy, fx = y - y0, x - x0
            v = [grid[y0, x0], grid[y0, x0 + 1], grid[y0 + 1, x0], grid[y0 + 1, x0 + 1]]
            v = [np.where(a == -32768, np.nan, a.astype(float)) for a in v]
            out[mask] = v[0] * (1 - fx) * (1 - fy) + v[1] * fx * (1 - fy) + v[2] * (1 - fx) * fy + v[3] * fx * fy
        return out


def ascent(line, elevation, step=30.0):
    """Metres of climbing along a line: sampled every 30 m, smoothed over 90 m, counting rises
    only once they exceed 3 m (the elevation model's noise would add up otherwise)."""
    lats, lons = [], []
    for a, b in zip(line, line[1:]):
        n = max(1, int(length([a, b]) // step))
        for i in range(n):
            lats.append(a[0] + (b[0] - a[0]) * i / n)
            lons.append(a[1] + (b[1] - a[1]) * i / n)
    lats.append(line[-1][0]); lons.append(line[-1][1])
    h = elevation.sample(np.array(lats), np.array(lons))
    h = h[~np.isnan(h)]
    if len(h) < 4:
        return 0.0
    h = np.convolve(h, np.ones(3) / 3, mode="valid")
    total, low = 0.0, h[0]
    for v in h[1:]:
        if v < low:
            low = v
        elif v - low > 3:
            total += v - low
            low = v
    return total


def grade(tags, country, metres, climb, technical):
    """0–3 and whether it's signposted (see the module's notes)."""
    for key in ("mtb:difficulty", "difficulty"):
        g = DIFFICULTY.get(tags.get(key, "").lower())
        if g is not None:
            return g, True
    imba = scale(tags.get("mtb:scale:imba"))
    if imba is not None:
        return (0 if imba <= 1 else 1 if imba < 3 else 2 if imba < 4 else 3), True
    if country in COLOUR_GRADES and tags.get("colour", "").lower() in COLOURS:
        return COLOURS[tags["colour"].lower()], True
    effort = metres / 1000 + climb / 100
    g = 0 if effort < 20 else 1 if effort < 40 else 2 if effort < 70 else 3
    if technical is not None:
        g = max(g, 3 if technical >= 2.5 else 2 if technical >= 1.5 else 1 if technical >= 0.8 else 0)
    return g, False


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


os.makedirs(WORK, exist_ok=True)
elevation = Elevation(ELEVATION)
routes = {}
for extract in sys.argv[1:]:
    # The MTB relations with their ways and nodes, then ways with coordinates.
    filtered = os.path.join(WORK, f"{extract}-mtb.osm.pbf")
    subprocess.run(["osmium", "tags-filter", os.path.join(OSM, f"{extract}-latest.osm.pbf"), "r/route=mtb",
                    "-o", filtered, "--overwrite", "--no-progress"], check=True)
    handler = Collect()
    handler.apply_file(filtered, locations=True)
    kept = 0
    for rid, tags, member_ways in handler.routes:
        lines = [simplify(line) for line in chain([handler.ways[w] for w in member_ways if w in handler.ways])]
        lines = [l for l in lines if len(l) >= 2]
        metres = sum(length(l) for l in lines)
        if metres < 1000:
            continue
        # Technical grade: the paths' mtb:scale, weighted by length, when a third is tagged.
        tagged = [(length(handler.ways[w]), handler.scales[w]) for w in member_ways if w in handler.scales and w in handler.ways]
        tagged_m = sum(m for m, _ in tagged)
        technical = round(sum(m * s for m, s in tagged) / tagged_m, 1) if tagged_m >= metres / 3 else None
        climb = sum(ascent(l, elevation) for l in lines)
        level, posted = grade(tags, COUNTRY.get(extract, ""), metres, climb, technical)
        if f"osm-{rid}" in routes and routes[f"osm-{rid}"]["length"] >= metres:
            continue  # a route across a border is in both extracts, each with its own part: keep the longest
        routes[f"osm-{rid}"] = {
            "id": f"osm-{rid}",
            "name": tags.get("name") or tags.get("ref"),
            "ref": tags.get("ref"),
            "network": tags["network"],
            "country": COUNTRY.get(extract, ""),
            "length": round(metres),
            "url": f"https://www.openstreetmap.org/relation/{rid}",
            "website": tags.get("website"),
            "ascent": round(climb),
            "grade": level,
            "signposted": posted,
            "technical": technical,
            "lat": round(lines[0][0][0], 6),
            "lon": round(lines[0][0][1], 6),
            "lines": [encode(l) for l in lines],
        }
        kept += 1
    print(f"{extract}: {len(handler.routes)} signposted MTB relations, {kept} kept", flush=True)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
data = sorted(routes.values(), key=lambda r: r["id"])
json.dump(data, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
km = sum(r["length"] for r in data) / 1000
print(f"{OUT}: {len(data)} routes, {km:,.0f} km, {os.path.getsize(OUT) / 1e6:.1f} MB")
grades = [sum(1 for r in data if r["grade"] == g) for g in range(4)]
print(f"grades (easy, moderate, hard, very hard): {grades}; signposted: {sum(r['signposted'] for r in data)}")
