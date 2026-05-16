import SwiftUI
import SwiftData

struct RecordsView: View {
    @Query(sort: [SortDescriptor(\Run.startTime, order: .reverse)]) private var runs: [Run]
    @Environment(\.modelContext) private var modelContext
    @State private var bestSplits: [SplitRecord] = []
    @State private var isComputing = false
    @State private var hasComputed = false

    struct SplitRecord: Identifiable {
        let id = UUID()
        let targetName: String
        let targetM: Double
        let timeS: Double
        let paceMinKm: Double
        let runId: UUID
        let date: Date
        let location: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if runs.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 20) {
                        raceRecordsCard
                        bestSplitsCard
                        otherRecordsCard
                    }
                    .padding()
                }
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Records")
            .refreshable {
                await computeSplits()
            }
            .task {
                guard !hasComputed else { return }
                if loadCachedSplits() {
                    hasComputed = true
                } else {
                    await computeSplits()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)
            Text("No Records Yet")
                .font(.title3.bold()).foregroundStyle(.white)
            Text("Import runs to see your personal records.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .padding(60)
    }

    // MARK: - Race Records

    private var raceRecordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Race Records", systemImage: "medal.fill")
                .font(.headline).foregroundStyle(.white)

            let valid = runs.filter { $0.avgPaceMinPerKm >= 3.5 && $0.avgPaceMinPerKm <= 15 }

            if let best = valid.filter({ $0.category == .halfMarathon }).min(by: { $0.totalTimeS < $1.totalTimeS }) {
                raceRow("Best Half Marathon", run: best)
            }
            if let best = valid.filter({ $0.category == .marathon }).min(by: { $0.totalTimeS < $1.totalTimeS }) {
                raceRow("Best Marathon", run: best)
            }

            let raceCategories: [RunCategory] = [.halfMarathon, .marathon]
            if !valid.contains(where: { raceCategories.contains($0.category) }) {
                Text("Complete a half marathon or marathon to see race records.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func raceRow(_ title: String, run: Run) -> some View {
        NavigationLink {
            RunDetailView(run: run)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accent)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.durationLong(run.totalTimeS))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(.white)
                        Text("\(Fmt.pace(run.avgPaceMinPerKm)) \(Fmt.paceLabel)")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.dateShort(run.startTime))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        if let city = run.city {
                            Text("\(Fmt.flag(run.countryCode)) \(city)")
                                .font(.caption).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .padding(12)
            .background(Theme.bgPrimary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Best Splits

    private var bestSplitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Best Splits", systemImage: "stopwatch.fill")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                if isComputing {
                    ProgressView().tint(Theme.accent)
                }
            }

            if bestSplits.isEmpty && !isComputing {
                Text("Computing splits requires imported trackpoint data.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }

            ForEach(bestSplits) { split in
                NavigationLink {
                    if let run = runs.first(where: { $0.id == split.runId }) {
                        RunDetailView(run: run)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(split.targetName)
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.accent)
                            Text(Fmt.durationLong(split.timeS))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Fmt.pace(split.paceMinKm)) \(Fmt.paceLabel)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                            Text(Fmt.speed(split.targetM / split.timeS))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textMuted)
                            Text(split.location.isEmpty ? Fmt.dateShort(split.date) : split.location)
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(10)
                    .background(Theme.bgPrimary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Other Records

    private var otherRecordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Bests", systemImage: "star.fill")
                .font(.headline).foregroundStyle(.white)

            if let r = runs.max(by: { $0.totalDistanceM < $1.totalDistanceM }) {
                pbRow("Longest Run", Fmt.distance(r.totalDistanceM), run: r)
            }
            if let r = runs.max(by: { $0.totalTimeS < $1.totalTimeS }) {
                pbRow("Longest Duration", Fmt.duration(r.totalTimeS), run: r)
            }
            if let r = runs.max(by: { $0.elevationGainM < $1.elevationGainM }) {
                pbRow("Most Elevation", Fmt.elevation(r.elevationGainM), run: r)
            }
            if let r = runs.filter({ $0.totalDistanceM >= 1000 && $0.avgPaceMinPerKm >= 2 && $0.avgPaceMinPerKm <= 15 }).min(by: { $0.avgPaceMinPerKm < $1.avgPaceMinPerKm }) {
                pbRow("Fastest Pace", "\(Fmt.pace(r.avgPaceMinPerKm)) \(Fmt.paceLabel)", run: r)
            }
            if let r = runs.max(by: { $0.calories < $1.calories }) {
                pbRow("Most Calories", "\(r.calories) kcal", run: r)
            }
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func pbRow(_ title: String, _ value: String, run: Run) -> some View {
        NavigationLink {
            RunDetailView(run: run)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.dateShort(run.startTime)).font(.caption2).foregroundStyle(Theme.textMuted)
                    if let city = run.city {
                        Text(city).font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textMuted)
            }
            .padding(10)
            .background(Theme.bgPrimary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cache

    private func loadCachedSplits() -> Bool {
        guard let cached = TrackpointStore.loadSplitsCache() else { return false }
        bestSplits = cached.map { c in
            SplitRecord(
                targetName: c.targetName, targetM: c.targetM, timeS: c.timeS,
                paceMinKm: c.paceMinKm, runId: c.runId, date: c.date, location: c.location
            )
        }
        return !bestSplits.isEmpty
    }

    private func saveSplitsToCache() {
        let cached = bestSplits.map { s in
            TrackpointStore.CachedSplit(
                targetName: s.targetName, targetM: s.targetM, timeS: s.timeS,
                paceMinKm: s.paceMinKm, runId: s.runId, date: s.date, location: s.location
            )
        }
        TrackpointStore.saveSplitsCache(cached)
    }

    // MARK: - Parallel Sliding Window Computation

    private struct SplitWorkResult: Sendable {
        let runId: UUID
        let bestTimes: [Double]
    }

    private func computeSplits() async {
        guard !runs.isEmpty else { return }
        isComputing = true

        let runInfoList = runs.map { (id: $0.id, date: $0.startTime, city: $0.city, country: $0.country) }

        let targets: [(String, Double)] = [
            ("1K", 1000), ("5K", 5000), ("10K", 10000),
            ("15K", 15000), ("21.1K", 21097.5), ("42.2K", 42195)
        ]
        let targetDistances = targets.map { $0.1 }
        let targetCount = targets.count

        let allResults = await withTaskGroup(of: SplitWorkResult?.self) { group in
            for info in runInfoList {
                let runId = info.id
                group.addTask {
                    guard let pts = TrackpointStore.loadDistances(runId: runId) else { return nil }

                    for i in 1..<pts.count {
                        if pts[i].distanceM < pts[i - 1].distanceM - 1.0 { return nil }
                        if pts[i].time <= pts[i - 1].time { return nil }
                    }
                    guard let lastDist = pts.last?.distanceM, lastDist > 0,
                          !lastDist.isNaN, !lastDist.isInfinite else { return nil }

                    var best = [Double](repeating: .infinity, count: targetCount)
                    for tIdx in 0..<targetCount {
                        let targetM = targetDistances[tIdx]
                        guard lastDist >= targetM else { continue }
                        var j = 0
                        for i in 0..<pts.count {
                            while j < pts.count - 1 && pts[j].distanceM - pts[i].distanceM < targetM { j += 1 }
                            let covered = pts[j].distanceM - pts[i].distanceM
                            if covered >= targetM {
                                let t = pts[j].time.timeIntervalSince(pts[i].time)
                                guard t > 0, !t.isNaN, !t.isInfinite else { continue }
                                let pace = (t / 60) / (covered / 1000)
                                if pace >= 2.0 && pace <= 15.0 && t < best[tIdx] {
                                    best[tIdx] = t
                                }
                            }
                        }
                    }
                    return SplitWorkResult(runId: runId, bestTimes: best)
                }
            }

            var collected: [SplitWorkResult] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }

        guard !Task.isCancelled else {
            isComputing = false
            return
        }

        var bestTimes = [Double](repeating: .infinity, count: targetCount)
        var bestRunIds = [UUID?](repeating: nil, count: targetCount)
        for result in allResults {
            for tIdx in 0..<targetCount {
                if result.bestTimes[tIdx] < bestTimes[tIdx] {
                    bestTimes[tIdx] = result.bestTimes[tIdx]
                    bestRunIds[tIdx] = result.runId
                }
            }
        }

        let runInfoMap = Dictionary(uniqueKeysWithValues: runInfoList.map { ($0.id, $0) })
        var results: [SplitRecord] = []
        for (tIdx, (name, targetM)) in targets.enumerated() {
            if bestTimes[tIdx] < .infinity, let rId = bestRunIds[tIdx], let ri = runInfoMap[rId] {
                let pace = (bestTimes[tIdx] / 60) / (targetM / 1000)
                let loc = [ri.city, ri.country].compactMap { $0 }.joined(separator: ", ")
                results.append(SplitRecord(
                    targetName: name, targetM: targetM, timeS: bestTimes[tIdx],
                    paceMinKm: pace, runId: rId, date: ri.date, location: loc
                ))
            }
        }

        bestSplits = results
        hasComputed = true
        isComputing = false
        saveSplitsToCache()
    }
}
