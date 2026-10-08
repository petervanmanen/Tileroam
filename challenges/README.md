# Challenges

A challenge is a set of **places to visit** (breweries, cafés, viewpoints, summits) or **routes to ride, run or walk** (signposted trails, walking paths, ferries). Tileroam shows a challenge as a tab on the map, checks every activity against it, and counts your progress in Statistics and in the Year in Review. You can plan a route to the places of a challenge you haven't visited yet.

A challenge is one file in the format below, a [GeoJSON](https://geojson.org) file with a small `tileroam` block. You can make one with any text editor, export one from [geojson.io](https://geojson.io), QGIS or an OpenStreetMap tool and add the block, or write a script.

**Example:** [`trappist-breweries.geojson`](trappist-breweries.geojson), the Trappist breweries with a 🍺.

## Adding a challenge to Tileroam

Put the file in the **Challenges** folder in the Files app:

- **iCloud Drive › Tileroam › Challenges** with *Sync with iCloud* on (Settings → Activities). All your devices then have the challenge.
- **On My iPhone › Tileroam › Challenges** (or *On My iPad*, *On My Mac*) without iCloud. A file put here while iCloud sync is on is moved to iCloud Drive.

Tileroam reads the folder when it opens or comes back to the foreground. A new challenge is turned on and appears as a tab at the top of the map. Turn it off with the **+** at the end of the tabs, or in Settings → Challenges. Hidden challenges still count.

To change a challenge, replace its file. Tileroam checks your activities against the new version. To remove a challenge, delete its file, or swipe it away in Settings → Challenges. Your activities stay.

When a file can't be used, Settings → Challenges says why. [`Tools/check_challenge.py`](../Tools/check_challenge.py) checks files on a computer with the same rules:

```bash
Tools/check_challenge.py my-challenge.geojson
```

## The format (version 1)

A challenge file is a GeoJSON `FeatureCollection` with a `tileroam` member next to `features`. Its name ends in `.geojson` (or `.json`). Coordinates are longitude and latitude in WGS 84 (`[5.12, 52.09]`), as in all GeoJSON.

```json
{
  "type": "FeatureCollection",
  "tileroam": {
    "format": 1,
    "id": "trappist-breweries",
    "name": "Trappist breweries",
    "tab": "Trappists",
    "kind": "locations",
    "icon": "🍺",
    "radius": 200
  },
  "features": [
    {
      "type": "Feature",
      "id": "westmalle",
      "geometry": { "type": "Point", "coordinates": [4.65667, 51.28472] },
      "properties": { "name": "Brouwerij der Trappisten van Westmalle", "subtitle": "Westmalle" }
    }
  ]
}
```

### The `tileroam` block

| Field | Required | For | Meaning |
|---|---|---|---|
| `format` | yes | all | The format version: `1`. A file with a higher version needs a newer Tileroam. |
| `name` | yes | all | The challenge's name, as in Settings and Statistics. |
| `kind` | yes | all | `"locations"`: places to visit. `"routes"`: routes to ride, run or walk. |
| `id` | no | all | A short id of lower-case letters, digits and hyphens (at most 64), unique among your challenges. It ties your progress to the challenge, so keep it when you change the file. Default: made from the file name. |
| `tab` | no | all | A short name for the tab on the map (about 12 characters). Default: `name`. |
| `icon` | no | all | One emoji, drawn on the map and on the cards. Default: 📍 for locations, 🛤️ for routes. |
| `description` | no | all | A sentence about the challenge. |
| `attribution` | no | all | Where the data comes from and its license, shown in Settings → Sources & Licenses. Markdown links are allowed: `© OpenStreetMap contributors (ODbL), [openstreetmap.org](https://www.openstreetmap.org/copyright)`. |
| `url` | no | all | The challenge's website (`https://…`). |
| `sports` | no | all | Only activities of these sports count, for example `["Cycling", "E-biking"]`. Default: all activities with GPS. See [Sports](#sports). |
| `radius` | no | locations | Metres between a place and your track for a visit, 10–5000. Default: `200`. |
| `complete` | no | routes | When a route is done: `"cover"` or `"cross"`. Default: `"cover"`. See [Routes](#routes). |
| `coverage` | no | routes, `cover` | The share of a route to cover, 0.1–1. Default: `0.9` (GPS and the route's drawing never match exactly). |
| `spacing` | no | routes, `cover` | Metres between the checkpoints along a route, 10–1000. Default: `50`. Use `100` or more for long routes (over 20 km) or thousands of routes, so checking stays quick. |

Other members are ignored, so you can keep your own notes in the file.

### Features

Every place or route is a GeoJSON `Feature`:

| Member | Required | Meaning |
|---|---|---|
| `id` | yes | The feature's `id` (or `properties.id`): a string or number, unique within the file. It ties your visits to the place, so keep it when you change the file. |
| `geometry` | yes | Locations: a `Point`. Routes: a `LineString`, or a `MultiLineString` for a route in pieces (`cover` only). A crossing (`cross`) is one `LineString` from one end to the other. |
| `properties.name` | yes | The place's or route's name. |
| `properties.subtitle` | no | A line under the name on its card: the town, the operator, the lengths of a walk. |
| `properties.icon` | no | One emoji instead of the challenge's, for this place. |
| `properties.url` | no | A web page about it (`https://…`), linked from its card. |
| `properties.difficulty` | no | Routes: `"easy"`, `"moderate"`, `"hard"` or `"very-hard"`, shown in green, blue, red or black. |

Tileroam skips features without an id or a name, with the wrong geometry, or with an id used before, and says how many in Settings → Challenges. A file without any usable feature can't be used.

### Locations

A place is **visited** when one of your activities passes within `radius` metres of it. The distance is measured to the lines between the points of your track, so a track with few points (a Strava summary) counts too. Visited places get a green ring and a check; their card says how often and when you last came by.

In route planning, tap places you haven't visited to plan a route past them, together with tiles, municipalities and postcodes.

### Routes

- **`cover`** (walking paths, MTB trails): Tileroam puts a checkpoint every `spacing` metres along the route. Your progress is the share of checkpoints that any of your activities passed within 30 m of, all activities together. A route is **done** at `coverage` (90%). Done routes are green, the others orange; the card shows the progress.
- **`cross`** (ferries, bridges, passes): a route is **done** when one activity comes near both ends of the line and near its middle. Riding along the bank to one end and back doesn't count. The tolerance is a third of the crossing's length, 15–80 m. Crossings are drawn as a badge at their middle.

Routes are things to ride themselves, so they aren't route planning targets.

### Sports

The names Tileroam gives activities, for `sports`: `Cycling`, `E-biking`, `Running`, `Walking`, `Hiking`, `Swimming`, `Skiing`, `Snowboarding`, `Cross-country skiing`, `Rowing`, `Inline skating`, `Fitness`. Indoor and virtual activities never count: they have no real track.

### Changing a challenge

Every activity is checked against a challenge once, and the result is kept. When the file changes, every activity is checked again, so changing a file is fine, but a big file (thousands of routes) takes a while the first time. Keep the `id`s of the challenge and its features: visits are stored by id.

### Size

There's no fixed limit. The file is read on every device, and a few megabytes is fine; the 4,700 MTB routes of OpenStreetMap are about 16 MB with 5 decimals per coordinate (about 1 m). Round coordinates to 5 decimals and leave out what Tileroam doesn't use.

## Schema

[`schema.json`](schema.json) is a JSON Schema of the format, for editors that check JSON (Visual Studio Code: add `"$schema": "https://raw.githubusercontent.com/petervanmanen/Tileroam/main/challenges/schema.json"` to the file). The rules above, and `Tools/check_challenge.py`, are what the app uses.

## Making challenge files from other data

[`Tools/make_challenges.py`](../Tools/make_challenges.py) makes the challenges that were built into Tileroam until version 1.12 from their lists: the Trappist breweries, the boscafés, the ferries, the Klompenpaden and the mountain bike routes. Only the Trappist breweries are in this repository, as the example; the others are made locally and kept out of git (`.gitignore`), because of their sources' licenses and size.

## Rights

Only use data you may use: your own, open data (OpenStreetMap is ODbL: credit it in `attribution`), or data you have permission for. Logos and other images aren't part of the format; use an emoji.
