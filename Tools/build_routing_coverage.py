#!/usr/bin/env python3
"""Writes docs/appstore/routing-coverage.geojson, the Routing App Coverage File for App Store
Connect: the countries route planning covers (RoutingData.countries), as Apple requires it.

    venv/bin/python Tools/build_routing_coverage.py NL BE LU   # needs shapely

Apple's rules: one MultiPolygon, at most 20 polygons, preferably at most 20 points each, closed
rings, no holes, longitude before latitude. The countries' municipalities are merged, widened
until a simplified outline of at most 20 points still contains all of them, and small parts that
lie apart (islands) become their own polygons. The result is checked to cover every municipality.
"""
import json
import os
import sys

from shapely import make_valid
from shapely.geometry import MultiPolygon, Polygon, mapping
from shapely.ops import unary_union

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fmr import read_fmr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "appstore", "routing-coverage.geojson")
countries = sys.argv[1:] or ["NL", "BE", "LU"]
KM = 1 / 111  # degrees, roughly

parts = []
for cc in countries:
    for _, _, polys in read_fmr(os.path.join(ROOT, "AssetPacks", "Regions", f"{cc}-municipalities.fmr")):
        for rings in polys:
            if len(rings[0]) >= 3:
                parts.append(make_valid(Polygon(rings[0])))
area = unary_union(parts)


def polygons(g):
    return [g] if isinstance(g, Polygon) else [p for p in getattr(g, "geoms", []) if isinstance(p, Polygon)]


def simplified(shape, max_points=20):
    """The shape's outline with at most `max_points` points (and no holes)."""
    shell = Polygon(shape.exterior)
    tolerance = 0.2 * KM
    while True:
        # Simplifying can split a shape or drop it entirely; keep the largest part.
        parts = polygons(make_valid(shell.simplify(tolerance, preserve_topology=False)))
        simple = max(parts, key=lambda p: p.area) if parts else shell
        if len(simple.exterior.coords) <= max_points + 1:  # plus the closing point
            return Polygon(simple.exterior)
        tolerance *= 1.25


def cover(pieces, margin_km):
    """Each piece widened by the margin, then simplified; None if the result misses something."""
    shapes = []
    for piece, clip in pieces:
        for part in polygons(piece.buffer(margin_km * KM, join_style="round")):
            shape = simplified(part)
            if clip is not None:  # keep cells apart, so the polygons don't overlap
                shape = max(polygons(make_valid(shape.intersection(clip))), key=lambda p: p.area, default=None)
                if shape is None:
                    continue
                shape = simplified(shape)
            shapes.append(shape)
    covered = unary_union(shapes)
    return shapes if len(shapes) <= 20 and covered.buffer(1e-9).contains(area) else None


best = None
# Whole area at once, or cut into grid cells (more polygons, but each fits more tightly).
for cell in [None, 2.0, 1.5, 1.0]:
    if cell is None:
        pieces = [(area, None)]
    else:
        x0, y0, x1, y1 = area.bounds
        pieces = []
        gx = x0
        while gx < x1:
            gy = y0
            while gy < y1:
                box = Polygon([(gx, gy), (gx + cell, gy), (gx + cell, gy + cell), (gx, gy + cell)])
                piece = area.intersection(box)
                if not piece.is_empty:
                    pieces.append((piece, box))
                gy += cell
            gx += cell
    for margin in [m / 2 for m in range(2, 80)]:
        shapes = cover(pieces, margin)
        if shapes:
            size = unary_union(shapes).area
            print(f"  cells {cell or 'none'}: {len(shapes)} polygons, margin {margin} km, {size / area.area:.2f}× the countries")
            if best is None or size < best[0]:
                best = (size, shapes, margin, cell)
            break
if best is None:
    sys.exit("no outline of at most 20 polygons contains the area")
size, shapes, margin, cell = best
covered = unary_union(shapes)
geo = MultiPolygon([Polygon([(round(x, 4), round(y, 4)) for x, y in p.exterior.coords]) for p in shapes])
geo = MultiPolygon([Polygon(list(p.exterior.coords)[::-1]) if not p.exterior.is_ccw else p for p in geo.geoms])
with open(OUT, "w") as f:
    json.dump(mapping(geo), f, indent=1)
print(f"{OUT}: {len(shapes)} polygons, {max(len(p.exterior.coords) for p in shapes)} points at most, "
      f"margin {margin} km, area {covered.area / area.area:.2f}× the countries (cells: {cell or 'none'})")
