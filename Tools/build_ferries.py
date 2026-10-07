#!/usr/bin/env python3
"""Builds AssetPacks/Ferries/ferries.json, the ferries' list (Tools/make_challenges.py ferries makes
the challenge file from it; until 1.12 it was the `ferries` asset pack), from OpenStreetMap: the ferries of the routing countries that take cyclists (issue #54).

Ferries: ways tagged route=ferry, joined where they meet (a crossing is often drawn in pieces),
between 30 m and 2 km long: the pontjes and ferries across rivers, canals and lake narrows. Longer
lines are left out: they're mostly boat trips along a river or around a lake, where riding the path
along the shore would look like taking the boat (GPS can't tell them apart), and so are round trips
(both landings in the same place). Also left out: bicycle=no, access=no/private, and disused or
abandoned ones. A ferry in two extracts (on a border) is kept once.

Per ferry: id ("osm-<first way id>"), name (if tagged), from and to (the nearest town, village or
hamlet to each landing, within 5 km), operator and website if tagged, country, length (metres),
lat/lon (the middle of the crossing) and line (encoded polyline, precision 5).
© OpenStreetMap contributors, ODbL.

    AssetPacks/build/climbs/venv/bin/python Tools/build_ferries.py netherlands belgium …
        (the Geofabrik extracts in AssetPacks/build/routing/osm, as for the routing data)
"""
import json
import math
import os
import subprocess
import sys

import osmium

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OSM = os.path.join(ROOT, "AssetPacks", "build", "routing", "osm")
WORK = os.path.join(ROOT, "AssetPacks", "build", "ferries")
OUT = os.path.join(ROOT, "AssetPacks", "Ferries", "ferries.json")
COUNTRY = {"netherlands": "NL", "belgium": "BE", "luxembourg": "LU", "germany": "DE", "france": "FR",
           "switzerland": "CH", "austria": "AT"}
MIN_LENGTH, MAX_LENGTH = 30, 2_000
PLACE_RADIUS = 5_000


def length(points):
    return sum(distance(a, b) for a, b in zip(points, points[1:]))


def distance(a, b):
    return math.hypot((b[0] - a[0]) * 110_574, (b[1] - a[1]) * 111_320 * math.cos(math.radians(a[0])))


def usable(tags):
    if tags.get("route") != "ferry":
        return False
    if tags.get("bicycle") == "no" or tags.get("access") in ("no", "private"):
        return False
    return not (tags.get("disused") == "yes" or tags.get("abandoned") == "yes")


class Collect(osmium.SimpleHandler):
    """Ferry ways with their coordinates, and the places (towns, villages, hamlets)."""

    def __init__(self):
        super().__init__()
        self.ferries = []
        self.places = []

    def node(self, n):
        if n.tags.get("place") in ("city", "town", "village", "hamlet") and "name" in n.tags:
            self.places.append((n.location.lat, n.location.lon, n.tags["name"]))

    def way(self, w):
        tags = {t.k: t.v for t in w.tags}
        if not usable(tags):
            return
        try:
            points = [(n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(points) >= 2:
            self.ferries.append((w.id, tags, points))


def join(ferries):
    """Joins pieces of one crossing (same name, meeting end to end)."""
    lines = []
    for wid, tags, points in sorted(ferries):
        for line in lines:
            if line["tags"].get("name") != tags.get("name"):
                continue
            p, q = line["points"], points
            if p[-1] == q[0]:
                p.extend(q[1:]); break
            if p[-1] == q[-1]:
                p.extend(reversed(q[:-1])); break
            if p[0] == q[-1]:
                p[:0] = q[:-1]; break
            if p[0] == q[0]:
                p[:0] = list(reversed(q[1:])); break
        else:
            lines.append({"id": wid, "tags": tags, "points": list(points)})
    return lines


def nearest_place(point, places):
    best, name = PLACE_RADIUS, None
    for lat, lon, n in places:
        if abs(lat - point[0]) > 0.05 or abs(lon - point[1]) > 0.08:
            continue
        d = distance(point, (lat, lon))
        if d < best:
            best, name = d, n
    return name


def middle(points):
    """The point halfway along the line."""
    half, walked = length(points) / 2, 0.0
    for a, b in zip(points, points[1:]):
        d = distance(a, b)
        if walked + d >= half and d > 0:
            t = (half - walked) / d
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        walked += d
    return points[len(points) // 2]


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
ferries, seen = {}, set()
for extract in sys.argv[1:]:
    filtered = os.path.join(WORK, f"{extract}-ferries.osm.pbf")
    subprocess.run(["osmium", "tags-filter", os.path.join(OSM, f"{extract}-latest.osm.pbf"), "w/route=ferry",
                    "n/place=city,town,village,hamlet", "-o", filtered, "--overwrite", "--no-progress"], check=True)
    handler = Collect()
    handler.apply_file(filtered, locations=True)
    kept = 0
    for line in join(handler.ferries):
        points, tags = line["points"], line["tags"]
        metres = length(points)
        if not MIN_LENGTH <= metres <= MAX_LENGTH or distance(points[0], points[-1]) < metres / 3:
            continue  # too short or long, or a round trip
        # The same crossing from two extracts (a border river): its landings, rounded to ~100 m, or
        # the same way cut off at the extract's edge (keep the longest).
        key = tuple(sorted((round(p[0], 3), round(p[1], 3)) for p in (points[0], points[-1])))
        fid = f"osm-{line['id']}"
        if key in seen or (fid in ferries and ferries[fid]["length"] >= metres):
            continue
        seen.add(key)
        mid = middle(points)
        ferries[fid] = {
            "id": fid,
            "name": tags.get("name"),
            "from": nearest_place(points[0], handler.places),
            "to": nearest_place(points[-1], handler.places),
            "operator": tags.get("operator"),
            "website": tags.get("website"),
            "country": COUNTRY.get(extract, ""),
            "length": round(metres),
            "lat": round(mid[0], 6),
            "lon": round(mid[1], 6),
            "line": encode(points),
        }
        kept += 1
    print(f"{extract}: {len(handler.ferries)} ferry ways, {kept} ferries kept", flush=True)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
ferries = sorted(ferries.values(), key=lambda f: f["id"])
json.dump(ferries, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
print(f"{OUT}: {len(ferries)} ferries, {os.path.getsize(OUT) / 1e3:.0f} KB; "
      f"named {sum(1 for f in ferries if f['name'])}, with both places {sum(1 for f in ferries if f['from'] and f['to'])}")
