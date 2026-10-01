# App Privacy questionnaire (App Store Connect → App Privacy)

These answers match `Tileroam/PrivacyInfo.xcprivacy` and [PRIVACY.md](../../PRIVACY.md). Keep the three in sync when something changes.

## Privacy Policy URL
https://github.com/petervanmanen/Tileroam/blob/main/PRIVACY.md

## Do you or your third-party partners collect data from this app?
**Yes.** The only data that leaves the device to a third party is the location used for route planning.

### Data type: Location → Precise Location
| Question | Answer |
|---|---|
| Collected for | **App Functionality** only |
| Linked to the user's identity? | **No** |
| Used for tracking? | **No** |

Why: when the user taps *Plan Route*, the start point (current location) and the selected stops are sent to the OpenStreetMap routing service (routing.openstreetmap.de, FOSSGIS e.V.) to calculate the route. No account or identifier is sent with it.

### Not collected (answer "No" / leave unchecked)
- **Contact info, Health & Fitness, Financial info, Contacts, User content, Browsing / Search history, Identifiers, Purchases, Usage data, Diagnostics, Sensitive info, Other data:** not collected.
  - Activity files are processed on the device and stored in the user's own iCloud. Apple holds that data for the user; the developer has no access, so it does not count as collected.
  - Strava activities go directly from Strava to the device. The token service only forwards the login and refresh request to Strava; it stores and logs nothing.
- **Coarse Location:** not collected. Only precise location is used, as above.

## Tracking
Tileroam does not track users. There's no App Tracking Transparency prompt, no advertising identifier and no third-party SDKs.

## Required-reason APIs (in PrivacyInfo.xcprivacy)
| API | Reason | Why |
|---|---|---|
| UserDefaults | CA92.1 | App settings |
| UserDefaults | 1C8F.1 | App Group shared with the widgets |
| File timestamp | C617.1 | Modification dates of files in the app's own containers (incremental import) |
| File timestamp | 3B52.1 | Modification dates of files in folders the user picked |
