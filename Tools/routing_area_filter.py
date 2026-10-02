"""Which 1° areas route planning can need: those within reach of the covered countries.

Route planning only starts and stops inside the covered countries, and downloads the areas within
60 km of a plan (RoutingData.packs, after a retry). Anything farther away, such as the ferry routes
to Scandinavia and Britain in Germany's OpenStreetMap extract, is never used, so it isn't packed.
The country outlines are the ones the app bundles (Tileroam/Resources/countries.fmr).
"""
import math
import os

from fmr import read_fmr

MARGIN_KM = 70  # RoutingData's 60 km retry margin, plus some room
OUTLINES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "Tileroam", "Resources", "countries.fmr")


def load_outlines(countries):
    """Outer rings (lists of (lon, lat)) of the given countries' outlines."""
    rings = []
    for code, _, polygons in read_fmr(OUTLINES):
        if code.split(":")[0] in countries:
            rings += [polygon[0] for polygon in polygons]
    return rings


def _inside(lon, lat, ring):
    inside = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        if (y1 > lat) != (y2 > lat) and lon < x1 + (lat - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside


def needed(lat, lon, size, rings):
    """Whether the size° × size° cell at (lat, lon) lies within MARGIN_KM of an outline."""
    dlat = MARGIN_KM / 111.0
    dlon = MARGIN_KM / (111.0 * max(math.cos(math.radians(lat + size / 2)), 0.2))
    s, n, w, e = lat - dlat, lat + size + dlat, lon - dlon, lon + size + dlon
    for ring in rings:
        if any(s <= y <= n and w <= x <= e for x, y in ring):
            return True
        if _inside(lon + size / 2, lat + size / 2, ring):
            return True
    return False
