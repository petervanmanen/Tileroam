#!/usr/bin/env python3
"""Converts a boscafé list in the editor's format ([{"title": "Name, Place", "icon": "🌲",
"lat": …, "lng": …}]) into AssetPacks/Boscafes/boscafes.json, the app's format (id, name, place,
emoji, lat, lon). Ids are made from name and place, so a café keeps its id (and its visits)
as long as its title stays the same. Then upload with Tools/upload_boscafes_r2.sh.

    Tools/import_boscafes.py ../temp/boscafe/boscafes.json
"""
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "AssetPacks", "Boscafes", "boscafes.json")

source = json.load(open(sys.argv[1]))
previous = {c["id"] for c in json.load(open(OUT))} if os.path.exists(OUT) else set()
cafes, seen = [], set()
for c in source:
    name, place = c["title"].rsplit(", ", 1)
    slug = unicodedata.normalize("NFKD", f"{name} {place}").encode("ascii", "ignore").decode().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", slug).strip("-")
    if slug in seen:
        sys.exit(f"Two boscafés with the same name and place: {c['title']}")
    seen.add(slug)
    cafes.append({"id": slug, "name": name, "place": place, "emoji": c["icon"], "lat": c["lat"], "lon": c["lng"]})
cafes.sort(key=lambda c: c["id"])
json.dump(cafes, open(OUT, "w"), ensure_ascii=False, indent=1)
added, removed = seen - previous, previous - seen
print(f"{len(cafes)} boscafés ({len(added)} added, {len(removed)} removed): {OUT}")
if removed:
    print("Removed (their visits no longer count):", ", ".join(sorted(removed)))
