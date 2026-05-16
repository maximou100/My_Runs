import SwiftUI
import SwiftData
import Charts
import MapKit
import HealthKit

struct RunDetailView: View {
    let run: Run
    @Environment(\.modelContext) private var modelContext

    @State private var trackpoints: [TrackpointData] = []
    @State private var isLoading = true

    @State private var currentIndex = 0
    @State private var isPlaying = false
    @State private var playbackSpeed = 1
    @State private var playbackTask: Task<Void, Never>?
    @State private var mapPosition: MapCameraPosition = .automatic

    @State private var paceSegments: [PaceSegment] = []
    @State private var paceChartData: [ChartPt] = []
    @State private var elevChartData: [ChartPt] = []
    @State private var speedChartData: [ChartPt] = []
    @State private var hrChartData: [ChartPt] = []
    @State private var splits: [KmSplit] = []

    struct PaceSegment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    struct ChartPt: Identifiable {
        let id: Int
        let km: Double
        let value: Double
    }

    struct KmSplit: Identifiable {
        var id: Int { km }
        let km: Int
        let time: TimeInterval
        let pace: Double
    }

    private var currentTp: TrackpointData? {
        trackpoints.indices.contains(currentIndex) ? trackpoints[currentIndex] : nil
    }

    private var progress: Double {
        guard trackpoints.count > 1 else { return 0 }
        return Double(currentIndex) / Double(trackpoints.count - 1)
    }

    private var hasHR: Bool { !hrChartData.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection

                if isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(60)
                } else if !trackpoints.isEmpty {
                    mapSection
                    controlsSection
                    paceChartSection
                    elevChartSection
                    if hasHR { hrChartSection }
                    speedChartSection
                    if !splits.isEmpty {
                        splitsSection
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.bgPrimary)
        .navigationTitle(Fmt.distance(run.totalDistanceM))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: Fmt.runSummary(run),
                    subject: Text("My Run — \(Fmt.distance(run.totalDistanceM))"),
                    message: Text(Fmt.runSummary(run))
                )
            }
        }
        .task { await loadData() }
        .onDisappear { playbackTask?.cancel() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.distanceShort(run.totalDistanceM))
                    .font(.system(size: 48, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(Fmt.distanceLabel)
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    if run.dataSource == .healthKit {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                            .padding(5)
                            .background(.pink.opacity(0.15), in: Circle())
                    } else {
                        Image(systemName: "doc.text.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(5)
                            .background(.blue.opacity(0.15), in: Circle())
                    }
                    Text(run.category.displayName)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(run.category.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(run.category.color)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Fmt.dateLong(run.startTime)) at \(Fmt.timeOnly(run.startTime))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if let city = run.city, let country = run.country {
                    HStack(spacing: 4) {
                        Text(Fmt.flag(run.countryCode))
                        Text("\(city), \(country)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                statChip("Duration", Fmt.duration(run.totalTimeS), "clock")
                statChip("Avg Pace", "\(Fmt.pace(run.avgPaceMinPerKm)) \(Fmt.paceLabel)", "speedometer")
                statChip("Calories", "\(run.calories)", "flame.fill")
                statChip("Elev +", Fmt.elevation(run.elevationGainM), "arrow.up.right")
                statChip("Elev -", Fmt.elevation(-run.elevationLossM), "arrow.down.right")
                if let hr = run.avgHeartRate {
                    statChip("Avg HR", "\(hr) bpm", "heart.fill")
                } else {
                    statChip("Max Speed", Fmt.speed(run.maxSpeedMps), "hare")
                }
            }
        }
        .padding(16)
        .background(Theme.bgCard)
    }

    private func statChip(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(Theme.accent)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Theme.bgPrimary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $mapPosition) {
            ForEach(paceSegments) { seg in
                MapPolyline(coordinates: seg.coordinates)
                    .stroke(seg.color, lineWidth: 4)
            }

            if let first = trackpoints.first {
                Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng)) {
                    Image(systemName: "flag.fill").foregroundStyle(.green).font(.caption)
                }
            }
            if let last = trackpoints.last, trackpoints.count > 1 {
                Annotation("Finish", coordinate: CLLocationCoordinate2D(latitude: last.lat, longitude: last.lng)) {
                    Image(systemName: "flag.checkered").foregroundStyle(.white).font(.caption)
                }
            }
            if let tp = currentTp {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: tp.lat, longitude: tp.lng)) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: Theme.accent.opacity(0.6), radius: 6)
                }
            }
        }
        .frame(height: 300)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).frame(width: 44, height: 44)
                }
                Button { resetPlayback() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body).frame(width: 36, height: 36)
                }
                Button { cycleSpeed() } label: {
                    Text("\(playbackSpeed)x")
                        .font(.subheadline.bold().monospacedDigit())
                        .frame(width: 44, height: 36)
                        .background(Theme.bgCardHover, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            }
            .foregroundStyle(.white)

            Slider(
                value: Binding(
                    get: { progress },
                    set: { v in
                        currentIndex = min(max(0, Int(v * Double(trackpoints.count - 1))), trackpoints.count - 1)
                        centerMap()
                    }
                ),
                in: 0...1
            )
            .tint(Theme.accent)

            if let tp = currentTp, let first = trackpoints.first {
                HStack(spacing: 6) {
                    Text(Fmt.distanceShort(tp.distanceM) + " " + Fmt.distanceLabel)
                    Text("|").foregroundStyle(Theme.textMuted)
                    Text(Fmt.duration(tp.time.timeIntervalSince(first.time)))
                    Text("|").foregroundStyle(Theme.textMuted)
                    Text(String(format: "%.0f %@ alt", Fmt.altitudeValue(tp.altitudeM), Fmt.altitudeLabel))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bgCard)
    }

    // MARK: - Charts

    private var currentKm: Double { (currentTp?.distanceM ?? 0) / 1000 }

    private var paceChartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pace")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 16)

            Chart {
                ForEach(paceChartData) { pt in
                    LineMark(x: .value("Km", pt.km), y: .value("Pace", pt.value))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(x: .value("Pos", currentKm))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { val in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = val.as(Double.self) { Text(Fmt.pace(v)).font(.caption2) }
                    }
                }
            }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: 120)
            .padding(.horizontal, 16)
            .chartOverlay { proxy in chartDragOverlay(proxy: proxy) }
        }
        .background(Theme.bgCard)
    }

    private var elevChartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Elevation")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 16)

            Chart {
                ForEach(elevChartData) { pt in
                    AreaMark(x: .value("Km", pt.km), y: .value("Alt", pt.value))
                        .foregroundStyle(.orange.opacity(0.3))
                    LineMark(x: .value("Km", pt.km), y: .value("Alt", pt.value))
                        .foregroundStyle(.orange)
                }
                RuleMark(x: .value("Pos", currentKm))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: 120)
            .padding(.horizontal, 16)
            .chartOverlay { proxy in chartDragOverlay(proxy: proxy) }
        }
        .background(Theme.bgCard)
    }

    private var hrChartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Heart Rate")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 16)

            Chart {
                ForEach(hrChartData) { pt in
                    AreaMark(x: .value(Fmt.distanceLabel, pt.km), y: .value("bpm", pt.value))
                        .foregroundStyle(.pink.opacity(0.2))
                    LineMark(x: .value(Fmt.distanceLabel, pt.km), y: .value("bpm", pt.value))
                        .foregroundStyle(.pink)
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(x: .value("Pos", currentKm))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { val in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = val.as(Double.self) { Text("\(Int(v))").font(.caption2) }
                    }
                }
            }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: 120)
            .padding(.horizontal, 16)
            .chartOverlay { proxy in chartDragOverlay(proxy: proxy) }
        }
        .background(Theme.bgCard)
    }

    private var speedChartSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speed")
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 16)

            Chart {
                ForEach(speedChartData) { pt in
                    LineMark(x: .value(Fmt.distanceLabel, pt.km), y: .value(Fmt.speedLabel, pt.value))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(x: .value("Pos", currentKm))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .frame(height: 100)
            .padding(.horizontal, 16)
            .chartOverlay { proxy in chartDragOverlay(proxy: proxy) }
        }
        .background(Theme.bgCard)
    }

    private func chartDragOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geo[plotFrame].origin
                            let x = value.location.x - origin.x
                            guard let km: Double = proxy.value(atX: x) else { return }
                            let dist = km * 1000
                            let idx = bsearchDistance(dist)
                            if idx < trackpoints.count {
                                currentIndex = idx
                                centerMap()
                            }
                        }
                )
        }
    }

    private func bsearchDistance(_ target: Double) -> Int {
        var lo = 0, hi = trackpoints.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if trackpoints[mid].distanceM < target { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: - Splits

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Splits").font(.headline).foregroundStyle(.white)

            let avgPace = splits.isEmpty ? 0 : splits.reduce(0.0) { $0 + $1.pace } / Double(splits.count)

            ForEach(splits) { split in
                HStack(spacing: 0) {
                    Text("KM \(split.km)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 55, alignment: .leading)
                    Text(Fmt.duration(split.time))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 55, alignment: .trailing)
                    Text("\(Fmt.pace(split.pace)) \(Fmt.paceLabel)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 80, alignment: .trailing)
                    Spacer(minLength: 8)
                    GeometryReader { geo in
                        let ratio = avgPace > 0 ? split.pace / avgPace : 1
                        let barW = min(geo.size.width, geo.size.width * min(1, 2 - ratio))
                        RoundedRectangle(cornerRadius: 3)
                            .fill((split.pace <= avgPace ? Color.green : Color.red).opacity(0.5))
                            .frame(width: max(4, barW))
                    }
                    .frame(height: 14)
                }
            }
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Playback

    private func togglePlayback() {
        Haptics.impact()
        if isPlaying { playbackTask?.cancel(); isPlaying = false }
        else { startPlayback() }
    }

    private func startPlayback() {
        if currentIndex >= trackpoints.count - 1 { currentIndex = 0 }
        isPlaying = true
        playbackTask = Task {
            while !Task.isCancelled && currentIndex < trackpoints.count - 1 {
                try? await Task.sleep(for: .milliseconds(33))
                let step = max(1, trackpoints.count / 1800) * playbackSpeed
                currentIndex = min(currentIndex + step, trackpoints.count - 1)
                centerMap()
            }
            isPlaying = false
        }
    }

    private func resetPlayback() {
        playbackTask?.cancel()
        isPlaying = false
        currentIndex = 0
        mapPosition = .automatic
    }

    private func cycleSpeed() {
        let speeds = [1, 3, 5, 10]
        if let i = speeds.firstIndex(of: playbackSpeed) {
            playbackSpeed = speeds[(i + 1) % speeds.count]
        } else { playbackSpeed = 1 }
    }

    private func centerMap() {
        guard let tp = currentTp else { return }
        mapPosition = .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: tp.lat, longitude: tp.lng),
            distance: 2000
        ))
    }

    // MARK: - Data Loading

    private func loadData() async {
        let runId = run.id

        let pts = await Task.detached {
            TrackpointStore.loadTrackpoints(runId: runId)
        }.value

        if let pts, !pts.isEmpty {
            trackpoints = pts
            computeChartData()
            backfillCloudTrackpointsIfNeeded(runId: runId, pts: pts)
        } else {
            let descriptor = FetchDescriptor<StoredTrackpoints>()
            if let all = try? modelContext.fetch(descriptor),
               let stored = all.first(where: { $0.runId == runId }),
               let pts = try? JSONDecoder().decode([TrackpointData].self, from: stored.data) {
                trackpoints = pts
                computeChartData()
                let cachePts = pts
                Task.detached { TrackpointStore.saveTrackpoints(runId: runId, trackpoints: cachePts) }
            }
        }

        if hrChartData.isEmpty && !trackpoints.isEmpty && HKHealthStore.isHealthDataAvailable() {
            await loadHRFromHealthKit()
        }

        isLoading = false
    }

    private func backfillCloudTrackpointsIfNeeded(runId: UUID, pts: [TrackpointData]) {
        let descriptor = FetchDescriptor<StoredTrackpoints>()
        guard let all = try? modelContext.fetch(descriptor),
              !all.contains(where: { $0.runId == runId }) else { return }
        guard let blob = try? JSONEncoder().encode(pts) else { return }
        modelContext.insert(StoredTrackpoints(runId: runId, data: blob))
        try? modelContext.save()
    }

    private func loadHRFromHealthKit() async {
        guard let first = trackpoints.first, let last = trackpoints.last else { return }
        let start = first.time
        let end = last.time

        guard let samples = try? await HealthKitService.shared.fetchHeartRateSamples(from: start, to: end),
              !samples.isEmpty else { return }

        let tps = trackpoints
        var hPts: [ChartPt] = []
        var tpIdx = 0

        for sample in samples {
            while tpIdx < tps.count - 1 && tps[tpIdx + 1].time <= sample.date {
                tpIdx += 1
            }
            let km = tps[tpIdx].distanceM / 1000
            let bpm = sample.bpm
            if bpm > 30 && bpm < 250 {
                hPts.append(ChartPt(id: hPts.count, km: km, value: bpm))
            }
        }

        if !hPts.isEmpty {
            hrChartData = hPts
        }
    }

    private func computeChartData() {
        let tps = trackpoints
        guard tps.count > 1 else { return }

        // Pace segments for map
        var segs: [PaceSegment] = []
        var segCoords: [CLLocationCoordinate2D] = [CLLocationCoordinate2D(latitude: tps[0].lat, longitude: tps[0].lng)]
        var segColor: Color = .yellow
        let segDist = 300.0

        var lastSegStart = 0
        for i in 1..<tps.count {
            let c = CLLocationCoordinate2D(latitude: tps[i].lat, longitude: tps[i].lng)
            segCoords.append(c)

            if tps[i].distanceM - tps[lastSegStart].distanceM >= segDist || i == tps.count - 1 {
                let dt = tps[i].time.timeIntervalSince(tps[lastSegStart].time)
                let dd = tps[i].distanceM - tps[lastSegStart].distanceM
                let color: Color
                if dd > 0 && dt > 0 {
                    let pace = (dt / 60) / (dd / 1000)
                    color = pace < 4.5 ? .green : (pace < 6.5 ? .yellow : .red)
                } else { color = .yellow }

                if color != segColor && segs.isEmpty == false {
                    segs.append(PaceSegment(id: segs.count, coordinates: segCoords, color: color))
                } else if segs.isEmpty || color != segColor {
                    segs.append(PaceSegment(id: segs.count, coordinates: segCoords, color: color))
                } else {
                    let last = segs.removeLast()
                    segs.append(PaceSegment(id: last.id, coordinates: last.coordinates + segCoords.dropFirst(), color: color))
                }
                segCoords = [c]
                segColor = color
                lastSegStart = i
            }
        }
        paceSegments = segs

        // Chart data — downsample
        let step = max(1, tps.count / 200)
        var pPts: [ChartPt] = [], ePts: [ChartPt] = [], sPts: [ChartPt] = [], hPts: [ChartPt] = []
        var idx = 0

        for i in stride(from: 0, to: tps.count, by: step) {
            let km = tps[i].distanceM / 1000
            ePts.append(ChartPt(id: idx, km: km, value: tps[i].altitudeM))

            if i >= step {
                let dt = tps[i].time.timeIntervalSince(tps[i - step].time)
                let dd = tps[i].distanceM - tps[i - step].distanceM
                if dd > 0 && dt > 0 {
                    let pace = (dt / 60) / (dd / 1000)
                    if pace > 1 && pace < 20 { pPts.append(ChartPt(id: idx, km: km, value: pace)) }
                    let spd = (dd / 1000) / (dt / 3600)
                    if spd > 0 && spd < 30 { sPts.append(ChartPt(id: idx, km: km, value: spd)) }
                }
            }

            if let hr = tps[i].heartRate, hr > 30 {
                hPts.append(ChartPt(id: idx, km: km, value: Double(hr)))
            }
            idx += 1
        }

        paceChartData = pPts
        elevChartData = ePts
        speedChartData = sPts
        hrChartData = hPts

        // Splits (binary search for each km boundary)
        var sp: [KmSplit] = []
        var lastTime = tps[0].time
        let totalKm = Int(tps.last!.distanceM / 1000)
        for km in 1...max(1, totalKm) {
            let target = Double(km) * 1000
            var lo = 0, hi = tps.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if tps[mid].distanceM < target { lo = mid + 1 } else { hi = mid }
            }
            guard lo < tps.count else { break }
            let i = lo
            let prev = i > 0 ? tps[i - 1] : tps[i]
            let dd = tps[i].distanceM - prev.distanceM
            let dt = tps[i].time.timeIntervalSince(prev.time)
            let over = tps[i].distanceM - target
            let end = dd > 0 ? tps[i].time.addingTimeInterval(-(over / dd) * dt) : tps[i].time
            let splitTime = end.timeIntervalSince(lastTime)
            sp.append(KmSplit(km: km, time: splitTime, pace: splitTime / 60))
            lastTime = end
        }
        splits = sp
    }
}
