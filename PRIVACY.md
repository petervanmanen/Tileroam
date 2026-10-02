# Privacy Policy

*Last updated: 2 October 2026*

Tileroam is an iPhone and iPad app that shows which map tiles, municipalities and postcodes you have visited, based on your own activity files. It is built so that your data stays with you.

**Short version:** Tileroam has no accounts, no analytics, no advertising and no tracking. The developer does not receive your activities or your location. The only thing the developer's server keeps is a short-lived list of Strava events (your Strava athlete number and the numbers of deleted activities, for at most 30 days) if you connect Strava; see below.

## What Tileroam uses, and where it goes

### Activity files (.fit)
Tileroam reads .fit files from folders you choose, from its own folder in iCloud Drive, and from its storage on your device. It reads them on your device. Tracks, tiles and statistics are calculated and stored only on your device, and in your iCloud account if you use iCloud Drive.

### Location
Your location is used to:
- show where you are on the map;
- show the tiles around you in the "Tiles Around You" widget;
- start planned routes from where you are.

Your location stays on your device. The widget reads it from a container that only Tileroam and its widget can open. The only exception is route planning: when you plan a route, your start point and the stops you selected are sent to the public OpenStreetMap routing service (routing.openstreetmap.de, run by FOSSGIS e.V.), which calculates the cycling route. See the [FOSSGIS privacy policy](https://www.fossgis.de/datenschutzerklaerung/).

You can turn off location access at any time in the Settings app. Tileroam keeps working without it.

### iCloud
If you are signed in to iCloud, Tileroam stores two things in your own iCloud account, so all your devices have them:
- **Files:** planned routes, downloaded activities and imported files, in the "iCloud Drive › Tileroam" folder.
- **Settings:** a few settings, such as the tile zoom, map style and countries.

This data is stored by Apple under your Apple Account and [Apple's privacy policy](https://www.apple.com/legal/privacy/). The developer has no access to it.

### Maps
Maps are shown with Apple MapKit. Apple receives the map areas that are displayed, as with any app that shows Apple Maps; see Apple's privacy policy.

### Strava (optional, where available)
If you connect Strava, Tileroam downloads your activities from Strava to your device and saves them as .fit files in your save folder.
- **Login:** a small service of the developer (a Cloudflare Worker) exchanges the login code for access tokens, so the app's Strava secret is not in the app. It doesn't store or log the tokens.
- **Strava events:** Strava tells that service when you revoke Tileroam's access and when you create or delete an activity. The service keeps these events for at most 30 days: your Strava athlete number, the activity number, the kind of event and its time. Nothing else (no names, routes or other activity data). Tileroam reads them when it opens, to delete its copies of activities you deleted on Strava, or everything it saved from Strava when you revoked access. Only your own app can read your events.
- **Tokens:** your Strava tokens are kept in the iOS Keychain on your device.
- **Disconnecting:** you can disconnect in Settings at any time. Tileroam then removes the connection and its copy of your Strava activities from the device, and offers to delete the .fit files it saved from Strava. When you revoke Tileroam's access on Strava's website, Tileroam removes the connection and deletes the files it saved from Strava the next time it opens.

Strava's handling of your data is covered by [Strava's privacy policy](https://www.strava.com/legal/privacy).

### Files you export
GPX files you export go only where you send them, for example through the share sheet.

## What Tileroam does not do
- It does not collect personal data on any server of the developer, apart from the Strava event list described above.
- It does not use analytics, crash-reporting or advertising SDKs.
- It does not track you across apps or websites.
- It does not sell or share data with third parties.

## Deleting your data
- **On your device:** deleting the app removes everything it stored on the device.
- **In iCloud:** files are in "iCloud Drive › Tileroam" and can be deleted with the Files app. The synced settings are a few small values, such as the chosen zoom level, tied to your Apple Account.

## Children
Tileroam does not knowingly collect any data from anyone, including children.

## Changes
If this policy changes, the new version will be published here with a new date. The history of changes is visible in this repository.

## Contact
For questions about privacy, open an issue at <https://github.com/petervanmanen/Tileroam/issues>.
