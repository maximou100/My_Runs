import SwiftUI
import SwiftData
import HealthKit
import CoreLocation

struct HealthView: View {
    @Query(sort: [SortDescriptor(\Run.startTime, order: .reverse)]) private var runs: [Run]
    @Environment(\.modelContext) private var modelContext
    @State private var isConnected = false
    @State private var connectionError: String?

    @State private var isImporting = false
    @State private var importProgress = 0.0
    @State private var importStatus = ""
    @State private var importResult: (imported: Int, skipped: Int, errors: Int)?

    @State private var isSyncing = false
    @State private var syncProgress = 0.0
    @State private var syncCount = 0
    @State private var syncTotal = 0

    private var syncedCount: Int { runs.filter(\.healthKitSynced).count }
    private var unsyncedTCXCount: Int { runs.filter { !$0.healthKitSynced && $0.dataSource == .tcx }.count }
    private var healthKitCount: Int { runs.filter { $0.dataSource == .healthKit }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !isConnected {
                        setupCard
                    } else {
                        summaryCard
                        importFromHealthCard
                        if isImporting { importProgressCard }
                        if let r = importResult { importResultCard(r) }
                        exportCard
                        if isSyncing { syncProgressCard }
                    }
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Health")
        }
    }

    // MARK: - Setup

    private var setupCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.system(size: 56))
                .foregroundStyle(.pink)

            Text("Apple Health")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Connect to Apple Health to import runs from Apple Watch and sync your TCX runs as workouts.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                connectToHealth()
            } label: {
                Label("Connect to Apple Health", systemImage: "heart.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)

            if let error = connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Apple Health", systemImage: "heart.fill")
                .font(.headline).foregroundStyle(.white)

            HStack(spacing: 24) {
                summaryPill("\(runs.count)", label: "Total", color: .white)
                summaryPill("\(healthKitCount)", label: "From Health", color: .pink)
                summaryPill("\(syncedCount)", label: "Exported", color: Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func summaryPill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Import from Health

    private var importFromHealthCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from Apple Health")
                        .font(.headline).foregroundStyle(.white)
                    Text("Pull running workouts with GPS routes from Apple Watch and Fitness.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                importFromHealth()
            } label: {
                Label("Import Workouts", systemImage: "arrow.down.heart.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .disabled(isImporting)
        }
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var importProgressCard: some View {
        VStack(spacing: 8) {
            ProgressView(value: importProgress) {
                Text(importStatus)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .tint(.pink)
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func importResultCard(_ r: (imported: Int, skipped: Int, errors: Int)) -> some View {
        VStack(spacing: 8) {
            if r.imported > 0 {
                Label("\(r.imported) workouts imported", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.pink)
            }
            if r.skipped > 0 {
                Label("\(r.skipped) duplicates skipped", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(.orange)
            }
            if r.errors > 0 {
                Label("\(r.errors) workouts failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Theme.danger)
            }
            if r.imported == 0 && r.skipped > 0 && r.errors == 0 {
                Text("All workouts already imported.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Export to Health

    private var exportCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export TCX Runs to Health")
                        .font(.headline).foregroundStyle(.white)
                    Text("\(unsyncedTCXCount) TCX runs not yet exported.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                syncAllRuns()
            } label: {
                Label("Export All", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isSyncing || unsyncedTCXCount == 0)

            if unsyncedTCXCount == 0 && !runs.isEmpty {
                Label("All TCX runs exported!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(20)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var syncProgressCard: some View {
        VStack(spacing: 8) {
            ProgressView(value: syncProgress) {
                Text("Exporting \(syncCount) of \(syncTotal)...")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .tint(Theme.accent)
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Actions

    private func connectToHealth() {
        connectionError = nil
        let service = HealthKitService.shared
        guard service.isAvailable else {
            connectionError = "HealthKit is not available on this device."
            return
        }
        Task {
            do {
                try await service.requestAuthorization()
                isConnected = true
                Haptics.notification(.success)
            } catch {
                connectionError = "Could not connect. Make sure the HealthKit capability is added in Xcode, then rebuild the app."
            }
        }
    }

    // MARK: - Import from Health

    private func importFromHealth() {
        isImporting = true
        importProgress = 0
        importStatus = "Fetching workouts..."
        importResult = nil

        Task {
            do {
                let workouts = try await HealthKitService.shared.fetchRunningWorkouts()

                guard !workouts.isEmpty else {
                    importStatus = ""
                    isImporting = false
                    importResult = (0, 0, 0)
                    return
                }

                let existingStartTimes = runs.map { $0.startTime }
                var toImport: [HKWorkout] = []
                var skipped = 0

                for workout in workouts {
                    let isDuplicate = existingStartTimes.contains {
                        abs($0.timeIntervalSince(workout.startDate)) < 60
                    }
                    if isDuplicate { skipped += 1 }
                    else { toImport.append(workout) }
                }

                guard !toImport.isEmpty else {
                    importStatus = ""
                    isImporting = false
                    importResult = (0, skipped, 0)
                    return
                }

                var imported = 0
                var errors = 0
                let total = toImport.count

                for (index, workout) in toImport.enumerated() {
                    importProgress = Double(index) / Double(total)
                    importStatus = "Importing \(index + 1) of \(total)..."

                    do {
                        try await importWorkout(workout)
                        imported += 1
                    } catch {
                        errors += 1
                    }
                }

                importProgress = 1.0
                importStatus = ""
                isImporting = false
                importResult = (imported, skipped, errors)
                if imported > 0 {
                    Haptics.notification(.success)
                    TrackpointStore.clearSplitsCache()
                    geocodeNewRuns()
                }
            } catch {
                importStatus = ""
                isImporting = false
                importResult = (0, 0, 1)
            }
        }
    }

    private func importWorkout(_ workout: HKWorkout) async throws {
        let distanceM = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
        let durationS = workout.duration
        let calories = Int(workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)

        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        let hrStats = workout.statistics(for: HKQuantityType(.heartRate))
        let avgHR = hrStats?.averageQuantity()?.doubleValue(for: hrUnit)
        let maxHR = hrStats?.maximumQuantity()?.doubleValue(for: hrUnit)

        let avgPace = distanceM > 0 && durationS > 0
            ? (durationS / 60) / (distanceM / 1000) : 0.0

        var locations: [CLLocation] = []
        do {
            locations = try await HealthKitService.shared.fetchRouteLocations(for: workout)
        } catch {}

        var startLat = 0.0, startLng = 0.0
        var elevGain = 0.0, elevLoss = 0.0
        var maxSpeed = 0.0
        var trackpoints: [TrackpointData] = []

        if !locations.isEmpty {
            startLat = locations[0].coordinate.latitude
            startLng = locations[0].coordinate.longitude

            var cumulativeDistance = 0.0
            var previousLocation: CLLocation?

            for loc in locations {
                if let prev = previousLocation {
                    cumulativeDistance += loc.distance(from: prev)
                    let diff = loc.altitude - prev.altitude
                    if diff > 0 { elevGain += diff }
                    else { elevLoss += abs(diff) }
                }
                if loc.speed > maxSpeed { maxSpeed = loc.speed }

                trackpoints.append(TrackpointData(
                    time: loc.timestamp,
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude,
                    altitudeM: loc.altitude,
                    distanceM: cumulativeDistance,
                    heartRate: nil,
                    speedMps: loc.speed >= 0 ? loc.speed : nil
                ))
                previousLocation = loc
            }
        }

        let runId = UUID()
        let run = Run(
            id: runId,
            fileName: "health_\(workout.uuid.uuidString)",
            sport: "Running",
            startTime: workout.startDate,
            totalDistanceM: distanceM,
            totalTimeS: durationS,
            calories: calories,
            avgPaceMinPerKm: avgPace,
            maxSpeedMps: maxSpeed,
            elevationGainM: elevGain,
            elevationLossM: elevLoss,
            startLat: startLat,
            startLng: startLng,
            category: RunCategory.from(distanceM: distanceM),
            avgHeartRate: avgHR.map { Int($0) },
            maxHeartRate: maxHR.map { Int($0) },
            healthKitSynced: true,
            dataSource: .healthKit
        )
        modelContext.insert(run)

        if !trackpoints.isEmpty {
            let pts = trackpoints
            let id = runId
            if let blob = try? JSONEncoder().encode(pts) {
                modelContext.insert(StoredTrackpoints(runId: id, data: blob))
            }
            Task.detached { TrackpointStore.saveTrackpoints(runId: id, trackpoints: pts) }
        }
        try? modelContext.save()
    }

    // MARK: - Export to Health

    private func syncAllRuns() {
        let unsynced = runs.filter { !$0.healthKitSynced && $0.dataSource == .tcx }
        guard !unsynced.isEmpty else { return }
        isSyncing = true
        syncTotal = unsynced.count
        syncCount = 0
        syncProgress = 0

        Task {
            for run in unsynced {
                do {
                    try await HealthKitService.shared.syncRun(run)
                    run.healthKitSynced = true
                } catch {}
                syncCount += 1
                syncProgress = Double(syncCount) / Double(syncTotal)
            }
            try? modelContext.save()
            isSyncing = false
            Haptics.notification(.success)
        }
    }

    // MARK: - Geocoding

    private func geocodeNewRuns() {
        let ungeocodedRuns = runs.filter { $0.city == nil && $0.startLat != 0 && $0.startLng != 0 }
        guard !ungeocodedRuns.isEmpty else { return }

        let items = ungeocodedRuns.map { (id: $0.id, lat: $0.startLat, lng: $0.startLng) }
        let runLookup = Dictionary(uniqueKeysWithValues: ungeocodedRuns.map { ($0.id, $0) })

        Task {
            for item in items {
                let result = await GeocodingService.shared.reverseGeocode(lat: item.lat, lng: item.lng)
                if let run = runLookup[item.id] {
                    run.city = result.city
                    run.country = result.country
                    run.countryCode = result.countryCode
                }
            }
            try? modelContext.save()
        }
    }
}
