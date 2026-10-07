#!/usr/bin/env python3
"""Checks Tileroam challenge files against the format in challenges/README.md, the same rules the
app uses (Tileroam/Challenges/CustomChallenge.swift).

    Tools/check_challenge.py challenges/*.geojson

Prints each file's challenge and what is wrong; exits with 1 when a file can't be used. Features
the app would skip (no id or name, wrong geometry, a repeated id) are listed as warnings.
"""
import json
import re
import sys
import unicodedata

FORMAT = 1
ID = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")
DIFFICULTIES = {"easy", "moderate", "hard", "very-hard"}
SPORTS = {"Cycling", "E-biking", "Running", "Walking", "Hiking", "Swimming", "Skiing", "Snowboarding",
          "Cross-country skiing", "Rowing", "Inline skating", "Fitness"}
RANGES = {"radius": (10, 5000), "coverage": (0.1, 1), "spacing": (10, 1000)}


def is_emoji(s):
    # One character as the user sees it; a rough check (the app's is exact).
    return isinstance(s, str) and 0 < len(s) <= 8 and not any(c.isalnum() and ord(c) < 0x2000 for c in s) \
        and all(unicodedata.category(c) in ("So", "Sk", "Mn", "Cf", "Me") or 0x1F1E6 <= ord(c) <= 0x1F1FF for c in s)


def position(p):
    return isinstance(p, list) and len(p) >= 2 and all(isinstance(v, (int, float)) for v in p[:2]) \
        and -180 <= p[0] <= 180 and -90 <= p[1] <= 90


def line(c):
    return isinstance(c, list) and len(c) >= 2 and all(position(p) for p in c)


def check(path):
    errors, warnings = [], []
    try:
        with open(path, encoding="utf-8") as f:
            root = json.load(f)
    except (OSError, ValueError) as e:
        return [f"not valid JSON: {e}"], [], None
    if not isinstance(root, dict) or root.get("type") != "FeatureCollection" or not isinstance(root.get("features"), list):
        return ["not a GeoJSON FeatureCollection"], [], None
    h = root.get("tileroam")
    if not isinstance(h, dict):
        return ['no "tileroam" block'], [], None
    if not isinstance(h.get("format"), int):
        errors.append('"format" is missing')
    elif h["format"] > FORMAT:
        errors.append(f'format {h["format"]} needs a newer version of Tileroam')
    if not isinstance(h.get("name"), str) or not h["name"].strip():
        errors.append('"name" is missing')
    kind = h.get("kind")
    if kind not in ("locations", "routes"):
        errors.append('"kind" must be "locations" or "routes"')
    if "id" in h and not (isinstance(h["id"], str) and ID.fullmatch(h["id"])):
        errors.append('"id": lower-case letters, digits and hyphens, at most 64')
    complete = h.get("complete", "cover")
    if "complete" in h and (kind != "routes" or complete not in ("cover", "cross")):
        errors.append('"complete" is "cover" or "cross", for routes only')
    for key, (lo, hi) in RANGES.items():
        if key in h and not (isinstance(h[key], (int, float)) and lo <= h[key] <= hi):
            errors.append(f'"{key}" must be a number from {lo} to {hi}')
    if "icon" in h and not is_emoji(h["icon"]):
        errors.append('"icon" must be one emoji')
    if "sports" in h:
        if not (isinstance(h["sports"], list) and h["sports"] and all(isinstance(s, str) for s in h["sports"])):
            errors.append('"sports" must be a list of sport names')
        else:
            unknown = sorted(set(h["sports"]) - SPORTS)
            if unknown:
                warnings.append(f'unknown sports (no activity will match): {", ".join(unknown)}')
    if errors:
        return errors, warnings, None

    seen, usable = set(), 0
    for i, f in enumerate(root["features"]):
        where = f"feature {i + 1}"
        if not isinstance(f, dict) or f.get("type") != "Feature" or not isinstance(f.get("geometry"), dict):
            warnings.append(f"{where}: not a Feature with a geometry")
            continue
        props = f.get("properties") or {}
        fid = f.get("id", props.get("id"))
        if isinstance(fid, (int, float)) and not isinstance(fid, bool):
            fid = str(fid) if not isinstance(fid, float) or not fid.is_integer() else str(int(fid))
        if not isinstance(fid, str) or not fid:
            warnings.append(f"{where}: no id")
            continue
        where = f'feature "{fid}"'
        if fid in seen:
            warnings.append(f"{where}: the id is used before")
            continue
        if not isinstance(props.get("name"), str) or not props["name"].strip():
            warnings.append(f"{where}: no name")
            continue
        g = f["geometry"]
        t, c = g.get("type"), g.get("coordinates")
        if kind == "locations":
            ok = t == "Point" and position(c)
        elif complete == "cross":
            ok = t == "LineString" and line(c)
        else:
            ok = (t == "LineString" and line(c)) or (t == "MultiLineString" and isinstance(c, list) and any(line(p) for p in c)
                                                    and all(isinstance(p, list) and all(position(q) for q in p) for p in c))
        if not ok:
            need = "a Point" if kind == "locations" else "a LineString" if complete == "cross" else "a LineString or MultiLineString"
            warnings.append(f"{where}: needs {need} with valid coordinates")
            continue
        if "icon" in props and not is_emoji(props["icon"]):
            warnings.append(f'{where}: "icon" isn\'t one emoji (the challenge\'s is used)')
        if "difficulty" in props and props["difficulty"] not in DIFFICULTIES:
            warnings.append(f'{where}: "difficulty" is one of {", ".join(sorted(DIFFICULTIES))}')
        if "url" in props and not (isinstance(props["url"], str) and re.match(r"https?://", props["url"])):
            warnings.append(f'{where}: "url" must start with https:// or http://')
        seen.add(fid)
        usable += 1
    if not usable:
        errors.append("no usable places or routes")
    return errors, warnings, (h, usable)


def main(paths):
    if not paths:
        print(__doc__)
        return 2
    failed = False
    for path in paths:
        errors, warnings, ok = check(path)
        if ok:
            h, usable = ok
            print(f'{path}: "{h["name"]}", {usable} {"places" if h["kind"] == "locations" else "routes"}')
        else:
            print(f"{path}: can't be used")
        for e in errors:
            print(f"  error: {e}")
        for w in warnings[:20]:
            print(f"  warning: {w}")
        if len(warnings) > 20:
            print(f"  … and {len(warnings) - 20} more warnings")
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
