# App Privacy questionnaire (App Store Connect → App Privacy)

These answers match `Tileroam/PrivacyInfo.xcprivacy` and [PRIVACY.md](../../PRIVACY.md). Keep the three in sync when something changes.

## Privacy Policy URL
https://github.com/petervanmanen/Tileroam/blob/main/PRIVACY.md

## Do you or your third-party partners collect data from this app?
**Yes, only for users who connect Strava:** their Strava athlete ID in the developer's event queue. Everything else stays on the device. Route planning runs on the device with downloaded OpenStreetMap data, so the location isn't collected.

### Data type: Identifiers → User ID
| Question | Answer |
|---|---|
| Collected for | **App Functionality** only |
| Linked to the user's identity? | **Yes** (it's their Strava athlete number) |
| Used for tracking? | **No** |

Why: only for users who connect Strava. The Worker in `backend/strava-auth` receives Strava's webhook events and keeps them for at most 30 days:
- the athlete ID;
- the activity ID;
- the event type: access revoked, activity created or deleted;
- the time.

The app reads them to delete its copies of deleted activities, or everything when access was revoked. No names, routes or other activity data are stored. Activity IDs aren't a separate data type in Apple's list; they fall under the same purpose.

### Not collected (answer "No" / leave unchecked)
- **Contact info, Health & Fitness, Financial info, Contacts, User content, Browsing / Search history, Identifiers other than User ID, Purchases, Usage data, Diagnostics, Sensitive info, Other data:** not collected.
  - Activity files are processed on the device and stored in the user's own iCloud. Apple holds that data for the user; the developer has no access, so it does not count as collected.
  - Strava activities go directly from Strava to the device. The token service forwards the login and refresh requests to Strava without storing tokens; it keeps only the event queue described above.
- **Location (precise and coarse):** not collected. It is used on the device only: the map, route planning (Valhalla on the device) and the widget.
- **Coarse location (route planning map data):** not collected. The app downloads map tiles (about 25 × 25 km) around a plan from the developer's Cloudflare R2 bucket. The request carries the IP address and which tiles, as any download does, but nothing is stored or logged (R2 has no access logs unless they're set up), so under Apple's definition (data kept longer than needed to answer the request) it isn't collected. Keep the bucket without access logging.
- **Search history:** not collected. Starting point searches and the address lookup for a long-pressed starting point go to Apple's MapKit, a platform service like the map itself, not to the developer. Recent starting points stay on the device.

## Tracking
Tileroam does not track users. There's no App Tracking Transparency prompt, no advertising identifier and no third-party SDKs.

## Required-reason APIs (in PrivacyInfo.xcprivacy)
| API | Reason | Why |
|---|---|---|
| UserDefaults | CA92.1 | App settings |
| UserDefaults | 1C8F.1 | App Group shared with the widgets |
| File timestamp | C617.1 | Modification dates of files in the app's own containers (incremental import) |
| File timestamp | 3B52.1 | Modification dates of files in folders the user picked |
