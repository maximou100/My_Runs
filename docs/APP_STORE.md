# App Store Connect — Listing Reference

Source of truth for all metadata to paste into App Store Connect for the **My Runs** iOS app.

---

## App information

| Field | Value |
| --- | --- |
| **Name** | My Runs |
| **Subtitle** *(max 30 chars)* | All your runs, in one place |
| **Primary Category** | Health & Fitness |
| **Secondary Category** | Sports |
| **Bundle ID** | `Max-Leclercq.My-Runs` |
| **SKU** | `myruns-ios-001` |
| **Privacy Policy URL** | https://maximou100.github.io/My_Runs/privacy/ |
| **Support URL** | https://github.com/maximou100/My_Runs/issues |
| **Marketing URL** *(optional)* | https://maximou100.github.io/My_Runs/ |

---

## Promotional Text *(max 170 chars — editable without resubmission)*

> Import every run you've ever logged — from Nike Run Club, Apple Health, or any TCX export — and see your full running history beautifully visualized on your iPhone.

---

## Description *(max 4000 chars)*

```
My Runs is the personal running tracker for runners who already have years of data trapped in other apps.

Import your full running history from Nike Run Club TCX exports, Apple Health, or any TCX file. Watch your runs come together in a single, fast, beautiful dashboard. Every device you own stays in sync through your own private iCloud account — no servers, no accounts, no third parties.

WHAT'S INSIDE

• Bulk TCX import. Drop in hundreds of files at once.
• Apple Health import. Pull running workouts with GPS routes from your Apple Watch.
• Apple Health export. Push your imported TCX runs back into Health.
• Records. Best half marathon, best marathon, and best splits for 1K through 42.2K, computed across your entire history.
• Dashboard. Total distance, total time, monthly and yearly charts, 30-day pace trend, distribution by distance, and a year-at-a-glance activity heatmap.
• Run detail. Interactive map with pace-colored route, scrubbable timeline, synced charts for pace, elevation, heart rate, and speed, plus per-kilometer splits with relative pace bars.
• Configurable units. Kilometers or miles, km/h or mph, min/km or min/mi, meters or feet.

PRIVATE BY DESIGN

• Apple Health integration. Read your runs, optionally export to Health. Your Health data never leaves your device.
• Private iCloud sync via CloudKit. Only you can see your data, even on Apple's servers.
• No analytics, no advertising, no third-party SDKs. The only network call My Runs makes is Apple's own reverse-geocoder, so we can label your runs with a city name.
• Delete all your data with one tap, including the iCloud copy.

REQUIREMENTS

• iPhone running iOS 17 or later.
• An Apple ID with iCloud Drive enabled for cross-device sync.
• Apple Health permission for workout import/export.

My Runs uses HealthKit to read running workouts, GPS routes, heart rate samples, active energy, and distance, and to write imported runs back as workouts you can see in the Fitness app. All HealthKit data stays on your device.

Built with native SwiftUI, SwiftData, HealthKit, and CloudKit. Zero third-party dependencies. Maintained as an open-source personal project: https://github.com/maximou100/My_Runs
```

---

## Keywords *(max 100 chars, comma-separated, no spaces between commas)*

```
nike,run,club,tcx,gpx,import,strava,workout,marathon,pace,splits,jogging,fitness,tracker
```

---

## App Privacy Details (in App Store Connect → App Privacy)

When you reach the "Data Collection" section, answer:

> **"Do you or your third-party partners collect data from this app?"**
> → **No, we do not collect data from this app.**

This is correct because:
- No data is transmitted to servers operated by you (the developer)
- HealthKit data stays on device per Guideline 5.1.3
- CloudKit syncing uses the **user's private database** under their Apple ID — Apple's [official guidance](https://developer.apple.com/app-store/app-privacy-details/) is that this is **not** considered "collected data" because the developer cannot access it
- Reverse geocoding via `CLGeocoder` is handled by Apple's framework, not by the developer, and contains no user identifier

---

## App Review Information

**Sign-in required?** No.

**Demo account?** Not applicable — there is no login.

**Notes for the reviewer:**

```
My Runs is a personal fitness app for managing imported running data.

How to test:
1. Launch the app. The Dashboard, Runs, Records, and Health tabs will be empty.
2. To populate data, you can either:
   a) Tap the Import tab → tap the import button → select one or more TCX/GPX files from Files. A sample TCX file is attached for convenience.
   b) Tap the Health tab → connect to Apple Health → tap "Import Workouts" to pull any existing running workouts.
3. After import, browse Dashboard, Runs (tap a run for the detail view), and Records.
4. In Settings, you can switch units and delete all data.

Privacy summary:
- HealthKit is used only to read/write running workouts and heart rate. Data never leaves the device.
- SwiftData + CloudKit syncs runs to the user's private iCloud database. The developer cannot access this data.
- There is no third-party network activity. The only outbound call is Apple's reverse geocoder (CLGeocoder).
- No analytics, no tracking, no advertising SDKs.

The app does not use the user's current location and does not request CLLocationManager authorization.
```

---

## Age Rating

Answer **None** to every question in the questionnaire (no objectionable content, no gambling, no unrestricted web). Result: **4+**.

---

## Export Compliance

Already handled in `My-Runs-Info.plist` via `ITSAppUsesNonExemptEncryption = false`. The app only uses Apple's standard system encryption (HTTPS via CloudKit, ATS), which is exempt from export documentation requirements. **No additional declaration needed in App Store Connect.**

---

## What's New (for first submission)

```
First release of My Runs.

• Import your full running history from TCX/GPX files or Apple Health.
• Bulk import handles hundreds of files at once.
• Dashboard, Records, run detail with map and synced charts.
• Configurable units (km/mi, m/ft, etc.).
• Private iCloud sync via CloudKit — only you can see your data.
• Apple Health two-way integration.
• Zero third-party SDKs.
```

---

## Screenshots required

Apple requires screenshots at these sizes. Capture from your iPhone 17 Pro and resize/scale as needed:

- **6.9" Display** (iPhone 16 Pro Max / 17 Pro Max): 1320 × 2868
- **6.5" Display** (iPhone 11 Pro Max, etc.): 1242 × 2688 (can reuse 6.9" if scaled)
- **iPad** (only if you support iPad — not required for iPhone-only)

Suggested screens to capture (in order):
1. Dashboard with stats and charts
2. Run detail with the map
3. Records (race PRs + best splits)
4. Apple Health import screen
5. Settings (showing units & data control)

---

## CloudKit before release

Promote the schema from Development to Production:

1. Visit https://icloud.developer.apple.com
2. Choose container `iCloud.Max-Leclercq.My-Runs`
3. **Schema** → **Development** → click **Deploy Schema Changes...**
4. Move record types `Run`, `Lap`, and `StoredTrackpoints` to **Production**

Without this step, the app will run on TestFlight in dev mode but production users won't sync.
