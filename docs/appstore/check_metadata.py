#!/usr/bin/env python3
"""Checks the App Store metadata files against App Store Connect's character limits."""
import re, sys, pathlib

LIMITS = {"name": 30, "subtitle": 30, "promotional": 170, "description": 4000, "keywords": 100,
          "naam": 30, "subtitel": 30, "promotietekst": 170, "beschrijving": 4000, "trefwoorden": 100}
ok = True
for path in sorted(pathlib.Path(__file__).parent.glob("metadata-*.md")):
    sections = re.split(r"^## ", path.read_text(), flags=re.M)[1:]
    for section in sections:
        title, _, body = section.partition("\n")
        key = title.split()[0].lower()
        if key not in LIMITS:
            continue
        text = body.strip()
        n = len(text)
        status = "ok" if n <= LIMITS[key] else "TOO LONG"
        ok &= n <= LIMITS[key]
        if key in ("keywords", "trefwoorden") and ", " in text:
            status += " (remove spaces after commas)"
        print(f"{path.name:18} {title:28} {n:5}/{LIMITS[key]:<5} {status}")
sys.exit(0 if ok else 1)
