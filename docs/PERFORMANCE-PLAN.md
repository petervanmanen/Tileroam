# Performance plan (branch `perf/map-overlays`)

Status: **done** in 1.15.1 (12 Oct 2026): the changes below are tested, measured and checked in
the simulator; see "Result". Still open: issue #74 (iPhone Duo), at the end.

## Measured (12 Oct 2026, iPhone 18 Pro Max simulator, `SWIFT_OPTIMIZATION_LEVEL=-O`)

Real data: the 1,951 activity files in iCloud (`~/Library/Mobile Documents/iCloud~nl~petervanmanen~Tileroam/Documents/Activities`).

| Step | Time | Where |
|---|---|---|
| Parse all 1,951 .fit files (serial) | 25.8 s | once per new device; the app parses in parallel |
| Track cache decode / encode | 43 ms / 49 ms | launch / background |
| Merge copies (groups + best) | 2 ms | main, every recompute |
| Eddington ×3 | 4 ms | main |
| Badge counts | 29 ms | main, every count |
| Max square + cluster | 1 ms | background |
| Tile history (video, year) | 38 ms | background |

The computation is not the problem. The map is:

| Step | Municipalities (51,064 areas, 5.2 M points) | Postcodes (22,733 areas, 1.1 M points) |
|---|---|---|
| Load boundaries, 7 countries | 1.1 s (background) | |
| `AreaGeometry` (to map points) | **0.29 s on the main thread** (first opening of the tab) | 0.06 s |
| Draw one 256-pt map tile, whole region | **84 ms** | 18 ms |
| Draw one map tile, province | 2 ms | 8 ms |
| Draw one map tile, city | 0.4 ms | 0.4 ms |

And `ActivityMapView.Coordinator.update` removed **all** overlays and added new ones whenever the
store's `version` changed — twice per recompute, after every challenge pass, after the max square,
every 10 s while iCloud downloads — so MapKit redrew every visible tile each time even when nothing
visible changed (zoomed out over the municipalities: roughly a second of drawing per update).

## Changes in this branch

1. **Keep the base overlay when it shows the same** (`ActivityMapView.swift`, `update`): the tiles
   or areas overlay is built first and compared with the one on the map (`TilesOverlay.shows(sameAs:)`
   in `SquaresOverlay.swift`, `AreaOverlay.shows(sameAs:)` in `AreaOverlay.swift`: same zoom, visited,
   selection, highlight, max square / same geometry object). Equal → it stays; only the other
   overlays and the annotations are replaced.
2. **Area geometry in the background** (`prepareAreaGeometry`): `AreaGeometry(areas)` runs in a
   detached task; the tab shows the map without areas for that moment, then `update` draws them.
   Cancelled when the countries change (`areaGeometryKey`).
3. **Less detail when zoomed out** (`AreaRenderer.draw`): ring points closer than 1.5 screen
   points (`minStep = 1.5 / zoomScale`) to the last drawn point are skipped. No visible change; at
   city zoom almost every point is kept.

4. **Badge counts only when something changed** (`ChallengeEngine.badgeCounts`): the counts
   (29 ms on the main thread) ran after every challenge pass and refresh; now they're kept until
   the activities (the fields the rules use), the number of countries or the time zone change.

## Result

- Full test suite: passes (`-parallel-testing-enabled NO -testLanguage en -testRegion US`).
- Drawing one 256-pt map tile, `-O`, seven countries, before → after (this Mac is faster than the
  one above, so compare the ratio):

  | | Municipalities | Postcodes |
  |---|---|---|
  | Whole region | 29 → **4 ms** | 6 → **1 ms** |
  | Province, city | < 1 ms both | < 1 ms both |

  `AreaGeometry` for the municipalities: 80 ms, now off the main thread.
- Simulator (iPhone 18 Pro, `-challenges gemeenten,postcodes -RegionsDir …`): the areas appear
  right after the map without a freeze; zoomed out the visited areas look as before; at city zoom
  the municipalities are pixel-identical to `main`, and the postcodes differ only in Apple's road
  shields (placed differently on every launch). Tiles unchanged.
- Not done: climbs keeping their polylines when equal (Climbs is behind `FeatureFlags.climbs`,
  off since 1.15; do it if the flag comes back on).

## Related: issue #74, iPhone Duo

Apple's foldable (announced 9 Sep 2026; 7.6″ inner, 5.4″ outer display; on sale 23 Oct). Apple's
guidance ([Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)): build with
**Xcode 27.1** (iOS 27.1 SDK) so the app resizes and uses the full inner display; use size classes,
not idiom or orientation; no fixed screen sizes; test in the iPhone Duo simulator (Xcode 27.1).

Tileroam already lays out by `horizontalSizeClass` (side panel when regular, like on iPad) and
doesn't use `UIScreen.main` or idiom checks for layout (`FolderAccess.isPad` only names "On My
iPad", by model, so the Duo says "On My iPhone"). What's missing:

- Xcode 27.1 on the build machine (this Mac has 27.0 only) and on the CI runner: the workflows
  select `/Applications/Xcode_27.app`; switch to Xcode 27.1 when the `xcode-27` runner has it
  (e.g. pick the newest `Xcode_27*.app`).
- Test closed (5.4″, compact) and open (7.6″, likely regular width) in the iPhone Duo simulator:
  header/footer vs. side panel, the plan panel, sheets, the map's leading inset.
