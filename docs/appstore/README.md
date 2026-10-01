# Submitting Tileroam to the App Store

Everything needed for App Store Connect is in this folder:

| File | What it's for |
|---|---|
| [metadata-en.md](metadata-en.md), [metadata-nl.md](metadata-nl.md) | Name, subtitle, promotional text, description, keywords, URLs, categories |
| [app-privacy.md](app-privacy.md) | Answers for the App Privacy questionnaire |
| [review-notes.md](review-notes.md) | Notes for App Review, including how to try the app with sample rides |
| [screenshots/iphone-6.5](screenshots/iphone-6.5) | iPhone screenshots, 1284 × 2778 (6.5″ display) |
| [screenshots/iphone-6.9](screenshots/iphone-6.9) | iPhone screenshots, 1320 × 2868 (6.9″ display, if App Store Connect asks for that size) |
| [screenshots/ipad-13](screenshots/ipad-13) | iPad screenshots, 2064 × 2752 (13″ display) |
| [check_metadata.py](check_metadata.py) | Checks the texts against App Store Connect's character limits |

Public pages the App Store links to:
- **Privacy Policy URL:** https://github.com/petervanmanen/Tileroam/blob/main/PRIVACY.md
- **Support URL:** https://github.com/petervanmanen/Tileroam/blob/main/SUPPORT.md
- **User guide:** [docs/MANUAL.md](../MANUAL.md)

## 1. One-time setup in App Store Connect
1. Sign in to [App Store Connect](https://appstoreconnect.apple.com) → **Apps → +** → **New App**.
   - Platform: iOS
   - Name: Tileroam
   - Primary language: English (U.K.)
   - Bundle ID: `nl.petervanmanen.Tileroam`
   - Apple ID (numeric, assigned by App Store Connect): `6818280181`
   - SKU: `tileroam`
2. Check that the identifiers exist in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list). Xcode created them during development:
   - App ID `nl.petervanmanen.Tileroam`, with App Groups and iCloud (CloudKit/Documents);
   - App ID `nl.petervanmanen.Tileroam.Widget`, with App Groups;
   - App Group `group.nl.petervanmanen.Tileroam`;
   - iCloud container `iCloud.nl.petervanmanen.Tileroam`.
3. **App Information:**
   - Categories: Health & Fitness (primary), Navigation (secondary).
   - Content rights: answer **Yes**, the app shows third-party content and you have the rights. The boundaries are open data under the licenses listed in Settings → Sources & Licenses (and DATA-LICENSES.md), and Strava data is the user's own, used under the Strava API agreement.
   - Age rating: answer **None/No** to every question. There's no user-generated content, no unrestricted web access, no gambling, no medical advice, and no messaging or chat. The result should be 4+.
4. **Pricing and Availability:** price (Free or a paid tier) and countries.

## 2. Before every upload
1. Raise the **build number**: Xcode → target Tileroam → General → Build, which is `CURRENT_PROJECT_VERSION`.
   - Keep it the same for the app and the widget target.
   - Change **Version** (`MARKETING_VERSION`) only for a new release.
2. Check that `Tileroam/StravaConfig.plist` exists, with `ClientID` and `TokenServiceURL`. It's not in Git. Without it, Strava doesn't appear in the build.
3. Run the tests: Product → Test, or
   ```bash
   xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
   ```
4. Check the texts:
   ```bash
   python3 docs/appstore/check_metadata.py
   ```

## 3. Asset packs (municipality and postcode boundaries)
The boundaries aren't in the app. Each country is an Apple-hosted asset pack (`regions-NL`, `regions-FR`, …, 22 in total, about 30 MB together). The app downloads a pack on demand the first time the user has an activity in that country.

1. Build the packs:
   ```bash
   Tools/build_asset_packs.sh
   ```
   This writes `AssetPacks/build/regions-<CC>.aar`.
2. Upload them to App Store Connect. Use the **Transporter** app (sign in, then drag the `.aar` files in), or the App Store Connect API.
   - Upload all 22 the first time.
   - After that, only upload the packs whose boundaries changed.
   - **Scripted:** `Tools/upload_asset_packs.sh` (all countries) or `Tools/upload_asset_packs.sh NL BE` builds and uploads with `iTMSTransporter`, using the API key in `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8` and the environment variables `ASC_KEY_ID` and `ASC_ISSUER_ID`.
   - The script needs Transporter: the Mac App Store app, or Apple's standalone installer. Xcode's own `iTMSTransporter` is only a stub.
   - **On GitHub:** the **Asset packs** workflow installs Apple's standalone Transporter and runs the script. It runs automatically for countries whose `AssetPacks/Regions` files change on `main`, or by hand from Actions → Asset packs → Run workflow.
3. In App Store Connect, check that the packs appear under the app's Background Assets, and that they're submitted with the version.
   - Without them, the Towns and Postcodes tabs stay empty, with a "couldn't download" message.
   - TestFlight builds download them too, so test there first.

**Testing locally before uploading:** Xcode's `ba-serve` serves the packs from your Mac:
```bash
xcrun ba-serve serve AssetPacks/build/*.aar --host <your-mac>.local
```
- It needs a TLS certificate for that host name. The certificate must be in your Mac's keychain and trusted on the test device.
- On the device, point Developer settings → Background Assets (development overrides) to the server's URL.
- In the simulator, the Debug-only launch argument `-RegionsDir <repo>/AssetPacks/Regions` skips downloading and reads the files directly.

## 4. Archive and upload
From the command line, this does the same as the Xcode steps below. The second command signs for distribution and uploads to App Store Connect:
```bash
xcodebuild archive -project Tileroam.xcodeproj -scheme Tileroam -configuration Release -destination 'generic/platform=iOS' -archivePath build/Tileroam.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/Tileroam.xcarchive -exportOptionsPlist Tools/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```

1. In Xcode, select the destination **Any iOS Device (arm64)**.
2. **Product → Archive.**
3. In the Organizer: **Distribute App → App Store Connect → Upload**, with automatic signing.
4. Wait for the processing email (about 10–30 minutes). Export compliance is already answered in `Info.plist` (`ITSAppUsesNonExemptEncryption = NO`), so no question appears.
5. Optional: test the build via **TestFlight** on your own iPhone and iPad first.

### Or let GitHub Actions do it
`.github/workflows/testflight.yml` tests, archives and uploads to TestFlight on GitHub's `xcode-27` runner. It uses the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` and `STRAVA_CONFIG_PLIST`. The first three are an App Store Connect API key, which must have the **Admin** role: with App Manager, cloud signing for distribution fails (exit code 70).
- **Release a version:** tag it and push the tag. That uploads version 1.0.1:
  ```bash
  git tag v1.0.1 && git push origin v1.0.1
  ```
- **Upload the current version again:** Actions → TestFlight → **Run workflow**.
- **Build numbers:** 100 + the workflow run number, set automatically. Don't upload builds numbered above 100 by hand.
- **Signing:** the runner has no certificates. The archive is built unsigned, `Tools/ci_sign_archive.sh` signs it ad hoc with its entitlements, and the export does the distribution signing with the API key (cloud signing).

`.github/workflows/test.yml` runs the tests on every push and pull request. It doesn't use any secrets.

## 5. Fill in the version page
1. **Screenshots:**
   - Drag the files from `screenshots/iphone-6.5` into "iPhone 6.5″ Display" and from `screenshots/ipad-13` into "iPad 13″ Display".
   - Recommended order: 01-tiles, 05-plan, 02-towns, 03-postcodes, 06-statistics, 04-routes, 00-intro. Apple uses the first three in search results.
   - App Store Connect scales them down for smaller devices.
2. **Texts:** promotional text, description, keywords, support URL and marketing URL, from `metadata-en.md`.
3. **Localization:** to add the Dutch texts, click the language menu (top right) → Dutch, and paste from `metadata-nl.md`. The screenshots can stay English.
4. **Build:** select the uploaded build.
5. **App Review Information:**
   - Your contact details.
   - **Sign-in required:** off. Strava is optional; the demo account goes in the notes.
   - **Notes:** paste from `review-notes.md`, after filling in the Strava demo account.
6. **App Privacy:** fill in from `app-privacy.md`. This is per app, not per version.
7. **Version release:** choose manual or automatic release after approval.
8. Click **Add for Review → Submit**.

## 6. If App Review comes back
Common questions for this kind of app, and where the answer is:
- *"We couldn't find content":* point to "Try with Sample Rides" (see the review notes).
- *Location use:* the permission text and the privacy policy explain the route-planning call to OpenStreetMap.
- *Third-party trademarks:* Strava's brand assets are used according to Strava's guidelines ("Connect with Strava" button, "Powered by Strava" logo). The texts mention other services (VeloViewer, StatsHunters, Squadrats) only to describe the tile sizes, never as keywords.

## Updating the screenshots
The screenshots come from the simulator with the bundled sample rides, using the Debug launch arguments in the app:
- `-mapMode squares|activities|gemeenten|postcodes`
- `-ShowStatistics YES`
- `-PlanDemo YES`
- `-FocusZoom 9`
- `-RegionsDir <repo>/AssetPacks/Regions` (boundaries without downloading)
- `-hasSeenIntro NO`

Set the status bar to 9:41 with `xcrun simctl status_bar <device> override --time 9:41`, set the location to Utrecht, and capture with `xcrun simctl io <device> screenshot`.
