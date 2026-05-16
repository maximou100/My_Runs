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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    importCard
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
        }
    }

    // MARK: - Cards

    private var importCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)

            Text("Import .tcx Files")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Select running data files exported from Nike+ Run Club, Garmin, or other fitness apps.")
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
            let tcxURLs = urls.filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "tcx" || ext == "xml"
            }
            guard !tcxURLs.isEmpty else {
                importStatus = "No .tcx files selected."
                return
            }
            lastResult = nil
            isImporting = true
            importFiles(tcxURLs)
        case .failure:
            importStatus = "Could not access files."
        }
    }

    private func importFiles(_ urls: [URL]) {
        let existingNames = Set(runs.map { $0.fileName })

        var toImport: [(url: URL, fileName: String)] = []
        var skippedCount = 0
        for url in urls {
            let fileName = url.lastPathComponent
            if existingNames.contains(fileName) {
                skippedCount += 1
            } else {
                toImport.append((url, fileName))
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
                let workResult = await Task.detached {
                    guard url.startAccessingSecurityScopedResource() else { return (nil as TCXParserService.LiteResult?, nil as Data?) }
                    defer { url.stopAccessingSecurityScopedResource() }

                    var fileData: Data?
                    autoreleasepool { fileData = try? Data(contentsOf: url) }
                    guard let data = fileData, !data.isEmpty else { return (nil, nil) }

                    let parsed: TCXParserService.LiteResult? = autoreleasepool {
                        let parser = TCXParserService()
                        return parser.parseLite(data: data)
                    }
                    return (parsed, data)
                }.value

                guard let parsed = workResult.0, let data = workResult.1 else {
                    errors += 1; continue
                }

                let avgPace = parsed.totalDistanceM > 0 && parsed.totalTimeS > 0
                    ? (parsed.totalTimeS / 60) / (parsed.totalDistanceM / 1000) : 0.0

                let laps = parsed.laps.map {
                    Lap(startTime: $0.startTime, totalTimeS: $0.totalTimeS,
                        distanceM: $0.distanceM, calories: $0.calories,
                        avgHeartRate: $0.avgHeartRate, maxHeartRate: $0.maxHeartRate)
                }

                let runId = UUID()
                let run = Run(
                    id: runId,
                    fileName: item.fileName,
                    sport: parsed.sport,
                    startTime: parsed.startTime,
                    totalDistanceM: parsed.totalDistanceM,
                    totalTimeS: parsed.totalTimeS,
                    calories: parsed.totalCalories,
                    avgPaceMinPerKm: avgPace,
                    maxSpeedMps: parsed.maxSpeedMps,
                    elevationGainM: parsed.elevationGainM,
                    elevationLossM: parsed.elevationLossM,
                    startLat: parsed.firstLat,
                    startLng: parsed.firstLng,
                    category: RunCategory.from(distanceM: parsed.totalDistanceM),
                    avgHeartRate: parsed.avgHeartRate,
                    maxHeartRate: parsed.maxHeartRate,
                    laps: laps
                )
                modelContext.insert(run)

                if (index + 1) % 20 == 0 || index == total - 1 {
                    try? modelContext.save()
                }

                let capturedData = data
                Task.detached { TrackpointStore.saveRawTCX(runId: runId, data: capturedData) }

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

