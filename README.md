# My Runs

A personal running tracker for iOS that pulls your historical runs from Strava, Apple Health, and your own activity files (`.tcx`, `.gpx`, `.fit`), then turns them into a fast, beautiful dashboard you actually want to open.

Built natively in SwiftUI + SwiftData for iOS 17+, with CloudKit sync across devices, full Apple Health integration, and zero third-party dependencies.

---

## Features

### Run management
- **Direct Strava sync** — connect your account once via OAuth, then one tap pulls all your Run / TrailRun / VirtualRun activities with GPS streams, heart rate, and elevation
- **Multi-format file import** — `.tcx`, `.gpx`, and `.fit` files import natively (no third-party conversion). Works with exports from Garmin Connect, Runkeeper, Nike Run Club, Strava bulk archives, and most other fitness platforms
- **In-app setup guides** — built-in tutorials for Strava API setup, Garmin Connect exports, and Runkeeper exports, with clickable links to the right pages
- **Apple Health import** — pull running workouts (with GPS routes) from Apple Watch and the Fitness app
- **Apple Health export** — push your imported runs back into Health as proper workouts
- **Per-run data source badges** so you always know where a run came from (TCX, Strava, Apple Health)

### Insights
- **Dashboard** — total distance, total time, calories, country count, monthly/yearly distance chart, 30-day pace trend, distance distribution, day-of-week breakdown, GitHub-style activity heatmap
- **Records** — best half marathon, best marathon, best splits for 1K/5K/10K/15K/21.1K/42.2K computed across every run, plus longest run, longest duration, most elevation, fastest pace, most calories
- **Run detail** — interactive map with pace-colored polylines, scrubbable timeline, synced charts for pace, elevation, heart rate (from Health if needed), and speed, plus per-km splits with relative pace bars

### Personalization
- **Configurable units** — km/miles, km/h or mph, min/km or min/mi, meters or feet
- **Reverse geocoding** — city and country attached to every run, with flag emoji
- **Light haptics** throughout

### Data and privacy
- **CloudKit sync** — runs, laps, and trackpoint blobs sync to your private iCloud database; new devices restore automatically
- **On-device only** — no third-party servers, analytics, or trackers
- **Delete all data** — one-tap data wipe in Settings, including iCloud
- **Privacy Manifest** included (iOS 17+ requirement)

---

## Tech stack

| Layer | Technology |
| --- | --- |
| UI | SwiftUI, Swift Charts, MapKit |
| Persistence | SwiftData (with CloudKit) |
| Health | HealthKit (`HKWorkoutRouteQueryDescriptor`, `HKQuantityType` heart rate samples) |
| Location | CoreLocation (`CLGeocoder`, no authorization required) |
| Strava | `ASWebAuthenticationSession` OAuth + Keychain-stored tokens + Strava v3 REST + streams API |
| Parsing | Custom XMLParser-based parsers for TCX and GPX, plus a from-scratch binary parser for Garmin's `.fit` protocol |
| Concurrency | Swift `async/await`, `TaskGroup`, `Task.detached`, `nonisolated` types |

No dependencies. No CocoaPods. No Swift Package Manager. Just Apple frameworks.

---

## Project layout

```
My_Runs/
├── My_RunsApp.swift          App entry, ModelContainer + CloudKit config
├── ContentView.swift         TabView root
├── Models.swift              Run, Lap, StoredTrackpoints, TrackpointData
├── DashboardView.swift       KPIs and charts (Settings gear in the toolbar)
├── RunsView.swift            Filterable list of runs
├── RunDetailView.swift       Map, charts, splits, playback
├── RecordsView.swift         Race PRs and best splits
├── HealthView.swift          Apple Health import / export
├── ImportView.swift          File picker + import flow + Strava/Garmin/Runkeeper cards
├── ImportGuides.swift        In-app tutorial sheets: Strava setup, Garmin, Runkeeper
├── StravaService.swift       Strava OAuth, token refresh, activities + streams API
├── SettingsView.swift        Units + delete-all-data
├── TCXParser.swift           Streaming TCX → TrackpointData
├── GPXParser.swift           Streaming GPX → TrackpointData (Haversine distance)
├── FITParser.swift           Binary Garmin FIT protocol parser
├── TrackpointStore.swift     Disk + cloud cache for trackpoint blobs
├── HealthKitService.swift    HK auth, workouts, routes, HR samples
├── GeocodingService.swift    CLGeocoder wrapper with caching
├── Formatters.swift          Unit-aware number/date formatting
├── Theme.swift               Dark-mode design tokens
├── Haptics.swift             Centralized feedback
└── PrivacyInfo.xcprivacy     UserDefaults API declaration
```

---

## Running it locally

### Requirements
- macOS with **Xcode 16+**
- An **iPhone with iOS 17+** (recommended: iOS 26 / iPhone 17 Pro)
- A **paid Apple Developer account** (required for iCloud + HealthKit capabilities; the free Personal team cannot ship apps with these)

### Setup
1. Clone the repo:
   ```bash
   git clone https://github.com/maximou100/My_Runs.git
   ```
2. Open `My_Runs.xcodeproj` in Xcode.
3. In **Signing & Capabilities**:
   - Select your **paid** developer team
   - Confirm **HealthKit**, **iCloud (CloudKit)** with container `iCloud.<your-bundle-id>`, and **Background Modes (Remote notifications)** are all present
4. Update the bundle identifier and CloudKit container ID to your own if you're forking
5. Build and run on a real device (HealthKit features don't work in the simulator)

### First launch
- Grant Apple Health permission
- Either import TCX files via the **Import** tab, or pull workouts from the **Health** tab
- Sit back while reverse geocoding fills in the city/country for each run

---

## Privacy

This app does not transmit any data to third-party servers. All run data is stored:
1. **Locally** in SwiftData and the Documents directory (TCX/JSON caches)
2. **In your private iCloud database** via CloudKit, accessible only to you across your own devices

HealthKit data never leaves the device for any purpose other than user-initiated import/export to Apple Health on the same device. There is no analytics, no tracking, no advertising SDK, and no remote logging.

The Privacy Manifest at `My_Runs/PrivacyInfo.xcprivacy` declares the single non-trivial API used (`UserDefaults`, reason `CA92.1`).

---

## App Store status

This project is being prepared for App Store submission. Compliance items addressed in code:

- HealthKit usage descriptions (`NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`)
- Privacy Manifest (`PrivacyInfo.xcprivacy`)
- User-facing data deletion (Settings → Data → Delete All Data)
- Display name (`My Runs` via `CFBundleDisplayName`)
- Encryption export declaration is straightforward — only standard system encryption is used

Items to complete in App Store Connect before submission:
- Privacy policy URL (required for any HealthKit app)
- App Privacy Details: Health & Fitness + Coarse Location, linked to user, app functionality, no tracking
- App description must mention HealthKit
- CloudKit schema: promote dev → production

---

## Changelog

### v1.1

**Import sources**
- **Strava direct sync** via OAuth (`ASWebAuthenticationSession`), tokens stored in Keychain with automatic refresh. One tap pulls Run / TrailRun / VirtualRun activities, downloads GPS streams, and dedups on re-sync.
- **In-app Strava setup tutorial** — 4-step walkthrough with a clickable link to `strava.com/settings/api`. Users can paste their own Client ID / Secret (stored in Keychain) to get a private rate-limit pool; bundled credentials remain as a fallback.
- **Garmin Connect guide** — three documented paths: Apple Health bridge, single-activity export, bulk archive request.
- **Runkeeper guide** — single-activity and bulk export documented.

**File format support**
- **`.gpx` parser** — XML-based, Haversine distance computation, namespace-aware element matching, GPX TrackPointExtension support (heart rate, speed).
- **`.fit` parser** — binary Garmin FIT protocol implemented from scratch: header validation, definition + data messages, all base types with invalid-sentinel handling, semicircles-to-degrees, FIT-epoch timestamps. Handles `file_id`, `record`, `lap`, `session`, `activity` messages.
- **Unified import pipeline** — `ImportView` dispatches by extension; `.tcx` files save raw bytes (re-parseable), `.gpx` / `.fit` save normalized trackpoints as JSON.

**Data & UI**
- New `DataSource.strava` case with an orange `figure.run` badge in the runs list.
- Strava sync card in the Import tab with Connect / Sync / Disconnect states.
- Settings moved from tab bar to a gear button on the Dashboard toolbar.
- URL scheme `myruns://` registered for OAuth callbacks.

**Reliability**
- Improved Strava error reporting: captures response body, dedicated handling for 401 (re-auth) and 429 (rate-limit).
- Target narrowed to iPhone (`TARGETED_DEVICE_FAMILY=1`).

### v1.0

- TCX file import (Nike Run Club, Garmin TCX exports)
- Apple Health import (workouts, GPS routes, heart rate samples) and export
- Dashboard, Records, Run Detail, Runs list
- CloudKit sync across devices
- Reverse geocoding (city + country)
- Configurable units (km/miles, pace, elevation)
- Privacy Manifest, HealthKit usage descriptions, Settings → Delete All Data
- App Store assets: privacy policy, GitHub Pages site, listing copy

---

## License

Personal project. Not currently licensed for redistribution.

---

## Acknowledgements

- TCX format reverse-engineered from Garmin and Nike Run Club exports
- Charts via [Swift Charts](https://developer.apple.com/documentation/charts)
- Icon: custom design


<img width="603" height="1311" alt="IMG_1622" src="https://github.com/user-attachments/assets/5acd7c20-ca03-4bd4-a933-793f4c71a9df" />
<img width="603" height="1311" alt="IMG_1621" src="https://github.com/user-attachments/assets/5743d8c1-e5ff-431f-b40f-e57c3e4b3425" />
<img width="603" height="1311" alt="IMG_1620" src="https://github.com/user-attachments/assets/bbd53de7-ae1c-4ada-ab7e-53d71f0de098" />
<img width="603" height="1311" alt="IMG_1619" src="https://github.com/user-attachments/assets/b252bc69-1c06-4704-baac-945e5cb847ab" />
<img width="603" height="1311" alt="IMG_1618" src="https://github.com/user-attachments/assets/af124d7c-41f2-4d74-b23e-a753d9aafbd2" />
<img width="603" height="1311" alt="IMG_1617" src="https://github.com/user-attachments/assets/8f1e58c3-e26a-4f1a-8788-538d685767cb" />
<img width="603" height="1311" alt="IMG_1616" src="https://github.com/user-attachments/assets/3a7ace00-5f16-4d91-a756-59b6d8676b3c" />
<img width="603" height="1311" alt="IMG_1615" src="https://github.com/user-attachments/assets/bf3bb2bb-1826-4070-b428-603fc8641ba3" />
