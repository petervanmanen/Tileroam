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
| **Import .fit Files…** | Pick .fit files, or a whole folder, for example where HealthFit, RunGap or your bike computer's app saves them. Tileroam copies them once into its own storage; the folder isn't watched afterwards, so import again to add new files. |
| **Connect with Strava** | Sign in with Strava to download your activities. They are saved as .fit files in Tileroam. |
| **Try with Sample Rides** | Loads 24 example rides around Utrecht, so you can explore the app first. You can remove them in Settings → Activities. |

You can import files and use Strava at the same time. If the same activity comes from more than one place, Tileroam keeps it once.

On a further iPhone or iPad with the same iCloud account, there's nothing to set up: Tileroam shows the activities from iCloud (see "Your devices and iCloud").

### Where do .fit files come from?
- **Garmin, Wahoo, Hammerhead and other bike computers:** they record .fit files. Their apps, or tools like HealthFit and RunGap, can save these files to iCloud Drive automatically.
- **Apple Watch workouts:** apps like HealthFit can export them as .fit files.
- **Strava:** connect your account in Tileroam.

Indoor and virtual activities, such as Zwift, Rouvy or a treadmill, count in your statistics but are not drawn on the map.

## The map

Use the tabs at the top to switch views. **Tiles** is always there. **Towns**, **Postcodes** and **Climbs** are *challenges* you turn on yourself, with the **+** at the end of the tabs or under Settings → Challenges; they're off at first, to keep the bar short. Your own challenges (see below) get a tab of their own, on as soon as they arrive. Your activities still count for every challenge, shown or not.

### Tiles
The map is divided into squares. A square turns green once you have passed through it. The squares are zoom 14 tiles, about 1.5 km wide in the Netherlands: the "explorer tiles" used by VeloViewer, StatsHunters and rideeverytile.com.

The header shows three numbers:
- **Tiles:** how many tiles you have visited.
- **Max square:** the largest fully visited square block, outlined in orange.
- **Cluster:** the number of visited tiles that are surrounded on all four sides by other visited tiles.

### Towns
The municipalities you have visited are filled in. The header shows how many of the total you have visited. Tap a municipality to see its name.

### Postcodes
Like Towns, but for postcode areas. Available for Belgium, France, Germany, the Netherlands and Switzerland (Luxembourg and Austria have no open postcode boundaries).

### Map controls
- **Layers button (bottom right):** choose Map, Satellite or Hybrid.
- **Arrow button:** centres the map on your location. Tileroam asks for permission the first time you tap it.

## Planning a route to new tiles

1. Tap the **route** button in the header to enter planning mode.
2. Tap unvisited tiles, municipalities or postcodes to select them. You can mix types, using the tabs to switch between them (turn on the Towns or Postcodes challenge to see their tab).
3. Choose where to start (optional). The route starts and ends at your current location, unless you choose a different **starting point**:
   - tap **Start: My Location** in the panel to search for an address or place, or pick a recent starting point;
   - or long-press the map and choose **Start Here**. Drag the green flag to move it.

   This lets you plan tonight for tomorrow's ride from home, or from a station or car park. Tileroam remembers your last five starting points on this device.

   For a ride from A to B, tap **End: Back to Start** and choose an **end point** the same way (search, or a recent place), or long-press the map and choose **End Here**. A checkered flag marks it on the map; drag it to move it. Choose **Back to Start** again for a round trip. With an end point you can also plan without selecting anything: the shortest cycling route from the start to the end.
4. Tap **Plan Route**. Tileroam plans a cycling round trip from the starting point past all selected items (or a route to the end point), and shows:
   - the distance;
   - the estimated time;
   - which new tiles, municipalities and postcodes the route would add.
5. Tap **Share GPX** to send the route to your bike computer or another app, or **Save to Folder** to keep it in Tileroam's "Routes" folder.

You can also **open an existing GPX file** to see which new tiles and areas it would collect.

Route planning works in **the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria**: the starting point and all selected items must be there. Routes are calculated on your iPhone or iPad with OpenStreetMap data. The first time you plan in an area, Tileroam downloads the map data around it, typically 25 to 75 MB; the panel shows the progress, and **Stop** ends it. What was downloaded is kept, so trying again continues where it stopped, also after a dropped connection. Round trips can be up to 500 km as the crow flies along the stops. Downloads larger than 25 MB wait for Wi-Fi: on mobile data or in Low Data Mode, Tileroam says how much it would download and offers **Download Anyway**. To always allow it, turn on Settings → Storage → Download Map Data over Mobile Data. After that, planning in that area also works offline, and nothing is sent anywhere.

## Activities

Tap the **list** button in the header to see all your activities, newest first, grouped by month. Each shows:
- its sport, name, date and time;
- the duration (moving time when the file or Strava has it, otherwise from start to finish);
- the distance;
- the average power, when the activity was recorded with a power meter, or otherwise the average speed.

Indoor and virtual activities are marked "Indoor". The same workout from several sources is listed once.

## Climbs

The **Climbs** tab (turn the Climbs challenge on with the **+** at the end of the tabs) shows the climbs on the roads: short steep hills in yellow, Cat 4 to HC in orange, red, purple and black (as on Strava), and the ones you have climbed in green. A climb you tap, or one on a planned route, is blue and thicker. Tap a climb to see its length, gradient, gain, steepest part and when you climbed it. Climbs are downloaded for the areas you ride and look at, a few hundred kilobytes per area.

A climb counts as climbed when an activity rides almost all of it uphill, from the bottom to the top. **Statistics → Climbs** shows how many you have climbed per category, and **All Climbs** lists them, with the ones you haven't climbed yet in the areas where you ride.

To **ride a climb on a planned route**, select it in planning mode on the Climbs tab: the route rides it uphill. A planned route or an opened GPX also shows which climbs it includes, and which are new.

Climbs are found by Tileroam from elevation data along OpenStreetMap's roads. Short steep hills often come out less steep than signposted, because the elevation data is about 30 m coarse.

## Your own challenges

A challenge of your own is a set of places to visit (breweries, cafés, viewpoints) or routes to ride, run or walk (trails, walking paths, ferries), in a file you put in **iCloud Drive › Tileroam › Challenges** (or *On My iPhone › Tileroam › Challenges* without iCloud). Tileroam reads the folder when it opens, and each challenge gets a tab with its emoji on the map. The format, and how to make a file, are in [challenges/README.md](../challenges/README.md); [trappist-breweries.geojson](../challenges/trappist-breweries.geojson) is an example to start from.

- **Places** count as visited when one of your activities passes within the challenge's radius (200 m unless the file says otherwise). They get a green ring and a check; tap one to see when you were there. In planning mode, tap places you haven't visited to plan a route past them; a planned route also lists the new places it passes.
- **Routes** are dark orange until done and green after. A route to *cover* (a walking path, a trail) is done when your activities together cover 90% of it (within 30 m; several activities add up); its card shows how far you are. A route to *cross* (a ferry) is done when one activity goes from one end to the other; riding along the bank doesn't count.
- A challenge can count only some sports, for example rides for mountain bike routes.

Settings → Challenges lists your challenges: turn them on or off, or swipe one away to delete its file. A file Tileroam can't use is listed there with the reason. Statistics shows your progress per challenge, and the Year in Review what was new that year.

Until version 1.12, Tileroam had the Trappist breweries, the boscafés, the ferries, the Klompenpaden and the mountain bike routes built in. They're challenge files now; their visits are counted again once you add the files.

## Statistics

At the top of Statistics:
- **Year in Review** shows a card for a year (pick it at the top): the tiles you added that year in orange on the map, with the earlier ones in blue, and how the year went: new tiles, activities, kilometres, max square and Eddington number (with how much they grew), new municipalities, postcodes, countries and climbs, Trappist breweries, boscafés and ferries, and the badges you earned. Share it as an image.
- **Tile History Video** makes a video of about 20 seconds (1080 × 1920): your tiles appear on the map in the order you first visited them, with the month and the count running, and it ends on your max square. It shows the country of your largest cluster. Share it or save it to Photos.

Tap the **chart** button for the categories below. Each is one small row with a summary; tap it to open it.
- **Overview:** countries, municipalities, postcodes and tiles visited.
- **Eddington number:** the largest number E such that you covered at least E km on at least E days, for cycling, walking and running. It also shows how many more activities you need to reach the next number.
- **Climbs:** how many climbs you have climbed, per category.
- **Badges:** all 18 badges; the ones you have earned are in colour, with **×2**, **×3** … when you earned one more than once. Tap a badge to see what it takes. Indoor and virtual activities count too. The badges: 100! and Century (100 km and 100 miles in one ride), Hollander (100 km with less than 100 m climbing), Everester (8,848 m of climbing within 24 hours), Pretzel (Zwift's Uber Pretzel: the name, at least 128 km and 2,300 m of climbing), Nosleep (an activity of more than 24 hours), Every day I'm hustling (every day of a week), Working 9 to 5 (every working day, free weekends around it), Triple jump (activity, 1 rest day, activity, 2 rest days, activity), Triathlete (swim, bike and run on one day, in that order), Eddy the Eagle (1,000 m of skiing or snowboarding descent in a day), Marathon and Half Marathon, Silent night (Christmas Eve), Giant leap (29 February), Festive 500 (500 km from 24 to 31 December), Globetrotter (activities in 50 countries, worked out on your device from a world map) and Taylor (100 Zwift activities). Climbing and descent come from your .fit files and Strava (Strava has no descent).
- **Municipalities per country:** your progress in each country.
- **Totals:** distance, time and number of activities per sport, for this year and for all time.

## Widgets

Add Tileroam widgets to your Home Screen. Touch and hold the Home Screen, tap **Edit → Add Widget** and search for Tileroam.
- **Eddington Number:** your cycling Eddington number and what you need for the next one.
- **Tiles Around You:** a map of the tiles around your current location, with visited tiles in green. Comes in small, medium and large sizes. To keep it up to date, allow location access "While Using the App or Widgets".

## Countries

Municipalities and postcodes are available for **the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria**, the same countries as route planning. Postcodes exist for the Netherlands, Belgium, Germany, France and Switzerland. Tiles, routes and statistics work everywhere.

A country is counted as soon as you have an activity there; there is nothing to set up. The municipality and postcode boundaries of a country are downloaded the first time you have an activity there, so the app itself stays small. This needs an internet connection once per country.

## Storage

Settings → Storage shows what Tileroam keeps on your device:
- **Route planning map data:** the areas downloaded for route planning, about 70 × 110 km each, named after a town in the area. Swipe left on an area to remove it, or remove all of them at once. Removed areas download again the next time you plan a route there.
- **Download Map Data over Mobile Data:** allows map downloads larger than 25 MB without Wi-Fi.
- **Municipalities and postcodes:** the boundaries per country. They are small and download again automatically, so they can't be removed.
- **Activity cache:** what Tileroam has read from your .fit files. **Clear Cache & Re-import** empties it and reads all files again; your files themselves are not touched.

## Your devices and iCloud

Tileroam keeps every activity and planned route in its own storage on the device: **On My iPhone › Tileroam › Activities** and **› Routes**.

With **Settings → Activities → Sync with iCloud** on (the default when you're signed in to iCloud with iCloud Drive on), they're also kept in **iCloud Drive › Tileroam**, without duplicates. Your other devices with the same Apple Account then have the same activities, also on a new device without importing anything or connecting Strava again. The map style and the challenges you show are kept in sync too. Turning sync off keeps both copies; the device then stops reading and writing iCloud.

**Deleting an activity:** in Activities, swipe left on it and tap **Delete**. It's deleted on this device and from iCloud, so your other devices remove it too. It stays on Strava and wherever you imported it from; a deleted Strava activity isn't downloaded again.

**Updating from an earlier version:** Tileroam copies the files it used to read (from the folders you had chosen, its folder in iCloud Drive and your save folder) into its own storage once. Nothing is downloaded from Strava again, and the original files stay where they are. The folders you had chosen aren't watched afterwards.

## Strava

In Settings → Strava, tap **Connect with Strava**. Tileroam first loads your activity list with simplified routes, then downloads the detailed GPS over time.

Strava limits how many requests apps may make, so a large history can take a while. The sync continues by itself.

Each activity is saved as a .fit file in Tileroam's activities (and iCloud, with sync on). You can disconnect at any time in Settings. You then choose whether to also delete the .fit files Tileroam saved from Strava; files from other apps are never touched.

## Privacy

Tileroam has no accounts, no analytics and no advertising. See the [privacy policy](../PRIVACY.md).

## Help

See [Support](../SUPPORT.md) for frequently asked questions and how to get in touch.
