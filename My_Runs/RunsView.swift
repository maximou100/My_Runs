import SwiftUI
import SwiftData

struct RunsView: View {
    @Query(sort: [SortDescriptor(\Run.startTime, order: .reverse)]) private var runs: [Run]
    @State private var sortField: SortField = .date
    @State private var sortAscending = false
    @State private var filterCategory: RunCategory?
    @State private var filterCountry: String?
    @State private var showFilters = false
    @State private var searchText = ""

    enum SortField: String, CaseIterable {
        case date = "Date"
        case distance = "Distance"
        case pace = "Pace"
        case duration = "Duration"
        case elevation = "Elevation"
    }

    private var availableCountries: [(code: String, name: String)] {
        let codes = Set(runs.compactMap { $0.countryCode })
        return codes.compactMap { code in
            guard let name = runs.first(where: { $0.countryCode == code })?.country else { return nil }
            return (code, name)
        }.sorted { $0.name < $1.name }
    }

    private var filteredRuns: [Run] {
        var result = runs.filter { run in
            if let cat = filterCategory, run.category != cat { return false }
            if let country = filterCountry, run.countryCode != country { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let match = run.city?.lowercased().contains(q) == true
                    || run.country?.lowercased().contains(q) == true
                    || run.fileName.lowercased().contains(q)
                if !match { return false }
            }
            return true
        }

        result.sort { a, b in
            let cmp: Bool
            switch sortField {
            case .date: cmp = a.startTime < b.startTime
            case .distance: cmp = a.totalDistanceM < b.totalDistanceM
            case .pace: cmp = a.avgPaceMinPerKm < b.avgPaceMinPerKm
            case .duration: cmp = a.totalTimeS < b.totalTimeS
            case .elevation: cmp = a.elevationGainM < b.elevationGainM
            }
            return sortAscending ? cmp : !cmp
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                if runs.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        if showFilters { filterBar }
                        runList
                    }
                }
            }
            .navigationTitle("Runs")
            .searchable(text: $searchText, prompt: "Search by city, country...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showFilters.toggle() }
                    } label: {
                        Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textMuted)
            Text("No Runs Yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Import .tcx files from the Import tab.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Picker("Category", selection: $filterCategory) {
                    Text("All Categories").tag(RunCategory?.none)
                    ForEach(RunCategory.allCases, id: \.rawValue) { cat in
                        Text(cat.displayName).tag(RunCategory?.some(cat))
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)

                if !availableCountries.isEmpty {
                    Picker("Country", selection: $filterCountry) {
                        Text("All Countries").tag(String?.none)
                        ForEach(availableCountries, id: \.code) { c in
                            Text("\(Fmt.flag(c.code)) \(c.name)").tag(String?.some(c.code))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }

                if filterCategory != nil || filterCountry != nil {
                    Button("Clear") {
                        filterCategory = nil
                        filterCountry = nil
                    }
                    .font(.caption)
                    .tint(Theme.danger)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Theme.bgCard)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortField.allCases, id: \.rawValue) { field in
                Button {
                    if sortField == field { sortAscending.toggle() }
                    else { sortField = field; sortAscending = false }
                } label: {
                    HStack {
                        Text(field.rawValue)
                        if sortField == field {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var runList: some View {
        List {
            ForEach(filteredRuns, id: \.id) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    RunRowView(run: run)
                }
                .listRowBackground(Theme.bgCard)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Run Row

struct RunRowView: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Fmt.dateShort(run.startTime))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                dataSourceBadge
                categoryBadge
            }

            if let city = run.city {
                HStack(spacing: 4) {
                    Text(Fmt.flag(run.countryCode))
                    Text(city)
                        .foregroundStyle(.white)
                    if let country = run.country {
                        Text("·")
                            .foregroundStyle(Theme.textMuted)
                        Text(country)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }

            HStack(spacing: 16) {
                statItem(icon: "ruler", value: Fmt.distance(run.totalDistanceM))
                statItem(icon: "timer", value: Fmt.duration(run.totalTimeS))
                statItem(icon: "speedometer", value: "\(Fmt.pace(run.avgPaceMinPerKm)) \(Fmt.paceLabel)")
                if run.elevationGainM > 0 {
                    statItem(icon: "mountain.2", value: Fmt.elevation(run.elevationGainM))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dataSourceBadge: some View {
        Group {
            switch run.dataSource {
            case .tcx:
                Label("TCX", systemImage: "doc.text.fill")
                    .foregroundStyle(.blue)
                    .background(.blue.opacity(0.15), in: Capsule())
            case .healthKit:
                Label("Fitness", systemImage: "heart.fill")
                    .foregroundStyle(.pink)
                    .background(.pink.opacity(0.15), in: Capsule())
            case .strava:
                Label("Strava", systemImage: "figure.run")
                    .foregroundStyle(Color(hex: "fc5200"))
                    .background(Color(hex: "fc5200").opacity(0.15), in: Capsule())
            }
        }
        .font(.caption2.bold())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private var categoryBadge: some View {
        Text(run.category.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(run.category.color.opacity(0.2), in: Capsule())
            .foregroundStyle(run.category.color)
    }

    private func statItem(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
