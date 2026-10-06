#!/usr/bin/env python3
"""Builds AssetPacks/MTB/mtb-routes.json, the mountain bike route challenge's list (the `mtbroutes`
asset pack), from OpenStreetMap: the signposted MTB routes of the routing countries.

Signposted: relations with route=mtb and type=route that belong to a network (network=lcn, rcn,
ncn, icn or mtb: in OpenStreetMap the routes of a network are the signposted ones). Left out:
networks, superroutes and collections (groupings of routes), routes without a network (often a
GPS track someone shared), and routes tagged unsigned, signed_route=no, proposed or disused.

Per route: id ("osm-<relation id>"), name (or the ref), ref, network, country, length (metres),
url (the relation on openstreetmap.org), website if tagged, lat/lon (its first point) and
lines: its ways, chained where they meet, simplified to about 10 m, as encoded polylines
(precision 5). © OpenStreetMap contributors, ODbL.

    AssetPacks/build/climbs/venv/bin/pip install osmium
    AssetPacks/build/climbs/venv/bin/python Tools/build_mtb_routes.py netherlands belgium …
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
WORK = os.path.join(ROOT, "AssetPacks", "build", "mtb")
OUT = os.path.join(ROOT, "AssetPacks", "MTB", "mtb-routes.json")
NETWORKS = {"lcn", "rcn", "ncn", "icn", "mtb"}
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


class Collect(osmium.SimpleHandler):
    """Ways with their coordinates, then the signposted MTB relations (relations come last)."""

    def __init__(self):
        super().__init__()
        self.ways = {}
        self.routes = []

    def way(self, w):
        try:
            self.ways[w.id] = [(n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            pass

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
