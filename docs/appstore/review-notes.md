# Notes for App Review

Paste the text below into App Store Connect → version page → App Review Information → Notes. Fill in the Strava demo account first (see the end of this file).

---

Tileroam shows which map tiles, municipalities and postcode areas a cyclist, runner or walker has visited, based on their own activity files (.fit), and plans routes to new ones.

HOW TO TRY IT WITHOUT YOUR OWN FILES
1. Open the app. Swipe through the short introduction, or tap Skip.
2. On the "Add your activities" card, tap "Try with Sample Rides". This loads 24 bundled example rides around Utrecht, the Netherlands.
3. Explore the tabs at the top: Tiles, Routes, Towns (municipalities) and Postcodes.
4. Statistics: tap the chart button in the header.
5. Route planning: tap the route button in the header, tap a few white (unvisited) tiles, then tap "Plan Route". The route starts at the device's location; outside Europe it still works, but the route will be long. To try it near the sample rides, set the simulator or device location to Utrecht (52.0907, 5.1214).
6. Widgets: "Tiles Around You" and "Eddington Number" can be added from the Home Screen widget gallery.

The sample rides can be removed in Settings → Import Folders → Remove Sample Rides.

STRAVA
Tileroam can import activities from Strava (Settings → Strava → Connect with Strava). Use this Strava demo account:
- Email: <STRAVA DEMO EMAIL>
- Password: <STRAVA DEMO PASSWORD>

Strava is optional; the app is fully usable without it.

LOCATION
Location is used to show the user on the map, to start planned routes from there, and in the "Tiles Around You" widget. For route planning, the start point and selected stops are sent to the public OpenStreetMap routing service (FOSSGIS). This is stated in the permission text and the privacy policy.

ICLOUD
With iCloud Drive on, files are kept in "iCloud Drive › Tileroam" so the user's other devices see the same activities. Without iCloud, the app works the same with on-device storage.

No account, sign-in, purchase or subscription is needed.

---

## Before submitting: Strava demo account
1. Create a separate Strava account for App Review. Don't use your personal one.
2. Upload or record a few activities with GPS, for example by importing some of the sample rides via strava.com → Upload activity.
3. Fill in the email and password above.
4. Make sure your Strava API application's athlete capacity allows one more athlete.
5. Remove the reviewer's athlete later via Strava if you need the capacity back.
