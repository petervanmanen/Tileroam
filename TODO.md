# To do

What's still open (13 October 2026; the retired challenges' files on R2 and the unused asset
packs were removed that day). Finished work is in the git history and the pull requests;
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

## Before App Review (you)
- **Strava demo account** for App Review: fill in `docs/appstore/review-notes.md` (still a
  placeholder) and check that the Strava app's athlete capacity has room for it.
- **App Privacy** in App Store Connect: *Identifiers → User ID* added, *Precise Location* removed;
  see `docs/appstore/app-privacy.md`.
- **Test routing on a device** via TestFlight: near home, across a border, from a chosen start, and
  offline in an area downloaded before.

## Servers and App Store Connect (you)
- **Strava Worker:** set `STRAVA_SUBSCRIPTION_ID` = 375082, so it only accepts events of
  Tileroam's subscription (the app checks events with Strava since 1.15 anyway, #68). Keep the
  `workers.dev` address: the webhook is registered to it.
- **Strava Client Secret:** rotate it (it used to be in local development builds) and update the
  Worker.

## Check
- **Strava API terms:** Tileroam keeps activities as .fit files (also in iCloud) and deletes them
  through the webhook queue; check that's within the agreement, and the rate limits granted.
- **Trademark check** for the name "Tileroam".
- **Third-party names** (issue #69 leftovers): the Pretzel and Taylor badges mention Zwift.
