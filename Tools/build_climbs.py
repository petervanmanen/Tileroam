#!/usr/bin/env python3
"""Finds the climbs on the cycling road network of OpenStreetMap extracts, from an elevation model.
Called by Tools/build_climbs.sh; see docs/CLIMBS.md.

    build_climbs.py <elevation dir> <out.json> <extract.osm.pbf>…

1. Roads: trunk, primary, secondary, tertiary, unclassified and residential roads, living streets
   and cycleways (not motorways, service roads or unpaved tracks), exported with osmium.
2. Pieces of the same road (same ref, else same name, meeting end to end) are joined into one
   line; unnamed pieces only where exactly two meet. Joining by ref keeps a col road in one
   piece where its name changes on the way up (the D 918 over the Tourmalet has ten names).
3. Each line is sampled every 20 m from the elevation tiles (Valhalla's "skadi" layout:
   N52/N52E005.hgt) and smoothed over 60 m.
4. Climbs, in both directions: from a low point up to the highest point reached before the road
   drops more than 10 m, without the flat run-up. Kept when they're categorised like Strava's
   climbs (average at least 3%, length × gradient ≥ 8,000 for Cat 4, 16,000 Cat 3, 32,000 Cat 2,
   64,000 Cat 1, 80,000 HC) or a short steep hill (at least 300 m at 5% or more).
5. The same climb found twice (dual carriageways, overlapping pieces) is kept once, and each gets
   a name: the road name used most on its upper half (else anywhere on it, else the ref), and the
   nearest place at the top.

Output: {"climbs": [{id, name, place, cat, length, gain, avg, max, top, start, end, line}]}, with
the line as a Google encoded polyline (precision 5) of points every ~20 m, simplified.
"""
import hashlib
import json
import math
import os
import subprocess
import sys
from collections import defaultdict

import numpy as np

STEP = 20.0          # metres between profile samples
SMOOTH = 3           # samples in the moving average (60 m; more flattens short steep hills further)
DROP = 10.0          # metres a climb may dip before it ends
# Long climbs may dip more: 5% of the height gained so far, up to 50 m. The elevation model has
# false dips of 10–30 m on hairpins, which otherwise cut the Tourmalet or Alpe d'Huez in pieces.
DROP_SHARE, DROP_MAX = 0.05, 50
ROAD_TYPES = "trunk,primary,secondary,tertiary,unclassified,residential,living_street,cycleway"
CATEGORIES = [(80000, "HC"), (64000, "1"), (32000, "2"), (16000, "3"), (8000, "4")]

elevation_dir, out_path, extracts = sys.argv[1], sys.argv[2], sys.argv[3:]


# MARK: Elevation

class Elevation:
    """Bilinear samples from 1° hgt tiles (big-endian int16, 3601 or 1201 rows, -32768 = void)."""

    def __init__(self, folder):
        self.folder, self.tiles = folder, {}

    def tile(self, lat, lon):
        key = (lat, lon)
        if key not in self.tiles:
            name = f"{'N' if lat >= 0 else 'S'}{abs(lat):02d}{'E' if lon >= 0 else 'W'}{abs(lon):03d}"
            path = os.path.join(self.folder, name[:3], name + ".hgt")
            if os.path.exists(path):
                data = np.memmap(path, dtype=">i2", mode="r")
                n = int(round(math.sqrt(data.size)))
                self.tiles[key] = data.reshape(n, n)
            else:
                self.tiles[key] = None
        return self.tiles[key]

    def sample(self, lats, lons):
        out = np.full(len(lats), np.nan)
        cells = np.floor(lats).astype(int), np.floor(lons).astype(int)
        for lat, lon in set(zip(cells[0].tolist(), cells[1].tolist())):
            grid = self.tile(lat, lon)
            if grid is None:
                continue
            mask = (cells[0] == lat) & (cells[1] == lon)
            n = grid.shape[0] - 1
            y = (lat + 1 - lats[mask]) * n  # rows run north to south
            x = (lons[mask] - lon) * n
            y0, x0 = np.clip(np.floor(y).astype(int), 0, n - 1), np.clip(np.floor(x).astype(int), 0, n - 1)
            fy, fx = y - y0, x - x0
            v = [grid[y0, x0], grid[y0, x0 + 1], grid[y0 + 1, x0], grid[y0 + 1, x0 + 1]]
            v = [np.where(a == -32768, np.nan, a.astype(float)) for a in v]
            out[mask] = (v[0] * (1 - fx) * (1 - fy) + v[1] * fx * (1 - fy) + v[2] * (1 - fx) * fy + v[3] * fx * fy)
        return out


# MARK: Roads

def roads(pbf):
    """(ref or name, [(lon, lat, flat, name, kind)]) per way, streamed from osmium; name is an
    index into NAMES (or -1), kind one into HIGHWAYS."""
    filtered = os.path.join(os.path.dirname(out_path), os.path.basename(pbf) + ".roads.pbf")
    subprocess.run(["osmium", "tags-filter", pbf, f"w/highway={ROAD_TYPES}", "-o", filtered, "--overwrite", "--no-progress"], check=True)
    proc = subprocess.Popen(["osmium", "export", filtered, "-f", "geojsonseq", "--geometry-types=linestring", "--no-progress",
                             "-a", "id"], stdout=subprocess.PIPE, text=True)
    for line in proc.stdout:
        line = line.lstrip("\x1e")
        if not line.strip():
            continue
        f = json.loads(line)
        p = f["properties"]
        if p.get("bicycle") == "no" or p.get("motorroad") == "yes" or p.get("access") in ("no", "private"):
            continue
        coords = f["geometry"]["coordinates"]
        # On bridges and in tunnels the elevation model has the valley or the hill, not the road.
        flat = p.get("bridge", "no") != "no" or p.get("tunnel", "no") != "no"
        # Compact: millions of road pieces for a large country.
        name = name_index(p["name"]) if p.get("name") else -1
        kind = HIGHWAYS.index(p["highway"]) if p.get("highway") in HIGHWAYS else -1
        yield p.get("ref") or p.get("name"), np.array([(x, y, 1.0 if flat else 0.0, name, kind) for x, y in coords])
    proc.wait()
    os.remove(filtered)


NAMES, NAME_IDS = [], {}
HIGHWAYS = ROAD_TYPES.split(",")


def name_index(name):
    if name not in NAME_IDS:
        NAME_IDS[name] = len(NAMES)
        NAMES.append(name)
    return NAME_IDS[name]


def places(pbf):
    """(name, lon, lat) of towns, villages and hamlets, for naming unnamed climbs."""
    filtered = os.path.join(os.path.dirname(out_path), os.path.basename(pbf) + ".places.pbf")
    subprocess.run(["osmium", "tags-filter", pbf, "n/place=city,town,village,hamlet", "-o", filtered, "--overwrite", "--no-progress"], check=True)
    out = subprocess.run(["osmium", "export", filtered, "-f", "geojsonseq", "--no-progress"], capture_output=True, text=True, check=True).stdout
    os.remove(filtered)
    for line in out.splitlines():
        line = line.lstrip("\x1e")
        if line.strip():
            f = json.loads(line)
            if f["properties"].get("name"):
                lon, lat = f["geometry"]["coordinates"]
                yield f["properties"]["name"], lon, lat


def chains(ways):
    """Joins ways of the same road that meet end to end into longer lines."""
    by_end = defaultdict(list)
    for i, (key, coords) in enumerate(ways):
        for end in (coords[0], coords[-1]):
            by_end[(key, round(end[0], 6), round(end[1], 6))].append(i)
    used = [False] * len(ways)

    def away(j, point):
        """Direction of way j leaving `point` (one of its ends)."""
        c = ways[j][1]
        if round(c[0][0], 6) == round(point[0], 6) and round(c[0][1], 6) == round(point[1], 6):
            return c[1][0] - c[0][0], c[1][1] - c[0][1]
        return c[-2][0] - c[-1][0], c[-2][1] - c[-1][1]

    def next_way(key, point, heading, kind):
        candidates = [j for j in by_end[(key, round(point[0], 6), round(point[1], 6))] if not used[j]]
        # Unnamed roads only continue where exactly two pieces meet.
        if key is None and len(by_end[(key, round(point[0], 6), round(point[1], 6))]) != 2:
            return None
        if not candidates or (key is None and len(candidates) != 1):
            return None
        # Where a road splits (one-way pairs, a fork of the same ref), stay on the same kind of
        # road (a side street may go straight on at a hairpin, as on the Cauberg), then go
        # straightest on: the first piece found could be the other carriageway, back the way
        # the road came.
        def turn(j):
            dx, dy = away(j, point)
            return (ways[j][1][0][4] != kind,
                    -(dx * heading[0] + dy * heading[1]) / (math.hypot(dx, dy) * math.hypot(*heading) or 1))
        return min(candidates, key=turn)

    # Major roads first, so a side street with the same name doesn't take over a main road's pieces.
    for i in sorted(range(len(ways)), key=lambda i: ways[i][1][0][4] if ways[i][1][0][4] >= 0 else len(HIGHWAYS)):
        key, coords = ways[i]
        if used[i]:
            continue
        used[i] = True
        parts = [coords]
        for forward in (True, False):
            while True:
                end = parts[-1][-1] if forward else parts[0][0]
                # (A joined piece can be a single point: its way's other end.)
                if forward:
                    before = parts[-1][-2] if len(parts[-1]) > 1 else parts[-2][-1]
                else:
                    before = parts[0][1] if len(parts[0]) > 1 else parts[1][0]
                j = next_way(key, end, (end[0] - before[0], end[1] - before[1]), end[4])
                if j is None:
                    break
                used[j] = True
                c = ways[j][1]
                starts_here = round(c[0][0], 6) == round(end[0], 6) and round(c[0][1], 6) == round(end[1], 6)
                piece = c[1:] if starts_here else c[::-1][1:]
                if forward:
                    parts.append(piece)
                else:
                    parts.insert(0, piece[::-1])
        yield key, np.concatenate(parts)


GAP = 300  # metres between the ends of two pieces of the same road that are joined anyway


def stitch(lines):
    """Joins lines of the same road whose ends are close but don't meet: where a road's ref or
    name is missing on a stretch, for example on the one-way streets through a village (the
    D 918 in Barèges). The gap counts as a bridge: its elevation is interpolated."""
    lines = [[key, line] for key, line in lines]
    for _ in range(3):
        ends = defaultdict(list)  # (key, cell) → [(line index, at start?)]
        for i, (key, line) in enumerate(lines):
            if key is None or line is None:
                continue
            for start in (True, False):
                p = line[0] if start else line[-1]
                ends[(key, int(p[0] * 200), int(p[1] * 200))].append((i, start))

        def nearest(i, start):
            key, line = lines[i]
            p = line[0] if start else line[-1]
            k = math.cos(math.radians(p[1]))
            best, best_d = None, GAP
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for j, s in ends[(key, int(p[0] * 200) + dx, int(p[1] * 200) + dy)]:
                        if j == i or lines[j][1] is None:
                            continue
                        q = lines[j][1][0] if s else lines[j][1][-1]
                        d = math.hypot((q[0] - p[0]) * k, q[1] - p[1]) * 111_320
                        if d < best_d:
                            best, best_d = (j, s), d
            return best

        joined = 0
        for i in range(len(lines)):
            for start in (True, False):
                if lines[i][1] is None or lines[i][0] is None:
                    continue
                other = nearest(i, start)
                if other is None or nearest(*other) != (i, start):
                    continue
                j, s = other
                a = lines[i][1] if not start else lines[i][1][::-1]   # ends at the gap
                b = lines[j][1] if s else lines[j][1][::-1]           # starts at the gap
                # Only the gap is flat: two points just inside it, so the roads on either side
                # keep their own elevation (marking their end points would flatten short streets).
                gap = np.array([[*(a[-1, :2] + (b[0, :2] - a[-1, :2]) * f), 1.0, -1.0, a[-1, 4]] for f in (0.02, 0.98)])
                lines[i][1] = np.concatenate([a, gap, b])
                lines[j][1] = None
                joined += 1
        if not joined:
            break
    return [(key, line) for key, line in lines if line is not None]


# MARK: Profiles and climbs

def resample(line):
    """Points every STEP metres along the line, their distances, which are on a bridge or in a
    tunnel, and their road names (indexes into NAMES)."""
    lon, lat, flat = line[:, 0], line[:, 1], line[:, 2]
    k = math.cos(math.radians(float(lat.mean())))
    seg = np.hypot(np.diff(lon) * k, np.diff(lat)) * 111_320
    dist = np.concatenate([[0], np.cumsum(seg)])
    if dist[-1] < 300:
        return None
    at = np.arange(0, dist[-1], STEP)
    piece = np.clip(np.searchsorted(dist, at, side="right") - 1, 0, len(line) - 1)
    return np.interp(at, dist, lat), np.interp(at, dist, lon), at, np.interp(at, dist, flat) > 0.5, line[piece, 3].astype(int)


def find_climbs(dist, elev):
    """(start, top) index pairs of climbs going up in this direction."""
    out, i, n = [], 0, len(elev)
    while i < n - 1:
        while i < n - 1 and elev[i + 1] <= elev[i]:
            i += 1
        start, top, high = i, i, elev[i]
        k = i + 1
        while k < n:
            if elev[k] > high:
                high, top = elev[k], k
            elif high - elev[k] > max(DROP, min(DROP_MAX, DROP_SHARE * (high - elev[start]))):
                break
            k += 1
        if top > start:
            # Leave out the flat run-up: start where the next 100 m rise at least 2 m.
            while start < top - 5 and elev[start + 5] - elev[start] < 2:
                start += 1
            out.append((start, top))
        i = max(top, i + 1)
    return out


def category(length, avg):
    if avg < 3:
        return None
    score = length * avg
    for limit, cat in CATEGORIES:
        if score >= limit:
            return cat
    # The 30 m elevation model flattens short steep hills (it measures the Koppenberg, 11.6% in
    # reality, at about 6%), so hills count from 5%.
    return "hill" if length >= 300 and avg >= 5 else None


def encode(points):
    """Google encoded polyline, precision 5, of (lat, lon) points."""
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


def simplify(lats, lons, tolerance=5.0):
    """Douglas-Peucker on the 20 m samples, in metres."""
    k = math.cos(math.radians(float(lats.mean())))
    xs, ys = lons * k * 111_320, lats * 111_320
    keep = np.zeros(len(xs), bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(xs) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        dx, dy = xs[b] - xs[a], ys[b] - ys[a]
        norm = math.hypot(dx, dy) or 1
        d = np.abs(dy * (xs[a + 1:b] - xs[a]) - dx * (ys[a + 1:b] - ys[a])) / norm
        m = int(np.argmax(d))
        if d[m] > tolerance:
            keep[a + 1 + m] = True
            stack += [(a, a + 1 + m), (a + 1 + m, b)]
    return [(float(lats[i]), float(lons[i])) for i in np.nonzero(keep)[0]]


def climb_name(names, ref):
    """The road name used most on the climb's upper half, else anywhere on it, else the ref."""
    for part in (names[len(names) // 2:], names):
        named = part[part >= 0]
        if len(named):
            return NAMES[int(np.bincount(named).argmax())]
    return ref


def main():
    dem = Elevation(elevation_dir)
    found, town_list = [], []
    for pbf in extracts:
        print(f"{os.path.basename(pbf)}: reading roads…", flush=True)
        ways = list(roads(pbf))
        town_list += list(places(pbf))
        lines = stitch(chains(ways))
        print(f"  {len(ways)} road pieces in {len(lines)} roads", flush=True)
        for key, line in lines:
            r = resample(line)
            if r is None:
                continue
            lats, lons, at, flat, names = r
            elev = dem.sample(lats, lons)
            if np.isnan(elev).any():
                continue
            if flat.any():
                if flat.all():
                    continue
                elev[flat] = np.interp(at[flat], at[~flat], elev[~flat])  # straight across
            if len(elev) >= SMOOTH:
                elev = np.convolve(np.pad(elev, SMOOTH // 2, mode="edge"), np.ones(SMOOTH) / SMOOTH, mode="valid")
            for reverse in (False, True):
                e, la, lo, nm = (elev[::-1], lats[::-1], lons[::-1], names[::-1]) if reverse else (elev, lats, lons, names)
                for s, t in find_climbs(at, e):
                    length = (t - s) * STEP
                    gain = float(e[t] - e[s])
                    avg = gain / length * 100 if length else 0
                    cat = category(length, avg)
                    if not cat:
                        continue
                    window = 10  # steepest 200 m (100 m is too noisy in the elevation data)
                    steep = max(((e[j + window] - e[j]) / (window * STEP) * 100 for j in range(s, t - window + 1)), default=avg)
                    found.append({"name": climb_name(nm[s:t + 1], key), "cat": cat, "length": round(length), "gain": round(gain),
                                  "avg": round(avg, 1), "max": round(float(steep), 1), "top": round(float(e[t])),
                                  "lats": la[s:t + 1], "lons": lo[s:t + 1]})
        print(f"  {len(found)} climbs so far", flush=True)

    # The same climb twice (dual carriageways, a road and its cycleway): keep the biggest.
    found.sort(key=lambda c: -c["gain"])
    taken, climbs = {}, []
    def cell(lat, lon):
        return (round(lat / 0.0015), round(lon / 0.0025))  # ~150 m
    for c in found:
        a, b = cell(c["lats"][0], c["lons"][0]), cell(c["lats"][-1], c["lons"][-1])
        near = [(a[0] + i, a[1] + j, b[0] + k, b[1] + l) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1) for l in (-1, 0, 1)]
        if any(n in taken for n in near):
            continue
        taken[a + b] = True
        climbs.append(c)

    # Names for unnamed climbs: the nearest place.
    grid = defaultdict(list)
    for name, lon, lat in town_list:
        grid[(int(lat * 10), int(lon * 10))].append((name, lon, lat))
    def nearest_place(lat, lon):
        best, best_d = None, 1e9
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for name, plon, plat in grid[(int(lat * 10) + i, int(lon * 10) + j)]:
                    d = (plat - lat) ** 2 + ((plon - lon) * math.cos(math.radians(lat))) ** 2
                    if d < best_d:
                        best, best_d = name, d
        return best

    out = []
    for c in climbs:
        lat0, lon0, lat1, lon1 = float(c["lats"][0]), float(c["lons"][0]), float(c["lats"][-1]), float(c["lons"][-1])
        key = f"{lat0:.4f},{lon0:.4f},{lat1:.4f},{lon1:.4f}"
        out.append({
            "id": hashlib.sha1(key.encode()).hexdigest()[:10],
            "name": c["name"], "place": nearest_place(lat1, lon1),
            "cat": c["cat"], "length": c["length"], "gain": c["gain"], "avg": c["avg"], "max": c["max"], "top": c["top"],
            "start": [round(lat0, 5), round(lon0, 5)], "end": [round(lat1, 5), round(lon1, 5)],
            "line": encode(simplify(c["lats"], c["lons"])),
        })
    with open(out_path, "w") as f:
        json.dump({"climbs": out}, f, ensure_ascii=False, separators=(",", ":"))
    counts = defaultdict(int)
    for c in out:
        counts[c["cat"]] += 1
    print(f"{len(out)} climbs: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())) + f"; {os.path.getsize(out_path) / 1e6:.1f} MB")


main()
