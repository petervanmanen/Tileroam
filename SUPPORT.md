# Tileroam Support

For how to use Tileroam, see the [user guide](docs/MANUAL.md).

## Contact

Found a problem or have a question? [Open an issue on GitHub](https://github.com/petervanmanen/Tileroam/issues/new). Please include:
- your device and iOS version;
- what you did, and what happened.

If a file won't import, mention where it came from (for example Garmin, Wahoo or HealthFit).

## Frequently asked questions

**My activities don't show up.**
- Imported files are copied once: new files in that folder don't appear by themselves. Import them in Settings → Activities → Import .fit Files.
- Tileroam only reads .fit files; it doesn't read .gpx or .tcx for activities.
- Files that could not be read are listed under "Could not read".
- Files in iCloud Drive that aren't downloaded to the device yet are downloaded when Tileroam reads them. That can take a moment on a slow connection.

**An activity is in my statistics but not on the map.**
Indoor and virtual activities aren't drawn on the map: Zwift, Rouvy, treadmill and indoor cycling. Activities without GPS aren't drawn either. They do count in your totals and Eddington number.

**My tile count differs from VeloViewer, StatsHunters or Squadrats.**
- Tileroam uses the same tiles: zoom 14 explorer tiles and zoom 17 squadratinhos.
- Differences usually come from activities one service has and the other doesn't, or from GPS points right at a tile edge.
- Check in Settings → Tiles that the right tile size is selected.

**The Strava sync is slow.**
Strava limits how many requests an app may make every 15 minutes and every day. With a long history, the detailed GPS download can take a day or more. The sync continues by itself each time you open Tileroam.

**How do I get my data on my iPad too?**
- Sign in to iCloud with the same Apple Account on both devices, with iCloud Drive on.
- Keep Settings → Activities → Sync with iCloud on. Tileroam keeps its activities and routes in iCloud Drive › Tileroam, without duplicates, and a new device shows them without importing or connecting Strava.
- Strava is connected separately on each device. You only need to connect it on one device; its downloads reach the other through iCloud.

**Route planning says the area isn't supported.**
Route planning works in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria. The starting point and all selected tiles, municipalities and postcodes must be there. Away from home, choose a starting point inside these countries: tap "Start: My Location" in the planning panel, or long-press the map.

**Route planning waits for Wi-Fi.**
The first plan in an area downloads its map data. Downloads over 25 MB wait for Wi-Fi. Tap "Download Anyway" to use mobile data this once, or turn on Settings → Storage → Download Map Data over Mobile Data.

**How much space does Tileroam use?**
See Settings → Storage. You can remove downloaded route planning areas there; they download again when you plan a route in that area.

**Where are my planned routes?**
In On My iPhone › Tileroam › Routes, and with iCloud sync in iCloud Drive › Tileroam › Routes. Open them in the Files app.

**How do I remove the sample rides?**
Settings → Activities → Remove Sample Rides.

**How do I delete an activity?**
In Activities (the list button on the map), swipe left on it and tap Delete. It's removed on this device and from iCloud, not from Strava or from where you imported it.

**How do I delete my data?**
- Deleting the app removes everything it stored on the device.
- Files in iCloud Drive › Tileroam can be deleted with the Files app. With iCloud sync on, delete activities in Tileroam itself, so your other devices don't send them back.
- See the [privacy policy](PRIVACY.md).
