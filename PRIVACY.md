# Privacy Policy

*Last updated: 7 October 2026*

Tileroam is an iPhone and iPad app that shows which map tiles, municipalities and postcodes you have visited, based on your own activity files. It is built so that your data stays with you.

**Short version:** Tileroam has no accounts, no analytics, no advertising and no tracking. The developer does not receive your activities or your location. Route planning downloads map data around the area you plan in from the developer's storage at Cloudflare, which keeps no logs. The only thing the developer's server keeps is a short-lived list of Strava events (your Strava athlete number and the numbers of deleted activities, for at most 30 days) if you connect Strava; see below.

## What Tileroam uses, and where it goes

### Activity files (.fit)
Tileroam keeps a copy of the .fit files you import or download from Strava in its own storage on your device, and reads them there. Tracks, tiles and statistics are calculated and stored only on your device, and in your iCloud account if you use iCloud Drive.

### Location
Your location is used to:
- show where you are on the map;
- show the tiles around you in the "Tiles Around You" widget;
- start planned routes from where you are, unless you choose another starting point.

Your location stays on your device. The widget reads it from a container that only Tileroam and its widget can open. Route planning also runs entirely on your device, with OpenStreetMap map data that Tileroam downloads for the area around a plan (see "Map data downloads"); your route, its start and its stops are not sent anywhere.

You can turn off location access at any time in the Settings app. Tileroam keeps working without it.

### Starting points
You can start a planned route somewhere other than your location:
- **Search:** what you type in the search field goes to Apple's MapKit search to find matching addresses and places, as in any app with Apple Maps search.
- **Long-press on the map:** the coordinate goes to Apple's MapKit to look up the address there, so the starting point gets a name.
- **Recent starting points:** your last five are kept on your device only. Swipe one away in the list to remove it.

### Map data downloads
- **Municipality and postcode boundaries** are downloaded from Apple's servers (App Store asset packs) when they are first needed. Apple handles these downloads like app downloads.
- **Route planning map data and climbs** are downloaded from the developer's storage at Cloudflare (Cloudflare R2): map data in small pieces of about 25 × 25 km for the area around a route you plan, and climbs per area of about 70 × 110 km for where you ride, the map you look at and your plans. Like any download, such a request reveals your IP address and which map pieces are fetched, and so roughly the area you plan in. The storage keeps no access logs, and the developer doesn't record or receive these requests. Cloudflare's handling is covered by [Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/).

You can see and remove the route planning map data in Settings → Storage.

### Your own challenges
Challenges you add are files you put in the Challenges folder (iCloud Drive › Tileroam › Challenges, or on your device without iCloud). Tileroam reads them and checks your activities against them on your device; nothing about them is sent anywhere. Links in a challenge open in your browser only when you tap them.

### iCloud
If you are signed in to iCloud, Tileroam stores two things in your own iCloud account, so all your devices have them:
- **Files:** your activities, planned routes and challenges, in the "iCloud Drive › Tileroam" folder, while "Sync with iCloud" is on (Settings → Activities).
- **Deleted activities:** the names of activity files you deleted and the numbers of deleted Strava activities, in iCloud's key-value store, so your other devices delete them too.
- **Settings:** a few settings, such as the tile zoom and map style.

This data is stored by Apple under your Apple Account and [Apple's privacy policy](https://www.apple.com/legal/privacy/). The developer has no access to it.

### Maps
Maps are shown with Apple MapKit. Apple receives the map areas that are displayed, as with any app that shows Apple Maps; see Apple's privacy policy.

### Strava (optional, where available)
If you connect Strava, Tileroam downloads your activities from Strava to your device and saves them as .fit files in Tileroam's own storage (and iCloud, with sync on).
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
