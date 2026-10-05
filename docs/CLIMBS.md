# Climbs

Tileroam knows the climbs on the roads of the route planning countries: which ones the user has climbed, which there are, and it can plan routes over them.

Climbs aren't a thing in OpenStreetMap, and commercial climb lists can't be used, so Tileroam **finds them itself** from an open elevation model along OpenStreetMap's roads. The result for the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria (climbs version 2, October 2026): 264,471 climbs in 176 areas of 1° × 1°, 23.8 MB compressed: 194 HC, 232 Cat 1, 2,929 Cat 2, 12,812 Cat 3, 46,823 Cat 4 and 201,481 hills. (Version 1, in app 1.4, had the first four countries: 77,020 climbs.)

## What counts as a climb

| Category | Rule |
|---|---|
| HC, Cat 1 – Cat 4 | Like Strava: average at least 3%, and length (m) × average (%) at least 80,000 (HC), 64,000 (1), 32,000 (2), 16,000 (3) or 8,000 (4) |
| Hill | Not categorised, but at least 300 m at 5% or more: the short steep hills of Limburg, the Ardennes and the Flemish Ardennes |

A climb runs from a low point up to the highest point reached before the road drops more than 10 m, or on long climbs more than 5% of the height gained so far (up to 50 m), without the flat run-up. The steepest gradient is measured over 200 m.

**Known limit:** the elevation model has a resolution of about 30 m, which flattens short steep hills. The Koppenberg (600 m at 11.6% in reality) comes out at about 6%; longer climbs come out close to their real numbers. The app says so under Statistics → Climbs.

Examples it finds:

| Climb | Found | In reality |
|---|---|---|
| Cauberg | 1.1 km, 5.3% (hill) | Strava's segment: 1.1 km, 5.8% |
| Keutenberg | 560 m, 9.8% | |
| Mur de Huy (Chemin des Chapelles) | 680 m, 12.7% (Cat 4) | |
| Paterberg | 360 m, 11.6% | |
| Col du Tourmalet from Luz | 18.9 km, 7.4%, 1,403 m (HC) | 19 km, 7.4%, 1,404 m |
| Mont Ventoux from Bédoin | 21.8 km, 7.3% (HC) | 21.5 km, 7.5% |
| Col du Galibier from Valloire | 16.7 km, 6.7% (HC) | 18.1 km, 6.9% |
| Furkapass | 17 km, 6.2% (HC) | |
| Alpe d'Huez | 11.2 km, 8.0% (HC) | 13.8 km, 8.1%: the first bends from Le Bourg-d'Oisans are missing |
| Großglockner Hochalpenstraße | 8.3 km, 7.7% (Cat 1) | longer: the road's passes and tunnels split it |

## Building

```bash
Tools/download_elevation.sh 41 55 -5 17     # once: elevation tiles for the area (about 9 GB)
Tools/build_climbs.sh west netherlands belgium luxembourg germany france switzerland austria
```

1. **Elevation** (`Tools/download_elevation.sh`): 1° × 1° tiles in Valhalla's "skadi" layout (`N52/N52E005.hgt`) from the [Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) open dataset, into `AssetPacks/build/elevation` (or `ROUTING_ELEVATION`). In Europe: SRTM and EU-DEM (Copernicus). The same tiles give the routing tiles their gradients (`Tools/build_routing_tiles.sh`).
2. **Detection** (`Tools/build_climbs.py`, numpy in its own environment):
   - roads: trunk, primary, secondary, tertiary, unclassified, residential, living street and cycleway, exported with osmium (not motorways, service roads or unpaved tracks; not where bicycles are forbidden);
   - pieces of the same road are joined into one line: by road number (`ref`) where there is one, else by name; unnamed pieces only where exactly two meet. A col road changes its name many times on the way up (the D 918 over the Tourmalet has ten names), but keeps its number;
   - where several pieces of the road meet, the line stays on the same kind of road (a side street with the same name may go straight on at a hairpin, as on the Cauberg), then goes straightest on (one-way pairs). Main roads are joined first;
   - two lines of the same road whose ends are within 300 m are joined too, where the number or name is missing on a stretch (the one-way streets through Barèges have no `ref`). The gap counts as a bridge;
   - each road is sampled every 20 m and smoothed over 60 m; on bridges and in tunnels the elevation is interpolated (the model has the valley or the hill there);
   - climbs in both directions; the same climb twice (dual carriageways, a road and its cycleway) is kept once;
   - names: the road name used most on the climb's upper half (else anywhere on it, else the number), else "Climb near <nearest town or village at the top>".
3. **Areas** (`Tools/split_climbs.py`): per 1° area of the climb's bottom, gzipped to `AssetPacks/build/routing/r2/west/climbs/v<version>/<area>.json.gz`, plus the index `Tileroam/Resources/climbs-west.json` (commit it). Every build raises the version (`CLIMBS_VERSION` overrides).

Time on an M-series Mac with 8 GB: all seven countries 23 minutes (France and Germany most of it). Run it in a terminal of your own, or check that it fits the time limit of background tasks.

## Uploading

`Tools/upload_routing_r2.sh west` uploads the climbs of the bundled index too, to `<bucket>/west/climbs/v<version>/`, next to the routing tiles. Upload before releasing the app with a new index.

## In the app

| Part | Where | What it does |
|---|---|---|
| Data | `ClimbData`, `ClimbIndex` (`Tileroam/Geo/ClimbData.swift`) | Downloads the areas around the user's activities, the map they look at (Climbs tab, up to about 3° × 4°) and plans, into `Application Support/Climbs/west-v<version>`. Same server, retries and errors as the routing tiles (`RemoteFile`). |
| Climbed | `ClimbMatcher` (`Tileroam/Geo/Climb.swift`) | An activity climbed a climb when its track passes within 30 m of at least 90% of the climb's points (one every 50 m), and passes the bottom at some time before it passes the top (so up and back down the same road counts; only descending doesn't). Stored per activity (`Activity.climbs`, with `climbsKey` = the climbs version and `ClimbMatcher.version`), so activities are only checked again when the climbs or the rules change. |
| Map | Climbs tab (`MapMode.climbs`) | Climbs coloured by category (hill yellow, Cat 4 orange, Cat 3 red, Cat 2 dark red, Cat 1 purple, HC black), climbed ones green, the selected one (and those on a planned route) blue and thicker. Tap for the card with name, category, length, gradient, gain, steepest part, top, and when it was climbed. |
| List | Statistics → Climbs → All Climbs (`ClimbsView`) | Climbed climbs (how often, last time) and not-yet-climbed climbs in the user's areas, per category, hardest first. |
| Planning | `PlanTarget.climb`, `TargetGeometry.climbVia` | Tap climbs in planning mode. The route goes to the bottom and then over at most four points up to the top, so it rides the climb uphill. |
| Routes | `RouteCoverage.climbs` / `newClimbs` | A planned or opened GPX route lists the climbs it rides uphill, and the new ones. |

## Adding countries

Climbs follow the routing countries: after `Tools/build_routing_tiles.sh` with a new country (docs/ROUTING.md), download its elevation (`Tools/download_elevation.sh`) and run `Tools/build_climbs.sh west …` with the same extracts. Check a few known climbs of the new country against reality (see the examples above); new kinds of road data may need another rule.
