#!/usr/bin/env python3
"""Fetch all Klompenpaden from klompenpaden.nl / Jimbo API and write GPX files for paths > 5 km."""
import csv, json, os, re, time, urllib.request
from xml.sax.saxutils import escape

SITE = "https://www.klompenpaden.nl"
API = "https://api.jimbogo.com/api/jimbo/v1.1/published-content-objects/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gpx")
MIN_LEN = 5000
USAGE_ORDER = ["mainRoute", "shorteningRoute", "extensionRoute", "alternativeRoute", "connectionRoute"]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode("utf-8")
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def list_paths():
    found = {}
    page = 1
    while True:
        html = get(f"{SITE}/klompenpaden?page={page}")
        new = 0
        for slug, uid in re.findall(r'/klompenpaden/([^/"\\]+)/([0-9a-f-]{36})', html):
            if uid not in found:
                found[uid] = slug
                new += 1
        if new == 0:
            break
        page += 1
    return found


def safe(name):
    return re.sub(r"[^\w\-]+", "_", name).strip("_")


def to_gpx(d):
    name = d["name"]
    parts = sorted(d.get("route", {}).get("routeParts", []),
                   key=lambda p: USAGE_ORDER.index(p.get("usage")) if p.get("usage") in USAGE_ORDER else 99)
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<gpx version="1.1" creator="klompenpaden.nl via Jimbo API" xmlns="http://www.topografix.com/GPX/1/1">',
           f'<metadata><name>{escape(name)}</name><desc>{escape(d.get("description") or "")}</desc>'
           f'<link href="{SITE}/klompenpaden/{safe(name)}/{d["id"]}"><text>klompenpaden.nl</text></link></metadata>']
    loc = d.get("location")
    if loc:
        sp = d.get("contentAttributes", {}).get("startingPoints") or "Start"
        out.append(f'<wpt lat="{loc["lat"]}" lon="{loc["lng"]}"><name>Start {escape(sp)}</name></wpt>')
    for p in parts:
        pts = p.get("points") or []
        if len(pts) < 4:
            continue
        out.append(f'<trk><name>{escape(name)} - {escape(p.get("name") or p.get("usage") or "")}</name>'
                   f'<type>{escape(p.get("usage") or "")}</type><trkseg>')
        out += [f'<trkpt lat="{pts[i]:.7f}" lon="{pts[i+1]:.7f}"/>' for i in range(0, len(pts) - 1, 2)]
        out.append("</trkseg></trk>")
    out.append("</gpx>")
    return "\n".join(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    paths = list_paths()
    print(f"{len(paths)} klompenpaden found")
    rows = []
    for uid, slug in sorted(paths.items(), key=lambda x: x[1].lower()):
        d = json.loads(get(API + uid))
        attrs = d.get("contentAttributes", {})
        lengths = sorted(attrs.get("trailLengths") or [])
        parts = d.get("route", {}).get("routeParts", [])
        main_len = sum(p.get("length", 0) for p in parts if p.get("usage") == "mainRoute")
        longest = max(lengths) if lengths else main_len
        row = {"name": d["name"], "start": attrs.get("startingPoints") or "",
               "lengths_km": ", ".join(f"{l/1000:g}" for l in lengths),
               "longest_km": round(longest / 1000, 1),
               "lat": d.get("location", {}).get("lat"), "lon": d.get("location", {}).get("lng"),
               "url": f"{SITE}/klompenpaden/{slug}/{uid}", "gpx": ""}
        if longest > MIN_LEN:
            fn = safe(d["name"]) + ".gpx"
            with open(os.path.join(OUT, fn), "w", encoding="utf-8") as f:
                f.write(to_gpx(d))
            row["gpx"] = "gpx/" + fn
        rows.append(row)
        print(f'{row["name"]:40} {row["lengths_km"]:25} {"GPX" if row["gpx"] else "skip"}')
    base = os.path.dirname(OUT)
    with open(os.path.join(base, "klompenpaden_all.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    long_rows = [r for r in rows if r["gpx"]]
    with open(os.path.join(base, "klompenpaden_langer_dan_5km.md"), "w", encoding="utf-8") as f:
        f.write(f"# Klompenpaden langer dan 5 km ({len(long_rows)})\n\n")
        f.write("Bron: klompenpaden.nl (Jimbo API). Lengte = langste variant > 5 km.\n\n")
        f.write("| # | Naam | Startpunt | Lengtes (km) | GPX |\n|---|---|---|---|---|\n")
        for i, r in enumerate(long_rows, 1):
            f.write(f'| {i} | [{r["name"]}]({r["url"]}) | {r["start"]} | {r["lengths_km"]} | [{r["gpx"][4:]}]({r["gpx"]}) |\n')
    print(f"\n{len(long_rows)} paths > 5 km, GPX written to {OUT}")


if __name__ == "__main__":
    main()
