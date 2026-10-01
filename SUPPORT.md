# Tileroam Support

For how to use Tileroam, see the [user guide](docs/MANUAL.md).

## Contact

Found a problem or have a question? [Open an issue on GitHub](https://github.com/petervanmanen/Tileroam/issues/new). Please include:
- your device and iOS version;
- what you did, and what happened.

If a file won't import, mention where it came from (for example Garmin, Wahoo or HealthFit).

## Frequently asked questions

**My activities don't show up.**
- Open Settings → Import Folders. Check that the folder is listed and that it has no warning.
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
- Tileroam keeps its files in iCloud Drive › Tileroam, and both devices read them.
- Strava is connected separately on each device. You only need to connect it on one device; its downloads reach the other through iCloud.

**Where are my planned routes?**
In the "Routes" subfolder of your save folder. By default that is iCloud Drive › Tileroam › Routes. Open it in the Files app.

**How do I remove the sample rides?**
Settings → Import Folders → Remove Sample Rides.

**How do I delete my data?**
- Deleting the app removes everything it stored on the device.
- Files in iCloud Drive › Tileroam can be deleted with the Files app.
- See the [privacy policy](PRIVACY.md).
