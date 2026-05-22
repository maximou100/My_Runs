import SwiftUI

// MARK: - Shared step component

struct GuideStep<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                content()
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct GuideCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}

private struct WarningBox: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Strava setup

struct StravaSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var clientID = StravaService.customClientID
    @State private var clientSecret = StravaService.customClientSecret
    @State private var saved = false

    private var usingDefaults: Bool { !StravaService.hasCustomCredentials }
    private var canSave: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    intro
                    rateLimitWarning
                    tutorial
                    credentialsCard
                    backupCard
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Strava Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var intro: some View {
        GuideCard {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color(hex: "fc5200"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect to Strava")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Strava limits how many requests an app can make. For best results, register your own free Strava API app — it takes about 2 minutes and gives you a private rate-limit pool.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var rateLimitWarning: some View {
        WarningBox(
            title: "Strava API rate limits",
            message: "Strava allows ~100 requests every 15 minutes and 1,000 per day per app. If many users share the default app, syncs may fail until the limit resets. Registering your own credentials avoids this entirely."
        )
    }

    private var tutorial: some View {
        GuideCard {
            Text("Register your own Strava app")
                .font(.headline)
                .foregroundStyle(.white)

            GuideStep(number: 1, title: "Open Strava API settings") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sign in to Strava and open the developer page.")
                    Link(destination: URL(string: "https://www.strava.com/settings/api")!) {
                        Label("strava.com/settings/api", systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            GuideStep(number: 2, title: "Create an API application") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use any values for name/website. The one field that matters:")
                    Text("Authorization Callback Domain: myruns")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            GuideStep(number: 3, title: "Copy your credentials") {
                Text("Once created, Strava shows your Client ID (a number) and Client Secret (a long string). Click \"Show\" to reveal the secret.")
            }

            GuideStep(number: 4, title: "Paste them below") {
                Text("Tap Save. Your credentials are stored securely in the iOS Keychain.")
            }
        }
    }

    private var credentialsCard: some View {
        GuideCard {
            HStack {
                Text("Your credentials")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if !usingDefaults {
                    Text("Custom")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                } else {
                    Text("Using shared default")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Client ID")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                TextField("e.g. 123456", text: $clientID)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Client Secret")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                SecureField("40-character secret", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                Button {
                    StravaService.setCustomCredentials(
                        clientID: clientID.trimmingCharacters(in: .whitespaces),
                        clientSecret: clientSecret.trimmingCharacters(in: .whitespaces)
                    )
                    saved = true
                    Haptics.notification(.success)
                } label: {
                    Label(saved ? "Saved" : "Save",
                          systemImage: saved ? "checkmark.circle.fill" : "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
                .disabled(!canSave)

                if !usingDefaults {
                    Button(role: .destructive) {
                        StravaService.clearCustomCredentials()
                        clientID = ""
                        clientSecret = ""
                        saved = false
                    } label: {
                        Text("Reset")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.danger)
                }
            }
            .onChange(of: clientID) { _, _ in saved = false }
            .onChange(of: clientSecret) { _, _ in saved = false }
        }
    }

    private var backupCard: some View {
        GuideCard {
            Label("Backup option: export TCX from Strava", systemImage: "tray.and.arrow.down")
                .font(.headline)
                .foregroundStyle(.white)

            Text("If you'd rather not use the API at all, you can download every activity as a file:")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            GuideStep(number: 1, title: "Request your archive") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On a computer, sign in to Strava and request a bulk export.")
                    Link(destination: URL(string: "https://www.strava.com/athlete/delete_your_account")!) {
                        Label("Strava → Settings → My Account → Download Request", systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            GuideStep(number: 2, title: "Download the archive") {
                Text("Strava emails a link within a few hours. The .zip contains an `activities/` folder with one file per run.")
            }

            GuideStep(number: 3, title: "Import the files") {
                Text("Activities are stored as .gpx, .tcx, or .fit depending on the source. My Runs reads all three formats natively. Move them to your iPhone (AirDrop / Files / iCloud Drive) and tap \"Select Files\" on the Import tab.")
            }
        }
    }
}

// MARK: - Garmin Connect guide

struct GarminGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    intro
                    warning
                    option1
                    option2
                    option3
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Garmin Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var intro: some View {
        GuideCard {
            HStack(spacing: 12) {
                Image(systemName: "applewatch.side.right")
                    .font(.system(size: 30))
                    .foregroundStyle(Color(hex: "007cc3"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Garmin Connect")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Garmin doesn't offer a public API for personal apps. There are three reliable ways to get your runs into My Runs.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var warning: some View {
        WarningBox(
            title: "No direct sync available",
            message: "Garmin's Connect IQ / Activity APIs are gated behind a business partnership and not available for personal use. The methods below are the official, supported paths."
        )
    }

    private var option1: some View {
        GuideCard {
            Label("Option 1 — Sync via Apple Health (easiest)", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Garmin Connect can mirror your activities to Apple Health automatically. My Runs already imports from Apple Health (Health tab).")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            GuideStep(number: 1, title: "Open Garmin Connect on your iPhone") {
                Text("The mobile app, not the web site.")
            }

            GuideStep(number: 2, title: "More → Settings → Connected Apps → Apple Health") {
                Text("Tap \"Connect to Apple Health\" and grant access to Workouts and Routes.")
            }

            GuideStep(number: 3, title: "Open the Health tab in My Runs") {
                Text("Once Garmin syncs, your runs appear in Apple Health and My Runs can import them with one tap.")
            }
        }
    }

    private var option2: some View {
        GuideCard {
            Label("Option 2 — Export a single activity (TCX)", systemImage: "doc.badge.arrow.up")
                .font(.headline)
                .foregroundStyle(.white)

            GuideStep(number: 1, title: "Open the activity on the web") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On a computer, sign in to Garmin Connect.")
                    Link(destination: URL(string: "https://connect.garmin.com/modern/activities")!) {
                        Label("connect.garmin.com → Activities", systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            GuideStep(number: 2, title: "Open the ⋯ menu") {
                Text("Top-right of the activity page. Choose \"Export to TCX\", \"Export to GPX\", or \"Export Original\" — My Runs reads all three formats.")
            }

            GuideStep(number: 3, title: "Move the file to your iPhone") {
                Text("AirDrop, iCloud Drive, or email the file to yourself.")
            }

            GuideStep(number: 4, title: "Tap \"Select Files\" in My Runs") {
                Text("Pick the .tcx, .gpx, or .fit file. It imports through the standard flow.")
            }
        }
    }

    private var option3: some View {
        GuideCard {
            Label("Option 3 — Bulk export everything", systemImage: "archivebox")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Useful for a one-time migration. Garmin emails you a download link, usually within a few days.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            GuideStep(number: 1, title: "Open Account Management") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sign in on the web, then open:")
                    Link(destination: URL(string: "https://www.garmin.com/account/datamanagement/exportdata/")!) {
                        Label("Garmin Account → Export Your Data", systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            GuideStep(number: 2, title: "Request your data") {
                Text("Confirm the request. Garmin processes it in the background.")
            }

            GuideStep(number: 3, title: "Download & extract the .zip") {
                Text("When it arrives by email, unzip and look for the `DI_CONNECT/DI-Connect-Fitness` folder. Activities are .fit files.")
            }

            GuideStep(number: 4, title: "Import the .fit files") {
                Text("Transfer the files to your iPhone (AirDrop / Files / iCloud Drive) and tap \"Select Files\" in My Runs. .fit files import directly — no conversion needed.")
            }
        }
    }
}

// MARK: - Runkeeper guide

struct RunkeeperGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    intro
                    warning
                    option1
                    option2
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Runkeeper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var intro: some View {
        GuideCard {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 30))
                    .foregroundStyle(Color(hex: "00a6d6"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runkeeper / ASICS Runkeeper")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Runkeeper no longer accepts new API developers. You can still bring your runs across by exporting them as files.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var warning: some View {
        WarningBox(
            title: "Runkeeper exports as GPX",
            message: "Runkeeper exports activities as .gpx. My Runs reads .gpx files natively — no conversion needed."
        )
    }

    private var option1: some View {
        GuideCard {
            Label("Option 1 — Export a single activity", systemImage: "doc.badge.arrow.up")
                .font(.headline)
                .foregroundStyle(.white)

            GuideStep(number: 1, title: "Open the activity on the web") {
                VStack(alignment: .leading, spacing: 6) {
                    Link(destination: URL(string: "https://runkeeper.com/user")!) {
                        Label("runkeeper.com → Me → Activities", systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            GuideStep(number: 2, title: "Tap the export icon") {
                Text("Each activity has a download icon — choose GPX.")
            }

            GuideStep(number: 3, title: "Move the file to your iPhone") {
                Text("AirDrop, iCloud Drive, or email the .gpx file to yourself.")
            }

            GuideStep(number: 4, title: "Import in My Runs") {
                Text("Tap \"Select Files\" on the Import tab and pick the .gpx file.")
            }
        }
    }

    private var option2: some View {
        GuideCard {
            Label("Option 2 — Export your entire history", systemImage: "archivebox")
                .font(.headline)
                .foregroundStyle(.white)

            GuideStep(number: 1, title: "Open Account Settings") {
                VStack(alignment: .leading, spacing: 6) {
                    Link(destination: URL(string: "https://runkeeper.com/settings")!) {
                        Label("runkeeper.com → Settings", systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            GuideStep(number: 2, title: "Export Data") {
                Text("Scroll to \"Export Data\". Enter your email and request the archive.")
            }

            GuideStep(number: 3, title: "Wait for the email") {
                Text("Usually arrives within a few hours. You'll get a .zip with one .gpx per activity.")
            }

            GuideStep(number: 4, title: "Import the files") {
                Text("Transfer the .gpx files to your iPhone and tap \"Select Files\" in My Runs. They import natively — no conversion needed.")
            }
        }
    }
}
