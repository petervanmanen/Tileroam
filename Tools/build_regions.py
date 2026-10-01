#!/usr/bin/env python3
"""Builds Tileroam's bundled region files (municipalities and postcodes per country).

Usage:
    python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
    venv/bin/python Tools/build_regions.py <raw-download-dir> Tileroam/Resources/Regions

Output per layer: <CC>-<kind>.fmr, a raw-deflate compressed binary file:
    "FMR1", u32 area count, then per area:
        u8 code length + UTF-8 code ("DE:01001000"), u16 name length + UTF-8 name,
        varint polygon count, per polygon: varint ring count, per ring: varint point count,
        followed by zigzag-varint deltas of (lat, lon) * 1e5 (deltas run across the whole file).
Plus regions.json with counts, bounding boxes, sources and licenses.
"""
import ast
import glob
import json
import os
import sqlite3
import struct
import sys
import zlib
from collections import defaultdict

from pyproj import Transformer
from shapely import make_valid, wkb
from shapely.geometry import MultiPolygon, Polygon, shape
from shapely.geometry import LineString
from shapely.ops import linemerge, polygonize, transform, unary_union

RAW, OUT = sys.argv[1], sys.argv[2]
NL_SOURCE = os.path.join(os.path.dirname(__file__), "sources")


def first(v):
    """Opendatasoft exports some fields as lists (sometimes as their string form)."""
    if isinstance(v, str) and v.startswith("["):
        try:
            v = ast.literal_eval(v)
        except (ValueError, SyntaxError):
            return v
    if isinstance(v, list):
        return v[0] if v else None
    return v


def features(path):
    with open(path) as f:
        return json.load(f)["features"]


def geometry(f, reproject=None):
    g = shape(f["geometry"])
    if g.has_z:
        g = transform(lambda x, y, z=None: (x, y), g)
    if reproject:
        g = transform(reproject, g)
    return g


def polygons(g, repair=True):
    """All polygons in a geometry, including those nested in collections (make_valid output)."""
    if repair:
        g = make_valid(g)
    if isinstance(g, Polygon):
        return [g] if not g.is_empty else []
    return [p for part in getattr(g, "geoms", []) for p in polygons(part, repair=False)]


def simplified(g, meters):
    tolerance = meters / 111_000
    parts = []
    for p in polygons(g.simplify(tolerance, preserve_topology=True)):
        # Drop slivers and tiny islands (< ~50 m × 50 m).
        if p.area < (50 / 111_000) ** 2:
            continue
        parts.append(p)
    if not parts:  # keep at least the largest part
        parts = sorted(polygons(g), key=lambda p: p.area)[-1:]
    return parts


def varint(n, out):
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def zigzag(n):
    return (n << 1) ^ (n >> 63)


def write_layer(country, kind, areas, meters, source, license_, attribution):
    """areas: list of (code, name, shapely geometry)."""
    body = bytearray(b"FMR1")
    body += struct.pack("<I", len(areas))
    last = [0, 0]
    minx = miny = 1e9
    maxx = maxy = -1e9
    points = 0
    areas = [a for a in areas if simplified(a[2], meters)]
    for code, name, g in sorted(areas, key=lambda a: a[0]):
        code_b = f"{country}:{code}".encode()
        name_b = str(name).encode()
        body.append(len(code_b))
        body += code_b
        body += struct.pack("<H", len(name_b))
        body += name_b
        parts = simplified(g, meters)
        varint(len(parts), body)
        for p in parts:
            rings = [p.exterior] + list(p.interiors)
            varint(len(rings), body)
            for ring in rings:
                coords = list(ring.coords)[:-1]  # drop closing point
                varint(len(coords), body)
                for x, y in coords:
                    lat, lon = round(y * 1e5), round(x * 1e5)
                    varint(zigzag(lat - last[0]), body)
                    varint(zigzag(lon - last[1]), body)
                    last = [lat, lon]
                    minx, maxx = min(minx, x), max(maxx, x)
                    miny, maxy = min(miny, y), max(maxy, y)
                    points += 1
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = compressor.compress(bytes(body)) + compressor.flush()
    name = f"{country}-{kind}.fmr"
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(data)
    print(f"{name:28} {len(areas):6} areas {points:9} points {len(data) / 1e6:6.2f} MB")
    return {
        "file": name, "count": len(areas), "bbox": [round(minx, 4), round(miny, 4), round(maxx, 4), round(maxy, 4)],
        "source": source, "license": license_, "attribution": attribution,
    }


def dissolve(items):
    """items: iterable of (code, name, geometry) -> one entry per code."""
    groups = defaultdict(list)
    names = {}
    for code, name, g in items:
        groups[code].append(g)
        names.setdefault(code, name)
    return [(c, names[c], gs[0] if len(gs) == 1 else unary_union([make_valid(x) for x in gs])) for c, gs in groups.items()]


def raw(name):
    return os.path.join(RAW, name)


def ods(name):
    return features(raw(f"georef-{name}.geojson"))


os.makedirs(OUT, exist_ok=True)
manifest = defaultdict(dict)
M, P = "municipalities", "postcodes"

# Netherlands (CBS / PDOK)
manifest["NL"][M] = write_layer("NL", M, [(f["properties"]["code"], f["properties"]["name"], geometry(f))
                                          for f in features(os.path.join(NL_SOURCE, "gemeenten.geojson"))],
                                25, "CBS / PDOK gebiedsindelingen 2025", "CC BY 4.0", "© CBS, Kadaster")
manifest["NL"][P] = write_layer("NL", P, [(f["properties"]["code"], f["properties"]["code"], geometry(f))
                                          for f in features(os.path.join(NL_SOURCE, "postcodes.geojson"))],
                                20, "CBS postcode4 2024 via PDOK", "CC BY 4.0", "© CBS, Kadaster")

# Belgium (NGI-IGN via Opendatasoft)
def be_name(p, prefix):
    lang = (first(p.get(f"{prefix}_off_language")) or "NL").lower()
    return first(p.get(f"{prefix}_name_{lang}")) or first(p.get(f"{prefix}_name_nl")) or first(p.get(f"{prefix}_name_fr"))

manifest["BE"][M] = write_layer("BE", M, [(first(f["properties"]["mun_code"]), be_name(f["properties"], "mun"), geometry(f))
                                          for f in ods("belgium-municipality")],
                                25, "NGI-IGN via Opendatasoft (georef-belgium-municipality)", "NGI open data licence", "© NGI-IGN")
be_pc = [f for f in ods("belgium-postal-codes") if str(f["properties"].get("special_code")) == "0"]
manifest["BE"][P] = write_layer("BE", P, dissolve((f["properties"]["postcode"], f["properties"]["postcode"], geometry(f)) for f in be_pc),
                                20, "bpost / NGI-IGN via Opendatasoft (georef-belgium-postal-codes)", "custom (see source)", "© bpost, NGI-IGN")

# Germany (BKG; postcodes from OpenStreetMap)
manifest["DE"][M] = write_layer("DE", M, [(first(f["properties"]["gem_code"]),
                                           first(f["properties"].get("gem_name_short")) or first(f["properties"]["gem_name"]), geometry(f))
                                          for f in ods("germany-gemeinde")],
                                25, "BKG VG250 via Opendatasoft (georef-germany-gemeinde)", "dl-de/by-2-0", "© GeoBasis-DE / BKG")
de_pc = []
for f in features(raw("de-plz.geojson")):
    p = f["properties"]
    de_pc.append((p["plz"], (p.get("note") or p["plz"]).split(" ", 1)[-1], geometry(f)))
manifest["DE"][P] = write_layer("DE", P, dissolve(de_pc), 20, "OpenStreetMap (tdudek/de-plz-geojson)", "ODbL",
                                "© OpenStreetMap contributors")

# France (IGN / INSEE; postcode zones from adresse.data.gouv.fr)
fr_path = raw("georef-france-commune.geojson")
manifest["FR"][M] = write_layer("FR", M, [(first(f["properties"]["com_code"]), first(f["properties"]["com_name"]), geometry(f))
                                          for f in features(fr_path)],
                                25, "IGN Admin Express / INSEE via Opendatasoft (georef-france-commune)", "Licence Ouverte 2.0",
                                "© IGN, INSEE")
manifest["FR"][P] = write_layer("FR", P, dissolve((f["properties"]["codePostal"], f["properties"]["codePostal"], geometry(f))
                                                  for f in features(raw("fr-postcodes.geojson"))),
                                20, "adresse.data.gouv.fr – contours calculés des zones codes postaux", "Licence Ouverte 2.0",
                                "© Etalab, BAN")

# Spain (IGN / CNIG)
manifest["ES"][M] = write_layer("ES", M, [(first(f["properties"]["mun_code"]), first(f["properties"]["mun_name"]), geometry(f))
                                          for f in ods("spain-municipio")],
                                25, "IGN via Opendatasoft (georef-spain-municipio)", "CC BY 4.0", "© IGN España")
es_pc = []
for path in sorted(glob.glob(raw("es/*.geojson"))):
    for f in features(path):
        code = f["properties"]["COD_POSTAL"]
        es_pc.append((code, code, geometry(f)))
manifest["ES"][P] = write_layer("ES", P, dissolve(es_pc), 20, "CNIG códigos postales (inigoflores/ds-codigos-postales)",
                                "CC BY 4.0", "© CNIG, Correos")

# Switzerland (swisstopo)
manifest["CH"][M] = write_layer("CH", M, [(first(f["properties"]["gem_code"]), first(f["properties"]["gem_name"]), geometry(f))
                                          for f in ods("switzerland-gemeinde")],
                                25, "swisstopo swissBOUNDARIES3D via Opendatasoft", "opendata.swiss BY", "© swisstopo")
ch_pc = []
for f in ods("switzerland-postleitzahl"):
    p = f["properties"]
    names = p.get("gem_name")
    names = ast.literal_eval(names) if isinstance(names, str) and names.startswith("[") else names
    ch_pc.append((first(p["plz_code"]), ", ".join(names) if isinstance(names, list) else (names or first(p["plz_code"])), geometry(f)))
manifest["CH"][P] = write_layer("CH", P, dissolve(ch_pc), 20, "swisstopo Amtliches Ortschaftenverzeichnis via Opendatasoft",
                                "opendata.swiss (see source)", "© swisstopo")

# Austria (Statistik Austria; no open postcode polygons exist)
def at_municipality(f):
    code, name = f["properties"]["g_id"], f["properties"]["g_name"]
    # Statistik Austria lists Vienna's 23 districts (9xxxx) separately; Vienna is one municipality.
    return ("90001", "Wien", geometry(f)) if code.startswith("9") else (code, name, geometry(f))

manifest["AT"][M] = write_layer("AT", M, dissolve(at_municipality(f) for f in features(raw("at-gemeinden.geojson"))),
                                25, "Statistik Austria Gemeinden 2025-01-01", "CC BY 4.0", "© Statistik Austria")

# Luxembourg (ACT; no open postcode polygons exist)
manifest["LU"][M] = write_layer("LU", M, [(f["properties"]["LAU2"], f["properties"]["COMMUNE"], geometry(f))
                                          for f in features(raw("lu-communes.geojson"))],
                                25, "data.public.lu – limites administratives", "CC0", "© ACT Luxembourg")

# United Kingdom (ONS; postcode districts from GeoLytix/ONS-based polygons)
manifest["GB"][M] = write_layer("GB", M, [(first(f["properties"]["lad_code"]), first(f["properties"]["lad_name"]), geometry(f))
                                          for f in ods("united-kingdom-local-authority-district")],
                                25, "ONS local authority districts via Opendatasoft", "OGL v3.0",
                                "Contains OS data © Crown copyright and database right; © ONS")
con = sqlite3.connect(raw("gb-postcodes.gpkg"))
layers = [r[0] for r in con.execute("select table_name from gpkg_contents where data_type='features'")]
district_layer = next(l for l in layers if "district" in l.lower())
srs_id = con.execute("select srs_id from gpkg_geometry_columns where table_name=?", (district_layer,)).fetchone()[0]
# srs_id is GeoPackage-internal; the EPSG code is in gpkg_spatial_ref_sys.
org, srs = con.execute("select organization, organization_coordsys_id from gpkg_spatial_ref_sys where srs_id=?", (srs_id,)).fetchone()
if org.upper() != "EPSG":
    srs = 27700  # this file's "Transverse Mercator" without EPSG code is the British National Grid
geom_col = con.execute("select column_name from gpkg_geometry_columns where table_name=?", (district_layer,)).fetchone()[0]
columns = [r[1] for r in con.execute(f"pragma table_info('{district_layer}')")]
name_col = next(c for c in columns if c.lower() in ("name", "district", "postcode", "pc_district", "label"))
to_wgs = Transformer.from_crs(f"EPSG:{srs}", "EPSG:4326", always_xy=True).transform if srs != 4326 else None
gb_pc = []
for code, blob in con.execute(f"select {name_col}, {geom_col} from '{district_layer}'"):
    flags = blob[3]
    envelope = [0, 32, 48, 48, 64][(flags >> 1) & 0x07]
    g = wkb.loads(bytes(blob[8 + envelope:]))
    gb_pc.append((code, code, transform(to_wgs, g) if to_wgs else g))
manifest["GB"][P] = write_layer("GB", P, dissolve(gb_pc), 20, "GB postcode districts (figshare 6050105, from ONS/OS open data)",
                                "CC BY 4.0", "Contains OS data © Crown copyright; Royal Mail data © Royal Mail copyright; ONS")

# Ireland (Tailte Éireann; Eircode areas have no open boundaries)
itm = Transformer.from_crs("EPSG:2157", "EPSG:4326", always_xy=True).transform
ie = [(f["properties"]["BDY_ID"], f["properties"]["ENG_NAME_VALUE"].title().replace("And", "and"), geometry(f, itm))
      for f in features(raw("ie-la.geojson"))]
manifest["IE"][M] = write_layer("IE", M, dissolve(ie), 25, "Tailte Éireann – Local Authorities 2024", "CC BY 4.0", "© Tailte Éireann")

# Portugal (DGT; postcodes are not open data)
manifest["PT"][M] = write_layer("PT", M, [(first(f["properties"]["con_code"]), first(f["properties"]["con_name"]), geometry(f))
                                          for f in ods("portugal-concelho")],
                                25, "DGT CAOP via Opendatasoft (georef-portugal-concelho)", "Public domain", "© Direção-Geral do Território")

# Italy (ISTAT; CAP boundaries are not open data)
manifest["IT"][M] = write_layer("IT", M, [(first(f["properties"]["com_code"]), first(f["properties"]["com_name"]), geometry(f))
                                          for f in ods("italy-comune")],
                                25, "ISTAT via Opendatasoft (georef-italy-comune)", "CC BY 3.0", "© ISTAT")


def geoboundaries(country, path, source, license_, attribution, code_prefix=""):
    items = []
    for i, f in enumerate(features(raw(path))):
        p = f["properties"]
        code = p.get("shapeISO") or f"{code_prefix}{i + 1:03d}"
        items.append((code if code != country else f"{country}1", p["shapeName"], geometry(f)))
    return write_layer(country, M, dissolve(items), 25, source, license_, attribution)


# Microstates (geoBoundaries / OpenStreetMap)
manifest["LI"][M] = geoboundaries("LI", "gb-LIE.geojson", "geoBoundaries LIE ADM1 (OpenStreetMap)", "ODbL", "© OpenStreetMap contributors, geoBoundaries")
manifest["MC"][M] = geoboundaries("MC", "gb-MCO.geojson", "geoBoundaries MCO ADM0 (OpenStreetMap)", "ODbL", "© OpenStreetMap contributors, geoBoundaries")
manifest["AD"][M] = geoboundaries("AD", "gb-AND.geojson", "geoBoundaries AND ADM1", "Public domain", "geoBoundaries, Wikimedia Commons")
manifest["SM"][M] = geoboundaries("SM", "gb-SMR.geojson", "geoBoundaries SMR ADM1 (OpenStreetMap)", "ODbL", "© OpenStreetMap contributors, geoBoundaries")
manifest["VA"][M] = geoboundaries("VA", "gb-VAT.geojson", "geoBoundaries VAT ADM0", "geoBoundaries (see source)", "geoBoundaries")

# Nordics
manifest["DK"][M] = write_layer("DK", M, dissolve((f["properties"]["KOMKODE"], f["properties"]["KOMNAVN"], geometry(f))
                                                  for f in features(raw("dk-kommuner.geojson"))),
                                25, "DAGI kommuner (Neogeografen/dagi)", "Danish free data licence", "© SDFI / Klimadatastyrelsen (DAGI)")
manifest["DK"][P] = write_layer("DK", P, dissolve((f["properties"]["POSTNR_TXT"], f["properties"]["POSTBYNAVN"], geometry(f))
                                                  for f in features(raw("dk-postnumre.geojson"))),
                                20, "DAGI postnumre (Neogeografen/dagi)", "Danish free data licence", "© SDFI / Klimadatastyrelsen (DAGI)")
def osm_relations(path, code_tag="ref"):
    """Overpass `out geom` relations -> (code, name, polygon) by polygonizing outer and inner ways."""
    items = []
    for rel in json.load(open(path))["elements"]:
        rings = {"outer": [], "inner": []}
        for m in rel.get("members", []):
            if m.get("type") == "way" and m.get("geometry"):
                role = "inner" if m.get("role") == "inner" else "outer"
                rings[role].append(LineString([(p["lon"], p["lat"]) for p in m["geometry"]]))
        outer = unary_union(list(polygonize(linemerge(rings["outer"])))) if rings["outer"] else None
        if outer is None or outer.is_empty:
            continue
        if rings["inner"]:
            holes = unary_union(list(polygonize(linemerge(rings["inner"]))))
            if not holes.is_empty:
                outer = outer.difference(holes)
        tags = rel["tags"]
        name = tags.get("name", "").removesuffix(" kommun")
        items.append((tags.get(code_tag) or str(rel["id"]), name, outer))
    return items


se_names = {f["properties"]["id"]: f["properties"]["kom_namn"] for f in features(raw("se-names.geojson"))}
se = [(code, se_names.get(code, name), g) for code, name, g in osm_relations(raw("se-osm.json"))]
manifest["SE"][M] = write_layer("SE", M, dissolve(se), 25,
                                "OpenStreetMap (admin_level 7, via Overpass)", "ODbL", "© OpenStreetMap contributors")
manifest["NO"][M] = write_layer("NO", M, [(f["properties"]["kommunenummer"], f["properties"]["kommunenavn"], geometry(f))
                                          for f in features(raw("no-kommuner.geojson"))],
                                25, "Kartverket kommuner 2024 (robhop/fylker-og-kommuner)", "CC BY 4.0", "© Kartverket")
manifest["FI"][M] = write_layer("FI", M, [(f["properties"]["kunta"], f["properties"]["nimi"], geometry(f))
                                          for f in features(raw("fi-kunnat.geojson"))],
                                25, "Statistics Finland kunta1000k_2025", "CC BY 4.0", "© Tilastokeskus / Statistics Finland")
manifest["FI"][P] = write_layer("FI", P, [(f["properties"]["posti_alue"], f["properties"]["nimi"], geometry(f))
                                          for f in features(raw("fi-postinumerot.geojson"))],
                                20, "Statistics Finland postal code areas (Paavo) 2025", "CC BY 4.0", "© Tilastokeskus / Statistics Finland")
manifest["IS"][M] = write_layer("IS", M, [(f["properties"]["nrsveitarfelags"], f["properties"]["sveitarfelag"], geometry(f))
                                          for f in features(raw("is-sveitarfelog.geojson"))],
                                25, "Náttúrufræðistofnun / LMI IS 50V sveitarfélög", "CC BY 4.0", "© Náttúrufræðistofnun Íslands")

with open(os.path.join(OUT, "regions.json"), "w") as f:
    json.dump(manifest, f, indent=1, ensure_ascii=False)
print("total", round(sum(os.path.getsize(os.path.join(OUT, x)) for x in os.listdir(OUT)) / 1e6, 1), "MB")
