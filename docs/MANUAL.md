# Tileroam User Guide

Tileroam shows everywhere you have been on your rides, runs and walks:
- every map tile you have visited;
- every municipality you have visited;
- every postcode area you have visited.

It also helps you plan routes to new ones. Your activities stay on your device and in your own iCloud.

## Getting started

When you first open Tileroam, a short introduction explains the main features. After that, add your activities in one of these ways:

| Option | What it does |
|---|---|
| **Choose Folder…** | Pick a folder with .fit files, for example in iCloud Drive where HealthFit, RunGap or your bike computer's app saves them. Tileroam reads the folder and its subfolders, and checks it for new files every time you open the app. |
| **Import .fit Files…** | Pick individual .fit files. They are copied into Tileroam's own folder. |
| **Connect with Strava** | Sign in with Strava to download your activities. They are saved as .fit files in Tileroam's folder. |
| **Try with Sample Rides** | Loads 24 example rides around Utrecht, so you can explore the app first. You can remove them in Settings → Import Folders. |

You can add several folders and use Strava at the same time. If the same activity appears in more than one place, Tileroam counts it once.

### Where do .fit files come from?
- **Garmin, Wahoo, Hammerhead and other bike computers:** they record .fit files. Their apps, or tools like HealthFit and RunGap, can save these files to iCloud Drive automatically.
- **Apple Watch workouts:** apps like HealthFit can export them as .fit files.
- **Strava:** connect your account in Tileroam.

Indoor and virtual activities, such as Zwift, Rouvy or a treadmill, count in your statistics but are not drawn on the map.

## The map

Use the tabs at the top to switch between four views.

### Tiles
The map is divided into squares. A square turns green once you have passed through it. Choose the tile size in Settings → Tiles:
- **Zoom 14 tiles** are about 1.5 km wide in the Netherlands. These are the "explorer tiles" used by VeloViewer, StatsHunters and rideeverytile.com.
- **Zoom 17 squadratinhos** are about 190 m wide, as used by Squadrats.

The header shows three numbers:
- **Tiles:** how many tiles you have visited.
- **Max square:** the largest fully visited square block, outlined in orange.
- **Cluster:** the number of visited tiles that are surrounded on all four sides by other visited tiles.

### Routes
All your activities with GPS, drawn on the map.

### Towns
The municipalities you have visited are filled in. The header shows how many of the total you have visited. Tap a municipality to see its name.

### Postcodes
Like Towns, but for postcode areas. Available for Belgium, Germany and the Netherlands (Luxembourg has no open postcode boundaries).

### Map controls
- **Layers button (bottom right):** choose Map, Satellite or Hybrid.
- **Arrow button:** centres the map on your location. Tileroam asks for permission the first time you tap it.

## Planning a route to new tiles

1. Tap the **route** button in the header to enter planning mode.
2. Tap unvisited tiles, municipalities or postcodes to select them. You can mix types, using the tabs to switch between them.
3. Choose where to start (optional). The route starts and ends at your current location, unless you choose a different **starting point**:
   - tap **Start: My Location** in the panel to search for an address or place, or pick a recent starting point;
   - or long-press the map to start there. Drag the green flag to move it.

   This lets you plan tonight for tomorrow's ride from home, or from a station or car park. Tileroam remembers your last five starting points on this device.
4. Tap **Plan Route**. Tileroam plans a cycling round trip from the starting point past all selected items, and shows:
   - the distance;
   - the estimated time;
   - which new tiles, municipalities and postcodes the route would add.
5. Tap **Share GPX** to send the route to your bike computer or another app, or **Save to Folder** to keep it in Tileroam's "Routes" folder.

You can also **open an existing GPX file** to see which new tiles and areas it would collect.

Route planning works in **the Netherlands, Belgium, Luxembourg and Germany**: the starting point and all selected items must be there. Routes are calculated on your iPhone or iPad with OpenStreetMap data. The first time you plan in an area, Tileroam downloads the map data around it, typically 25 to 75 MB. Downloads larger than 25 MB wait for Wi-Fi: on mobile data or in Low Data Mode, Tileroam says how much it would download and offers **Download Anyway**. To always allow it, turn on Settings → Storage → Download Map Data over Mobile Data. After that, planning in that area also works offline, and nothing is sent anywhere.

## Activities

Tap the **list** button in the header to see all your activities, newest first, grouped by month. Each shows:
- its sport, name, date and time;
- the duration (moving time when the file or Strava has it, otherwise from start to finish);
- the distance;
- the average power, when the activity was recorded with a power meter, or otherwise the average speed.

Indoor and virtual activities are marked "Indoor". The same workout from several sources is listed once.

## Statistics

Tap the **chart** button for:
- **Overview:** countries, municipalities, postcodes and tiles visited.
- **Eddington number:** the largest number E such that you covered at least E km on at least E days, for cycling, walking and running. It also shows how many more activities you need to reach the next number.
- **Municipalities per country:** your progress in each country.
- **Totals:** distance, time and number of activities per sport, for this year and for all time.

## Widgets

Add Tileroam widgets to your Home Screen. Touch and hold the Home Screen, tap **Edit → Add Widget** and search for Tileroam.
- **Eddington Number:** your cycling Eddington number and what you need for the next one.
- **Tiles Around You:** a map of the tiles around your current location, with visited tiles in green. Comes in small, medium and large sizes. To keep it up to date, allow location access "While Using the App or Widgets".

## Countries

Municipalities and postcodes are available for **the Netherlands, Belgium, Luxembourg and Germany**, the same countries as route planning. Postcodes exist for the Netherlands, Belgium and Germany. Tiles, routes and statistics work everywhere.

A country is counted as soon as you have an activity there; there is nothing to set up. The municipality and postcode boundaries of a country are downloaded the first time you have an activity there, so the app itself stays small. This needs an internet connection once per country.

## Storage

Settings → Storage shows what Tileroam keeps on your device:
- **Route planning map data:** the areas downloaded for route planning, about 70 × 110 km each, named after a town in the area. Swipe left on an area to remove it, or remove all of them at once. Removed areas download again the next time you plan a route there.
- **Download Map Data over Mobile Data:** allows map downloads larger than 25 MB without Wi-Fi.
- **Municipalities and postcodes:** the boundaries per country. They are small and download again automatically, so they can't be removed.
- **Activity cache:** what Tileroam has read from your .fit files. **Clear Cache & Re-import** empties it and reads all files again; your files themselves are not touched.

## Your devices and iCloud

If you are signed in to iCloud with iCloud Drive on, Tileroam keeps its files in **iCloud Drive › Tileroam**. That includes planned routes, Strava downloads and imported files. Every device signed in to the same Apple Account sees the same activities. The tile size and map style are also kept in sync.

You can choose a different save folder in Settings → Save Folder. Without iCloud, files are kept on the device, in **On My iPhone › Tileroam**. You can open both locations in the Files app.

## Strava

In Settings → Strava, tap **Connect with Strava**. Tileroam first loads your activity list with simplified routes, then downloads the detailed GPS over time.

Strava limits how many requests apps may make, so a large history can take a while. The sync continues by itself.

Each activity is saved as a .fit file in the "Strava" subfolder of your save folder. You can disconnect at any time in Settings. You then choose whether to also delete the .fit files Tileroam saved from Strava; files from other apps are never touched.

## Privacy

Tileroam has no accounts, no analytics and no advertising. See the [privacy policy](../PRIVACY.md).

## Help

See [Support](../SUPPORT.md) for frequently asked questions and how to get in touch.
