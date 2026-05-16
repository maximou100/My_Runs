---
layout: default
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy for My Runs

**Effective date:** 16 May 2026
**Publisher:** Maxime Leclercq
**Contact:** maximou100@gmail.com

This Privacy Policy describes how the **My Runs** iOS application ("the App", "we", "us") handles your information. By using the App you agree to the practices described below.

The short version: **My Runs does not collect, transmit, sell, or share your data with any third party. All your running data stays on your iPhone or inside your own private iCloud account.**

---

## 1. Information the App handles

The App is designed to work with running data that you provide or that already exists on your device. Specifically:

- **Imported run files (TCX, GPX, etc.)** that you select from the Files app
- **Apple Health workouts and GPS routes** that you authorize the App to read
- **Heart rate samples** from Apple Health when you view a run's detail
- **Coarse location data** embedded in your imported runs, used solely for reverse-geocoding the start location into a city and country name (via Apple's on-device CLGeocoder)
- **Your unit preferences** (km/miles, m/ft, etc.), stored locally in `UserDefaults`

The App **does not** access:

- Your current location in real time (no `CLLocationManager` is used)
- Your contacts, photos, microphone, camera, or any other personal data
- Any identifier used for advertising or cross-app tracking

---

## 2. How data is stored

- **On your device.** Run metadata is stored using Apple's SwiftData framework. Trackpoint data (the per-second GPS, altitude and heart rate samples that power the maps and charts) is stored as files in the App's sandboxed Documents directory.
- **In your private iCloud database.** If you are signed in to iCloud and have iCloud Drive enabled, SwiftData automatically replicates your runs to the **private CloudKit database** owned by your Apple ID. This data is only visible to you and only synchronized to your other devices signed in with the same Apple ID. Apple, not the developer, controls this storage.

The App developer has **no access** to your data at any time.

---

## 3. Apple Health (HealthKit)

When you grant Apple Health access, the App may:

- **Read** running workouts, GPS routes, heart rate samples, active energy, and distance from Apple Health, so you can view your existing runs in the App.
- **Write** workouts to Apple Health when you choose to export imported TCX runs.

In accordance with [Apple's App Store Review Guidelines section 5.1.3](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research):

- HealthKit data is **never** transmitted off your device by the App.
- HealthKit data is **never** used for advertising, marketing, or sold to anyone.
- HealthKit data is **never** shared with third parties.

You can revoke Health permissions at any time in **iOS Settings → Health → Data Access & Devices → My Runs**.

---

## 4. Data we do not collect

The App contains **no analytics, telemetry, crash reporting, advertising, or third-party SDKs**. There are no remote servers operated by the developer. Specifically:

- No Google Analytics, Firebase, Mixpanel, or similar tools
- No advertising networks
- No tracking pixels, IDFA usage, or cross-app/cross-site tracking
- No accounts, sign-up forms, or login credentials

---

## 5. Network usage

The only network activity initiated by the App is **reverse geocoding** of your run's starting coordinates via Apple's `CLGeocoder` API, which translates a latitude/longitude into a human-readable city and country name. This request is handled by the operating system, governed by Apple's own privacy practices, and contains only the coordinate — no identifier of you or your device is included.

---

## 6. Your rights and choices

- **Delete all your data at any time** from **Settings → Data → Delete All Data** inside the App. This removes runs, laps, trackpoints, and the local cache from your device. iCloud copies will be deleted on next sync.
- **Revoke Health access** from **iOS Settings → Health → Data Access & Devices → My Runs**.
- **Disable iCloud sync** from **iOS Settings → [Your Name] → iCloud → Apps Using iCloud → My Runs**.
- **Uninstall the App** to remove all local data immediately. iCloud data will remain in your account until you delete it via Settings or until you reset iCloud storage.

---

## 7. Children's privacy

The App is not directed at children under 13 and does not knowingly collect any personal information from children. If you believe a child has used the App, simply uninstall it — no data has been transmitted off the device.

---

## 8. Changes to this policy

This policy may be updated to reflect changes in the App's behavior or in applicable law. The "Effective date" above will be updated when changes are made. Continued use of the App after a change constitutes acceptance of the updated policy.

---

## 9. Contact

For any privacy-related question, please email **maximou100@gmail.com** or open an issue at [github.com/maximou100/My_Runs/issues](https://github.com/maximou100/My_Runs/issues).
