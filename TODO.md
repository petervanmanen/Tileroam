# To do

What's still open (13 October 2026; that day the retired challenges' files on R2 and the unused
asset packs were removed, and the Strava webhook moved to /webhook/<WEBHOOK_TOKEN> with a new
subscription, its id in the Worker's STRAVA_SUBSCRIPTION_ID; and the Strava Client Secret was
rotated; and the checks were done: Strava's API terms, the trademark "Tileroam" and the Zwift names
in the badges). Finished work is in the git history and the pull requests;
the 1.0 plan, done, is in [docs/PLAN-1.0.md](docs/PLAN-1.0.md).

## App
- **iPhone Duo** (issue #74): build with Xcode 27.1 (iOS 27.1 SDK) and test folded (5.4″,
  compact) and open (7.6″, likely regular width) in its simulator: header and footer vs. the side
  panel, the plan panel, sheets, the map's leading inset. Also switch the workflows from
  `/Applications/Xcode_27.app` to Xcode 27.1 once the `xcode-27` runner has it. Notes in
  [docs/PERFORMANCE-PLAN.md](docs/PERFORMANCE-PLAN.md).
- **Apple Maps can hand cycling directions to Tileroam** (routing app, optional): declare
  `MKDirectionsApplicationSupportedModes` (bike) in Info.plist and handle the incoming
  `MKDirections.Request`: plan from Maps' start to destination with Valhalla on the device, show it
  and offer it as GPX. Then upload `docs/appstore/routing-coverage.geojson` as the Routing App
  Coverage File. About half a day.
- **GitHub workflow for the routing data** (optional): build the Valhalla tiles on a runner, upload
  them to R2 and open a pull request with the new `Tileroam/Resources/routing-west.json`. Now built
  and uploaded from a Mac (docs/ROUTING.md).
- **Climbs** are behind `FeatureFlags.climbs` (off since 1.15). If they come back: keep their map
  lines when nothing changed, as the other tabs do since 1.15.1.

- **Garmin Connect** is in Debug and TestFlight builds only (`GarminSync.availability`): Garmin's
  Personal API is "not intended for commercial applications serving multiple end users". Ask
  Garmin (through developer.garmin.com) whether an App Store app may
  offer it with each user's own key; if yes, set `FeatureFlags.garminInAppStore` and add Garmin to
  the App Privacy answers and the review notes.

## Before App Review (you)
- **Strava demo account** for App Review: fill in `docs/appstore/review-notes.md` (still a
  placeholder) and check that the Strava app's athlete capacity has room for it.
- **App Privacy** in App Store Connect: *Identifiers → User ID* added, *Precise Location* removed;
  see `docs/appstore/app-privacy.md`.
- **Test routing on a device** via TestFlight: near home, across a border, from a chosen start, and
  offline in an area downloaded before.
