import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var runs: [Run]
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var importProgress = 0.0
    @State private var importStatus = ""
    @State private var isGeocoding = false
    @State private var geocodeStatus = ""
    @State private var showClearConfirm = false
    @State private var lastResult: (imported: Int, skipped: Int, errors: Int)?

    @State private var stravaConnected = StravaService.shared.isConnected
    @State private var stravaSyncing = false
    @State private var stravaStatus = ""
    @State private var stravaError: String?

    @State private var showStravaSetup = false
    @State private var showGarminGuide = false
    @State private var showRunkeeperGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    importCard
                    stravaCard
                    garminCard
                    runkeeperCard
                    if isImporting { progressCard }
                    if isGeocoding { geocodingCard }
                    if let r = lastResult { resultCard(r) }
                    if !runs.isEmpty { libraryCard }
                    dangerCard
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .alert("Clear All Data", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) { clearAllData() }
            } message: {
                Text("This will permanently delete all \(runs.count) imported runs.")
            }
            .sheet(isPresented: $showStravaSetup) {
                StravaSetupView()
            }
            .sheet(isPresented: $showGarminGuide) {
                GarminGuideView()
            }
            .sheet(isPresented: $showRunkeeperGuide) {
                RunkeeperGuideView()
            }
        }
    }

    // MARK: - Cards

    private var importCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Import Activity Files")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Import .tcx, .gpx, or .fit files exported from Nike+ Run Club, Garmin, Runkeeper, Strava, or other fitness apps.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showImporter = true
            } label: {
                Label("Select Files", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isImporting)
        }
        .padding(24)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var stravaCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(hex: "fc5200"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strava")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(stravaConnected ? "Connected" : "Sync runs directly from your account")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    showStravaSetup = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
            }

            if stravaConnected {
                Button {
                    syncStrava()
                } label: {
                    Label(stravaSyncing ? "Syncing…" : "Sync from Strava",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "fc5200"))
                .disabled(stravaSyncing || isImporting)

                Button(role: .destructive) {
                    StravaService.shared.disconnect()
                    stravaConnected = false
                    stravaStatus = ""
                } label: {
                    Text("Disconnect")
                        .font(.caption)
                }
                .disabled(stravaSyncing)
            } else {
                Button {
                    connectStrava()
                } label: {
                    Label("Connect Strava", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "fc5200"))
                .disabled(stravaSyncing)

                Button {
                    showStravaSetup = true
                } label: {
                    Text("How to set up your own API credentials")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            if !stravaStatus.isEmpty {
                HStack(spacing: 8) {
                    if stravaSyncing { ProgressView().tint(Theme.accent) }
                    Text(stravaStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }
            if let err = stravaError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var garminCard: some View {
        sourceGuideCard(
            iconName: "applewatch.side.right",
            iconColor: Color(hex: "007cc3"),
            title: "Garmin Connect",
            subtitle: "No direct API — import via Apple Health or .tcx export."
        ) { showGarminGuide = true }
    }

    private var runkeeperCard: some View {
        sourceGuideCard(
            iconName: "figure.run",
            iconColor: Color(hex: "00a6d6"),
            title: "Runkeeper",
            subtitle: "Public API closed. Export your activities and import as .tcx."
        ) { showRunkeeperGuide = true }
    }

    private func sourceGuideCard(iconName: String, iconColor: Color,
                                 title: String, subtitle: String,
                                 action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 30))
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            Button {
                action()
            } label: {
                Label("How to import", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(iconColor)
        }
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var progressCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: importProgress) {
                Text(importStatus)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .tint(Theme.accent)
        }
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var geocodingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.accent)
            Text(geocodeStatus)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func resultCard(_ r: (imported: Int, skipped: Int, errors: Int)) -> some View {
        VStack(spacing: 8) {
            if r.imported > 0 {
                Label("\(r.imported) runs imported", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            if r.skipped > 0 {
                Label("\(r.skipped) duplicates skipped", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(.orange)
            }
            if r.errors > 0 {
                Label("\(r.errors) files failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Theme.danger)
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Library", systemImage: "books.vertical.fill")
                .font(.headline)
                .foregroundStyle(.white)

            let countries = Set(runs.compactMap { $0.countryCode })
            let totalKm = runs.reduce(0.0) { $0 + $1.totalDistanceM } / 1000

            HStack(spacing: 24) {
                statPill(value: "\(runs.count)", label: "runs")
                statPill(value: String(format: "%.0f km", totalKm), label: "total")
                statPill(value: "\(countries.count)", label: "countries")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var dangerCard: some View {
        VStack(spacing: 12) {
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Clear All Data", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(Theme.danger)
            .disabled(runs.isEmpty || isImporting)
        }
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Import Logic

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let supported = urls.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            guard !supported.isEmpty else {
                importStatus = "No supported files selected (.tcx, .gpx, .fit)."
                return
            }
            lastResult = nil
            isImporting = true
            importFiles(supported)
        case .failure:
            importStatus = "Could not access files."
        }
    }

    private static let supportedExtensions: Set<String> = ["tcx", "xml", "gpx", "fit"]

    private func importFiles(_ urls: [URL]) {
        let existingNames = Set(runs.map { $0.fileName })

        var toImport: [(url: URL, fileName: String, ext: String)] = []
        var skippedCount = 0
        for url in urls {
            let fileName = url.lastPathComponent
            if existingNames.contains(fileName) {
                skippedCount += 1
            } else {
                toImport.append((url, fileName, url.pathExtension.lowercased()))
            }
        }

        guard !toImport.isEmpty else {
            isImporting = false
            lastResult = (0, skippedCount, 0)
            return
        }

        Task {
            var imported = 0
            var errors = 0
            let total = toImport.count

            for (index, item) in toImport.enumerated() {
                importProgress = Double(index) / Double(total)
                importStatus = "Importing \(index + 1) of \(total)..."

                let url = item.url
                let ext = item.ext
                let parsed = await Task.detached { () -> ParsedFile? in
                    guard url.startAccessingSecurityScopedResource() else { return nil }
                    defer { url.stopAccessingSecurityScopedResource() }

                    var fileData: Data?
                    autoreleasepool { fileData = try? Data(contentsOf: url) }
                    guard let data = fileData, !data.isEmpty else { return nil }

                    return Self.parseFile(data: data, ext: ext)
                }.value

                guard let parsed else {
                    errors += 1; continue
                }

                let runId = UUID()
                let run = makeRun(id: runId, fileName: item.fileName, summary: parsed.summary)
                modelContext.insert(run)

                if (index + 1) % 20 == 0 || index == total - 1 {
                    try? modelContext.save()
                }

                switch parsed.save {
                case .rawTCX(let data):
                    Task.detached { TrackpointStore.saveRawTCX(runId: runId, data: data) }
                case .trackpoints(let points):
                    Task.detached { TrackpointStore.saveTrackpoints(runId: runId, trackpoints: points) }
                }

                imported += 1
            }

            importProgress = 1.0
            importStatus = ""
            isImporting = false
            lastResult = (imported, skippedCount, errors)
            if imported > 0 { Haptics.notification(.success) }
            geocodeNewRuns()
        }
    }

    private struct ParsedSummary: Sendable {
        let sport: String
        let startTime: Date
        let laps: [TCXParserService.ParsedLap]
        let totalDistanceM: Double
        let totalTimeS: Double
        let totalCalories: Int
        let avgHeartRate: Int?
        let maxHeartRate: Int?
        let maxSpeedMps: Double
        let elevationGainM: Double
        let elevationLossM: Double
        let firstLat: Double
        let firstLng: Double
    }

    private enum SaveBlob: Sendable {
        case rawTCX(Data)
        case trackpoints([TrackpointData])
    }

    private struct ParsedFile: Sendable {
        let summary: ParsedSummary
        let save: SaveBlob
    }

    nonisolated private static func parseFile(data: Data, ext: String) -> ParsedFile? {
        switch ext {
        case "tcx", "xml":
            guard let r = autoreleasepool(invoking: { TCXParserService().parseLite(data: data) }) else { return nil }
            let summary = ParsedSummary(
                sport: r.sport, startTime: r.startTime, laps: r.laps,
                totalDistanceM: r.totalDistanceM, totalTimeS: r.totalTimeS,
                totalCalories: r.totalCalories,
                avgHeartRate: r.avgHeartRate, maxHeartRate: r.maxHeartRate,
                maxSpeedMps: r.maxSpeedMps,
                elevationGainM: r.elevationGainM, elevationLossM: r.elevationLossM,
                firstLat: r.firstLat, firstLng: r.firstLng
            )
            return ParsedFile(summary: summary, save: .rawTCX(data))
        case "gpx":
            guard let r = autoreleasepool(invoking: { GPXParserService().parseLite(data: data) }) else { return nil }
            let summary = ParsedSummary(
                sport: r.sport, startTime: r.startTime, laps: r.laps,
                totalDistanceM: r.totalDistanceM, totalTimeS: r.totalTimeS,
                totalCalories: r.totalCalories,
                avgHeartRate: r.avgHeartRate, maxHeartRate: r.maxHeartRate,
                maxSpeedMps: r.maxSpeedMps,
                elevationGainM: r.elevationGainM, elevationLossM: r.elevationLossM,
                firstLat: r.firstLat, firstLng: r.firstLng
            )
            return ParsedFile(summary: summary, save: .trackpoints(r.trackpoints))
        case "fit":
            guard let r = autoreleasepool(invoking: { FITParserService().parseLite(data: data) }) else { return nil }
            let summary = ParsedSummary(
                sport: r.sport, startTime: r.startTime, laps: r.laps,
                totalDistanceM: r.totalDistanceM, totalTimeS: r.totalTimeS,
                totalCalories: r.totalCalories,
                avgHeartRate: r.avgHeartRate, maxHeartRate: r.maxHeartRate,
                maxSpeedMps: r.maxSpeedMps,
                elevationGainM: r.elevationGainM, elevationLossM: r.elevationLossM,
                firstLat: r.firstLat, firstLng: r.firstLng
            )
            return ParsedFile(summary: summary, save: .trackpoints(r.trackpoints))
        default:
            return nil
        }
    }

    private func makeRun(id: UUID, fileName: String, summary s: ParsedSummary) -> Run {
        let avgPace = s.totalDistanceM > 0 && s.totalTimeS > 0
            ? (s.totalTimeS / 60) / (s.totalDistanceM / 1000) : 0.0
        let laps = s.laps.map {
            Lap(startTime: $0.startTime, totalTimeS: $0.totalTimeS,
                distanceM: $0.distanceM, calories: $0.calories,
                avgHeartRate: $0.avgHeartRate, maxHeartRate: $0.maxHeartRate)
        }
        return Run(
            id: id,
            fileName: fileName,
            sport: s.sport,
            startTime: s.startTime,
            totalDistanceM: s.totalDistanceM,
            totalTimeS: s.totalTimeS,
            calories: s.totalCalories,
            avgPaceMinPerKm: avgPace,
            maxSpeedMps: s.maxSpeedMps,
            elevationGainM: s.elevationGainM,
            elevationLossM: s.elevationLossM,
            startLat: s.firstLat,
            startLng: s.firstLng,
            category: RunCategory.from(distanceM: s.totalDistanceM),
            avgHeartRate: s.avgHeartRate,
            maxHeartRate: s.maxHeartRate,
            laps: laps
        )
    }

    private func geocodeNewRuns() {
        let ungeocodedRuns = runs.filter { $0.city == nil && $0.startLat != 0 && $0.startLng != 0 }
        guard !ungeocodedRuns.isEmpty else { return }

        isGeocoding = true
        let items = ungeocodedRuns.map { (id: $0.id, lat: $0.startLat, lng: $0.startLng) }
        let runLookup = Dictionary(uniqueKeysWithValues: ungeocodedRuns.map { ($0.id, $0) })

        Task {
            for (index, item) in items.enumerated() {
                geocodeStatus = "Geocoding \(index + 1) of \(items.count)..."
                let result = await GeocodingService.shared.reverseGeocode(lat: item.lat, lng: item.lng)
                if let run = runLookup[item.id] {
                    run.city = result.city
                    run.country = result.country
                    run.countryCode = result.countryCode
                }
                if (index + 1) % 20 == 0 {
                    try? modelContext.save()
                }
            }
            try? modelContext.save()
            isGeocoding = false
            geocodeStatus = ""
        }
    }

    // MARK: - Strava

    private func connectStrava() {
        stravaError = nil
        stravaStatus = "Opening Strava…"
        Task {
            do {
                try await StravaService.shared.connect()
                stravaConnected = true
                stravaStatus = "Connected. Tap Sync to import your runs."
                Haptics.notification(.success)
            } catch StravaService.StravaError.authCancelled {
                stravaStatus = ""
            } catch {
                stravaError = error.localizedDescription
                stravaStatus = ""
            }
        }
    }

    private func syncStrava() {
        stravaError = nil
        stravaSyncing = true
        stravaStatus = "Fetching activity list…"
        lastResult = nil

        Task {
            do {
                let activities = try await StravaService.shared.fetchAllRunActivities { count in
                    stravaStatus = "Found \(count) runs…"
                }

                let existingNames = Set(runs.map { $0.fileName })
                let toImport = activities.filter { !existingNames.contains("strava-\($0.id).json") }

                guard !toImport.isEmpty else {
                    stravaSyncing = false
                    stravaStatus = "All \(activities.count) runs are already imported."
                    return
                }

                var imported = 0
                var errors = 0
                let total = toImport.count

                for (index, activity) in toImport.enumerated() {
                    stravaStatus = "Downloading \(index + 1) of \(total)…"
                    let startTime = StravaService.shared.startDate(for: activity)
                    do {
                        let (points, elevLoss) = try await StravaService.shared.fetchTrackpoints(
                            activityId: activity.id, startTime: startTime
                        )
                        insertStravaRun(activity: activity, startTime: startTime,
                                        trackpoints: points, elevationLossM: elevLoss)
                        imported += 1
                        if (index + 1) % 10 == 0 { try? modelContext.save() }
                    } catch {
                        errors += 1
                    }
                }
                try? modelContext.save()

                stravaSyncing = false
                stravaStatus = ""
                lastResult = (imported, activities.count - toImport.count, errors)
                if imported > 0 { Haptics.notification(.success) }
                geocodeNewRuns()
            } catch {
                stravaSyncing = false
                stravaStatus = ""
                stravaError = error.localizedDescription
            }
        }
    }

    private func insertStravaRun(activity: StravaService.ActivitySummary,
                                 startTime: Date,
                                 trackpoints: [TrackpointData],
                                 elevationLossM: Double) {
        let distanceM = activity.distance
        let timeS = activity.moving_time > 0 ? activity.moving_time : activity.elapsed_time
        let avgPace = (distanceM > 0 && timeS > 0)
            ? (timeS / 60) / (distanceM / 1000)
            : 0

        let startLat = trackpoints.first?.lat ?? activity.start_latlng?.first ?? 0
        let startLng = trackpoints.first?.lng ?? activity.start_latlng?.dropFirst().first ?? 0

        let runId = UUID()
        let synthLap = Lap(
            startTime: startTime,
            totalTimeS: timeS,
            distanceM: distanceM,
            calories: Int(activity.calories ?? 0),
            avgHeartRate: activity.average_heartrate.map { Int($0) },
            maxHeartRate: activity.max_heartrate.map { Int($0) }
        )

        let run = Run(
            id: runId,
            fileName: "strava-\(activity.id).json",
            sport: "Running",
            startTime: startTime,
            totalDistanceM: distanceM,
            totalTimeS: timeS,
            calories: Int(activity.calories ?? 0),
            avgPaceMinPerKm: avgPace,
            maxSpeedMps: activity.max_speed ?? 0,
            elevationGainM: activity.total_elevation_gain ?? 0,
            elevationLossM: elevationLossM,
            startLat: startLat,
            startLng: startLng,
            category: RunCategory.from(distanceM: distanceM),
            avgHeartRate: activity.average_heartrate.map { Int($0) },
            maxHeartRate: activity.max_heartrate.map { Int($0) },
            laps: [synthLap],
            dataSource: .strava
        )
        modelContext.insert(run)

        let captured = trackpoints
        Task.detached { TrackpointStore.saveTrackpoints(runId: runId, trackpoints: captured) }
    }

    private func clearAllData() {
        do {
            try modelContext.delete(model: Run.self)
            try modelContext.delete(model: Lap.self)
            try modelContext.delete(model: StoredTrackpoints.self)
            try modelContext.save()
            TrackpointStore.deleteAll()
            lastResult = nil
            Haptics.notification(.warning)
        } catch {}
    }
}

