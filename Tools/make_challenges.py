#!/usr/bin/env python3
"""Makes Tileroam challenge files (challenges/README.md) from the lists of the challenges that were
built into the app until 1.12: the Trappist breweries, the boscafés, the ferries, the Klompenpaden
and the mountain bike routes.

    Tools/make_challenges.py                 # all five, into challenges/
    Tools/make_challenges.py trappist-breweries ferries
    Tools/make_challenges.py --out ~/Desktop/challenges

The sources are the lists in AssetPacks/ (Trappist/trappists.json, Boscafes/boscafes.json,
Ferries/ferries.json, Klompenpaden/klompenpaden.json, MTB/mtb-routes.json), made by
Tools/build_ferries.py, Tools/build_klompenpaden.py, Tools/build_mtb_routes.py and
Tools/import_boscafes.py. A list that isn't there is taken from git (the commit before they were
removed from the repository). Only trappist-breweries.geojson is in git; the others are in
.gitignore. Copy the files to iCloud Drive › Tileroam › Challenges to use them.
"""
import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The last commit with the lists in the repository.
LISTS_COMMIT = "701a62d"


def load(path):
    full = os.path.join(ROOT, path)
    if os.path.exists(full):
        with open(full, encoding="utf-8") as f:
            return json.load(f)
    data = subprocess.run(["git", "-C", ROOT, "show", f"{LISTS_COMMIT}:{path}"], capture_output=True, check=True).stdout
    return json.loads(data)


def decode_polyline(encoded, precision=5):
    """Google's encoded polyline → [[lon, lat], …] (GeoJSON order)."""
    points, index, lat, lon, factor = [], 0, 0, 0, 10 ** precision
    while index < len(encoded):
        for which in (0, 1):
            shift = result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if which == 0:
                lat += delta
            else:
                lon += delta
        points.append([round(lon / factor, 5), round(lat / factor, 5)])
    return points


def point(lon, lat):
    return {"type": "Point", "coordinates": [round(lon, 6), round(lat, 6)]}


def lines(encoded):
    pieces = [decode_polyline(e) for e in encoded]
    pieces = [p for p in pieces if len(p) >= 2]
    if len(pieces) == 1:
        return {"type": "LineString", "coordinates": pieces[0]}
    return {"type": "MultiLineString", "coordinates": pieces}


def feature(id, geometry, **properties):
    return {"type": "Feature", "id": id, "geometry": geometry,
            "properties": {k: v for k, v in properties.items() if v not in (None, "")}}


def web(url):
    return url if isinstance(url, str) and url.startswith(("https://", "http://")) else None


def km(metres):
    value = metres / 1000
    return f"{value:.0f} km" if value >= 10 else f"{value:.1f} km"


def trappists():
    features = [feature(b["id"], point(b["lon"], b["lat"]), name=b["name"], subtitle=f'{b["abbey"]} · {b["place"]}')
                for b in load("AssetPacks/Trappist/trappists.json")]
    return {"format": 1, "id": "trappist-breweries", "name": "Trappist breweries", "tab": "Trappists",
            "kind": "locations", "icon": "🍺", "radius": 200,
            "description": "Ride past the breweries of the Trappist abbeys.",
            "attribution": "Names and locations of the breweries from public sources"}, features


def boscafes():
    features = [feature(c["id"], point(c["lon"], c["lat"]), name=c["name"], subtitle=c["place"], icon=c.get("emoji"))
                for c in load("AssetPacks/Boscafes/boscafes.json")]
    return {"format": 1, "id": "boscafes", "name": "Boscafés", "kind": "locations", "icon": "🌲", "radius": 200,
            "description": "Visit the cafés and pavilions in the woods of the Netherlands.",
            "attribution": "Names and locations of the boscafés from public sources"}, features


def ferries():
    features = []
    for f in load("AssetPacks/Ferries/ferries.json"):
        name = f.get("name") or (f'{f["from"]} – {f["to"]}' if f.get("from") and f.get("to") and f["from"] != f["to"]
                                 else f'Ferry at {f.get("from") or f.get("to")}' if f.get("from") or f.get("to") else "Ferry")
        parts = []
        if f.get("name") and f.get("from") and f.get("to") and f["from"] != f["to"]:
            parts.append(f'{f["from"]} – {f["to"]}')
        if f.get("operator"):
            parts.append(f["operator"])
        osm = f'https://www.openstreetmap.org/way/{f["id"][4:]}' if f["id"].startswith("osm-") else None
        features.append(feature(f["id"], lines([f["line"]]), name=name, subtitle=" · ".join(parts), url=web(f.get("website")) or osm))
    return {"format": 1, "id": "ferries", "name": "Ferries", "kind": "routes", "complete": "cross", "icon": "⛴️",
            "description": "Cross on the ferries that take your bike.",
            "attribution": "Ferries that take cyclists: © OpenStreetMap contributors (ODbL), "
                           "[openstreetmap.org](https://www.openstreetmap.org/copyright)"}, features


def klompenpaden():
    features = []
    for p in load("AssetPacks/Klompenpaden/klompenpaden.json"):
        lengths = ", ".join(f"{v:g}" for v in p["lengths"])
        features.append(feature(p["id"], lines(p["lines"]), name=p["name"], subtitle=f'From {p["start"]} · {lengths} km', url=p["url"]))
    return {"format": 1, "id": "klompenpaden", "name": "Klompenpaden", "kind": "routes", "complete": "cover",
            "coverage": 0.9, "spacing": 50, "icon": "🥾",
            "description": "Walk the country paths of Gelderland and Utrecht.",
            "attribution": "Routes and names of the Klompenpaden: [www.klompenpaden.nl](https://www.klompenpaden.nl)"}, features


NETWORKS = {"lcn": "Local route", "rcn": "Regional route", "ncn": "National route", "icn": "International route"}
DIFFICULTY = ["easy", "moderate", "hard", "very-hard"]


def mtb_routes():
    features = []
    for r in load("AssetPacks/MTB/mtb-routes.json"):
        parts = [NETWORKS.get(r["network"], "MTB route")]
        if r.get("ascent") and r["ascent"] >= 1:
            parts.append(f'{round(r["ascent"])} m climbing')
        grade = r.get("grade")
        features.append(feature(r["id"], lines(r["lines"]), name=r["name"], subtitle=" · ".join(parts),
                                url=web(r.get("website")) or r["url"],
                                difficulty=DIFFICULTY[grade] if grade is not None and 0 <= grade < 4 else None))
    return {"format": 1, "id": "mtb-routes", "name": "Mountain bike routes", "tab": "MTB", "kind": "routes",
            "complete": "cover", "coverage": 0.9, "spacing": 100, "icon": "🚵", "sports": ["Cycling", "E-biking"],
            "description": "Ride the signposted mountain bike routes.",
            "attribution": "Signposted mountain bike routes: © OpenStreetMap contributors (ODbL), "
                           "[openstreetmap.org](https://www.openstreetmap.org/copyright)"}, features


CHALLENGES = {"trappist-breweries": trappists, "boscafes": boscafes, "ferries": ferries,
              "klompenpaden": klompenpaden, "mtb-routes": mtb_routes}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", metavar="name", help=", ".join(CHALLENGES))
    parser.add_argument("--out", default=os.path.join(ROOT, "challenges"))
    args = parser.parse_args()
    unknown = [n for n in args.names if n not in CHALLENGES]
    if unknown:
        parser.error(f"unknown: {', '.join(unknown)}")
    os.makedirs(args.out, exist_ok=True)
    for name in args.names or CHALLENGES:
        header, features = CHALLENGES[name]()
        path = os.path.join(args.out, f"{name}.geojson")
        with open(path, "w", encoding="utf-8") as f:
            # One feature per line: readable, and small diffs.
            f.write('{"type": "FeatureCollection",\n "tileroam": ' + json.dumps(header, ensure_ascii=False) + ',\n "features": [\n')
            f.write(",\n".join("  " + json.dumps(x, ensure_ascii=False, separators=(",", ":")) for x in features))
            f.write("\n ]}\n")
        print(f"{path}: {len(features)} {'places' if header['kind'] == 'locations' else 'routes'}, "
              f"{os.path.getsize(path) / 1e6:.1f} MB")


if __name__ == "__main__":
    sys.exit(main())
