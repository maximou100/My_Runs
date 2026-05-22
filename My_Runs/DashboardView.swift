import SwiftUI
import SwiftData
import Charts
import MapKit

struct DashboardView: View {
    @Query(sort: [SortDescriptor(\Run.startTime, order: .reverse)]) private var runs: [Run]
    @State private var activeSheet: SheetType?
    @State private var chartMode: ChartMode = .monthly
    @State private var showSettings = false

    enum ChartMode: String, CaseIterable { case monthly = "Monthly", yearly = "Yearly" }

    enum SheetType: Identifiable {
        case longestRuns, runsByYear, longestDuration, mostCalories, countries, fastestRuns
        case category(RunCategory)
        var id: String {
            switch self {
            case .longestRuns: "longest"
            case .runsByYear: "byYear"
            case .longestDuration: "duration"
            case .mostCalories: "calories"
            case .countries: "countries"
            case .fastestRuns: "fastest"
            case .category(let c): "cat-\(c.rawValue)"
            }
        }
    }

    private var totalDistanceKm: Double { runs.reduce(0) { $0 + $1.totalDistanceM } / 1000 }
    private var totalTimeHours: Double { runs.reduce(0) { $0 + $1.totalTimeS } / 3600 }
    private var totalCalories: Int { runs.reduce(0) { $0 + $1.calories } }
    private var countryCount: Int { Set(runs.compactMap { $0.countryCode }).count }
    private var avgPace: Double {
        let valid = runs.filter { $0.avgPaceMinPerKm > 0 && $0.avgPaceMinPerKm < 15 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.avgPaceMinPerKm } / Double(valid.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if runs.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 24) {
                        kpiGrid
                        raceBadges
                        distanceChartCard
                        paceTrendCard
                        distributionCard
                        dayOfWeekCard
                        calendarHeatmap
                        worldMapCard
                    }
                    .padding()
                }
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(sheet)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)
            Text("No Data Yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Import runs from the Import tab to see your dashboard.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(60)
    }

    // MARK: - KPI Grid

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            kpiCard("Total Distance", value: String(format: "%.1f %@", Fmt.distanceValue(totalDistanceKm * 1000), Fmt.distanceLabel), icon: "ruler", color: Theme.accent) { activeSheet = .longestRuns }
            kpiCard("Total Runs", value: "\(runs.count)", icon: "figure.run", color: .blue) { activeSheet = .runsByYear }
            kpiCard("Total Time", value: String(format: "%.0f hrs", totalTimeHours), icon: "clock", color: .purple) { activeSheet = .longestDuration }
            kpiCard("Calories", value: "\(totalCalories)", icon: "flame.fill", color: .orange) { activeSheet = .mostCalories }
            kpiCard("Countries", value: "\(countryCount)", icon: "globe", color: .cyan) { activeSheet = .countries }
            kpiCard("Avg Pace", value: "\(Fmt.pace(avgPace)) \(Fmt.paceLabel)", icon: "speedometer", color: Theme.accent) { activeSheet = .fastestRuns }
        }
    }

    private func kpiCard(_ title: String, value: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Race Badges

    private var raceBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach([RunCategory.marathon, .halfMarathon, .fifteenK, .tenK, .fiveK], id: \.rawValue) { cat in
                    let count = runs.filter { $0.category == cat }.count
                    Button {
                        Haptics.selection()
                        activeSheet = .category(cat)
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(count)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.white)
                            Text(cat.displayName)
                                .font(.caption2)
                                .foregroundStyle(cat.color)
                        }
                        .frame(width: 80, height: 60)
                        .background(cat.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cat.color.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Distance Chart

    private struct DateValue: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    private var distanceChartData: [DateValue] {
        let cal = Calendar.current
        var grouped: [Date: Double] = [:]
        for run in runs {
            let comps = chartMode == .monthly
                ? cal.dateComponents([.year, .month], from: run.startTime)
                : cal.dateComponents([.year], from: run.startTime)
            if let d = cal.date(from: comps) { grouped[d, default: 0] += Fmt.distanceValue(run.totalDistanceM) }
        }
        return grouped.map { DateValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }

    private var distanceChartCard: some View {
        chartCard(title: "Distance") {
            HStack {
                Spacer()
                Picker("", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        } chart: {
            Chart(distanceChartData) { item in
                BarMark(
                    x: .value("Date", item.date, unit: chartMode == .monthly ? .month : .year),
                    y: .value("Km", item.value)
                )
                .foregroundStyle(Theme.accent.gradient)
            }
            .chartYAxisLabel(Fmt.distanceLabel)
        }
    }

    // MARK: - Pace Trend

    private var paceTrendData: [DateValue] {
        let sorted = runs.filter { $0.avgPaceMinPerKm > 0 && $0.avgPaceMinPerKm < 15 }
            .sorted { $0.startTime < $1.startTime }
        guard !sorted.isEmpty else { return [] }

        let cal = Calendar.current
        var results: [DateValue] = []
        results.reserveCapacity(sorted.count)
        var lo = 0
        var windowSum = 0.0

        for i in 0..<sorted.count {
            let cutoff = cal.date(byAdding: .day, value: -30, to: sorted[i].startTime)!
            windowSum += sorted[i].avgPaceMinPerKm
            while sorted[lo].startTime < cutoff {
                windowSum -= sorted[lo].avgPaceMinPerKm
                lo += 1
            }
            let count = i - lo + 1
            results.append(DateValue(date: sorted[i].startTime, value: windowSum / Double(count)))
        }
        return results
    }

    private var paceTrendCard: some View {
        chartCard(title: "Pace Trend (30-day avg)") { EmptyView() } chart: {
            Chart(paceTrendData) { item in
                LineMark(x: .value("Date", item.date), y: .value("Pace", item.value))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Fmt.pace(v)) }
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
        }
    }

    // MARK: - Distribution

    private struct LabelValue: Identifiable {
        var id: String { label }
        let label: String
        let value: Double
    }

    private var distributionData: [LabelValue] {
        let isMiles = Fmt.distanceUnit == .miles
        let buckets: [(String, ClosedRange<Double>)] = isMiles
            ? [("0-2", 0...2), ("2-3", 2...3), ("3-5", 3...5), ("5-6", 5...6),
               ("6-10", 6...10), ("10-13", 10...13), ("13-19", 13...19),
               ("19-26", 19...26), ("26+", 26...500)]
            : [("0-3", 0...3), ("3-5", 3...5), ("5-8", 5...8), ("8-10", 8...10),
               ("10-15", 10...15), ("15-21", 15...21), ("21-30", 21...30),
               ("30-42", 30...42), ("42+", 42...500)]
        return buckets.map { label, range in
            LabelValue(label: label, value: Double(runs.filter { range.contains(Fmt.distanceValue($0.totalDistanceM)) }.count))
        }
    }

    private var distributionCard: some View {
        chartCard(title: "Distance Distribution (\(Fmt.distanceLabel))") { EmptyView() } chart: {
            Chart(distributionData) { item in
                BarMark(x: .value("Range", item.label), y: .value("Count", item.value))
                    .foregroundStyle(Theme.accent.gradient)
            }
        }
    }

    // MARK: - Day of Week

    private var dayOfWeekData: [LabelValue] {
        let cal = Calendar.current
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var counts = Array(repeating: 0, count: 7)
        for run in runs { counts[cal.component(.weekday, from: run.startTime) - 1] += 1 }
        return names.enumerated().map { LabelValue(label: $0.element, value: Double(counts[$0.offset])) }
    }

    private var dayOfWeekCard: some View {
        chartCard(title: "Runs by Day") { EmptyView() } chart: {
            Chart(dayOfWeekData) { item in
                BarMark(x: .value("Day", item.label), y: .value("Runs", item.value))
                    .foregroundStyle(Theme.accent.gradient)
            }
        }
    }

    // MARK: - Chart Card Helper

    private func chartCard<Header: View, ChartContent: View>(
        title: String,
        @ViewBuilder header: () -> Header,
        @ViewBuilder chart: () -> ChartContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.white)
                Spacer()
                header()
            }
            chart().frame(height: 200)
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Calendar Heatmap

    private var calendarHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity").font(.headline).foregroundStyle(.white)

            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let totalDays = 52 * 7
            let startDate = cal.date(byAdding: .day, value: -(totalDays - 1), to: today)!

            let dayDist: [Date: Double] = {
                var d: [Date: Double] = [:]
                for run in runs { d[cal.startOfDay(for: run.startTime), default: 0] += run.distanceKm }
                return d
            }()
            let maxDist = max(dayDist.values.max() ?? 1, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(0..<52, id: \.self) { week in
                        VStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { day in
                                let date = cal.date(byAdding: .day, value: week * 7 + day, to: startDate)!
                                let dist = dayDist[cal.startOfDay(for: date)] ?? 0
                                let opacity = dist > 0 ? max(0.25, min(1.0, dist / maxDist)) : 0

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(dist > 0 ? Theme.accent.opacity(opacity) : Theme.bgCard)
                                    .frame(width: 11, height: 11)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - World Map

    private struct MapPoint: Identifiable {
        let id: String
        let coord: CLLocationCoordinate2D
        let color: Color
        let count: Int
    }

    private var mapPoints: [MapPoint] {
        var grouped: [String: (lat: Double, lng: Double, count: Int, color: Color)] = [:]
        for run in runs where run.startLat != 0 {
            let key = String(format: "%.2f,%.2f", run.startLat, run.startLng)
            if let existing = grouped[key] {
                grouped[key] = (existing.lat, existing.lng, existing.count + 1, existing.color)
            } else {
                grouped[key] = (run.startLat, run.startLng, 1, run.category.color)
            }
        }
        return grouped.map { MapPoint(id: $0.key, coord: CLLocationCoordinate2D(latitude: $0.value.lat, longitude: $0.value.lng), color: $0.value.color, count: $0.value.count) }
    }

    private var worldMapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where You've Run").font(.headline).foregroundStyle(.white)
            Map {
                ForEach(mapPoints) { pt in
                    Annotation("", coordinate: pt.coord) {
                        Circle()
                            .fill(pt.color)
                            .frame(width: pt.count > 5 ? 12 : 8, height: pt.count > 5 ? 12 : 8)
                            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(_ sheet: SheetType) -> some View {
        NavigationStack {
            sheetBody(sheet)
                .navigationTitle(sheetTitle(sheet))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { activeSheet = nil }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private func sheetTitle(_ sheet: SheetType) -> String {
        switch sheet {
        case .longestRuns: "Longest Runs"
        case .runsByYear: "Runs by Year"
        case .longestDuration: "Longest Duration"
        case .mostCalories: "Most Calories"
        case .countries: "Countries"
        case .fastestRuns: "Fastest Runs"
        case .category(let c): c.displayName
        }
    }

    @ViewBuilder
    private func sheetBody(_ sheet: SheetType) -> some View {
        switch sheet {
        case .longestRuns:
            makeRunList(runs.sorted { $0.totalDistanceM > $1.totalDistanceM }, limit: 10)
        case .longestDuration:
            makeRunList(runs.sorted { $0.totalTimeS > $1.totalTimeS }, limit: 10)
        case .mostCalories:
            makeRunList(runs.sorted { $0.calories > $1.calories }, limit: 10)
        case .fastestRuns:
            makeRunList(runs.filter { $0.avgPaceMinPerKm > 0 }.sorted { $0.avgPaceMinPerKm < $1.avgPaceMinPerKm }, limit: 10)
        case .category(let cat):
            makeRunList(runs.filter { $0.category == cat }.sorted { $0.startTime > $1.startTime })
        case .runsByYear:
            yearBreakdownView
        case .countries:
            countriesListView
        }
    }

    private func makeRunList(_ items: [Run], limit: Int? = nil) -> some View {
        let display = limit.map { Array(items.prefix($0)) } ?? items
        return List {
            ForEach(display, id: \.id) { run in
                RunRowView(run: run)
                    .listRowBackground(Theme.bgCard)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var yearBreakdownView: some View {
        let cal = Calendar.current
        let byYear = Dictionary(grouping: runs) { cal.component(.year, from: $0.startTime) }
        let years = byYear.keys.sorted(by: >)
        return List {
            ForEach(years, id: \.self) { year in
                let yr = byYear[year]!
                HStack {
                    Text(String(year))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(yr.count) runs")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Text(Fmt.distance(yr.reduce(0) { $0 + $1.totalDistanceM }))
                            .font(.caption.bold())
                            .foregroundStyle(Theme.accent)
                    }
                }
                .listRowBackground(Theme.bgCard)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var countriesListView: some View {
        let grouped = Dictionary(grouping: runs.filter { $0.countryCode != nil }) { $0.countryCode! }
        let codes = grouped.keys.sorted { grouped[$0]!.count > grouped[$1]!.count }
        return List {
            ForEach(codes, id: \.self) { code in
                let cRuns = grouped[code]!
                HStack {
                    Text(Fmt.flag(code)).font(.title2)
                    Text(cRuns.first?.country ?? code).foregroundStyle(.white)
                    Spacer()
                    Text("\(cRuns.count) runs")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.bgCard)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Run.self, Lap.self, StoredTrackpoints.self], inMemory: true)
        .preferredColorScheme(.dark)
}
