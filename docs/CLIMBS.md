# Climbs

Tileroam knows the climbs on the roads of the route planning countries: which ones the user has climbed, which there are, and it can plan routes over them.

Climbs aren't a thing in OpenStreetMap, and commercial climb lists can't be used, so Tileroam **finds them itself** from an open elevation model along OpenStreetMap's roads. The result for the Netherlands, Belgium, Luxembourg and Germany (October 2026): 77,020 climbs in 76 areas of 1° × 1°, 6.1 MB compressed.

## What counts as a climb

| Category | Rule |
|---|---|
| HC, Cat 1 – Cat 4 | Like Strava: average at least 3%, and length (m) × average (%) at least 80,000 (HC), 64,000 (1), 32,000 (2), 16,000 (3) or 8,000 (4) |
| Hill | Not categorised, but at least 300 m at 5% or more: the short steep hills of Limburg, the Ardennes and the Flemish Ardennes |

A climb runs from a low point up to the highest point reached before the road drops more than 10 m, without the flat run-up. The steepest gradient is measured over 200 m.

**Known limit:** the elevation model has a resolution of about 30 m, which flattens short steep hills. The Koppenberg (600 m at 11.6% in reality) comes out at about 6%; longer climbs come out close to their real numbers. The app says so under Statistics → Climbs.

Examples it finds: Cauberg (720 m, 7.9%), Keutenberg (560 m, 9.8%), Mur de Huy / Chemin des Chapelles (680 m, 12.7%), Paterberg (360 m, 11.6%), the Bourscheid climbs in Luxembourg (3.3 km, 7.6%).

## Building

```bash
Tools/download_elevation.sh 41 55 -5 17     # once: elevation tiles for the area (about 9 GB)
Tools/build_climbs.sh west netherlands belgium luxembourg germany
```

1. **Elevation** (`Tools/download_elevation.sh`): 1° × 1° tiles in Valhalla's "skadi" layout (`N52/N52E005.hgt`) from the [Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) open dataset, into `AssetPacks/build/elevation` (or `ROUTING_ELEVATION`). In Europe: SRTM and EU-DEM (Copernicus). The same tiles give the routing tiles their gradients (`Tools/build_routing_tiles.sh`).
2. **Detection** (`Tools/build_climbs.py`, numpy in its own environment):
   - roads: trunk, primary, secondary, tertiary, unclassified, residential, living street and cycleway, exported with osmium (not motorways, service roads or unpaved tracks; not where bicycles are forbidden);
   - pieces of the same named road are joined; unnamed pieces only where exactly two meet;
   - each road is sampled every 20 m and smoothed over 60 m; on bridges and in tunnels the elevation is interpolated (the model has the valley or the hill there);
   - climbs in both directions; the same climb twice (dual carriageways, a road and its cycleway) is kept once;
   - names: the road's name or number, else "Climb near <nearest town or village at the top>".
3. **Areas** (`Tools/split_climbs.py`): per 1° area of the climb's bottom, gzipped to `AssetPacks/build/routing/r2/west/climbs/v<version>/<area>.json.gz`, plus the index `Tileroam/Resources/climbs-west.json` (commit it). Every build raises the version (`CLIMBS_VERSION` overrides).

Time on an M-series Mac with 8 GB: Luxembourg 3 s, the Netherlands and Belgium 1.5 minutes, Germany about 30 minutes.

## Uploading

`Tools/upload_routing_r2.sh west` uploads the climbs of the bundled index too, to `<bucket>/west/climbs/v<version>/`, next to the routing tiles. Upload before releasing the app with a new index.

## In the app

| Part | Where | What it does |
|---|---|---|
| Data | `ClimbData`, `ClimbIndex` (`Tileroam/Geo/ClimbData.swift`) | Downloads the areas around the user's activities, the map they look at (Climbs tab, up to about 3° × 4°) and plans, into `Application Support/Climbs/west-v<version>`. Same server, retries and errors as the routing tiles (`RemoteFile`). |
| Climbed | `ClimbMatcher` (`Tileroam/Geo/Climb.swift`) | An activity climbed a climb when its track passes within 30 m of at least 90% of the climb's points (one every 50 m), reaching the bottom before the top. Stored per activity (`Activity.climbs`, with `climbsKey` = the climbs version), so activities are only checked again when the climbs change. |
| Map | Climbs tab (`MapMode.climbs`) | Climbs coloured by category (hill yellow, Cat 4 orange, Cat 3 red, Cat 2 dark red, Cat 1 purple, HC black), climbed ones green, selected or planned ones orange. Tap for the card with name, category, length, gradient, gain, steepest part, top, and when it was climbed. |
| List | Statistics → Climbs → All Climbs (`ClimbsView`) | Climbed climbs (how often, last time) and not-yet-climbed climbs in the user's areas, per category, hardest first. |
| Planning | `PlanTarget.climb`, `TargetGeometry.climbVia` | Tap climbs in planning mode. The route goes to the bottom and then over at most four points up to the top, so it rides the climb uphill. |
| Routes | `RouteCoverage.climbs` / `newClimbs` | A planned or opened GPX route lists the climbs it rides uphill, and the new ones. |

## Adding countries

Climbs follow the routing countries: after `Tools/build_routing_tiles.sh` with a new country (docs/ROUTING.md), download its elevation (`Tools/download_elevation.sh`) and run `Tools/build_climbs.sh west …` with the same extracts. France and the Alps will add many climbs; the areas stay small enough to download one at a time.
