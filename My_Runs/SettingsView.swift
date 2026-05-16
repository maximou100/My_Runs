import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("distanceUnit") private var distanceUnit = DistanceUnit.km.rawValue
    @AppStorage("speedUnit") private var speedUnit = SpeedUnit.kmh.rawValue
    @AppStorage("paceUnit") private var paceUnit = PaceUnit.minPerKm.rawValue
    @AppStorage("altitudeUnit") private var altitudeUnit = AltitudeUnit.meters.rawValue

    @Environment(\.modelContext) private var modelContext
    @Query private var runs: [Run]
    @Query private var storedTrackpoints: [StoredTrackpoints]

    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    unitCard("Distance", selection: $distanceUnit, options: DistanceUnit.allCases)
                    unitCard("Speed", selection: $speedUnit, options: SpeedUnit.allCases)
                    unitCard("Pace", selection: $paceUnit, options: PaceUnit.allCases)
                    unitCard("Altitude", selection: $altitudeUnit, options: AltitudeUnit.allCases)
                    dataCard
                    aboutCard
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all data?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All Runs & Data", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes all imported runs, trackpoints, and cached records from this device and iCloud. This cannot be undone.")
            }
        }
    }

    private func unitCard<T: RawRepresentable & CaseIterable & Hashable>(
        _ title: String,
        selection: Binding<String>,
        options: [T]
    ) -> some View where T.RawValue == String, T: UnitDisplayable {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                ForEach(options, id: \.rawValue) { option in
                    let isSelected = selection.wrappedValue == option.rawValue
                    Button {
                        selection.wrappedValue = option.rawValue
                    } label: {
                        Text(option.displayLabel)
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                isSelected ? Theme.accent.opacity(0.2) : Theme.bgPrimary.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Data", systemImage: "externaldrive")
                .font(.headline)
                .foregroundStyle(.white)

            Text("\(runs.count) runs stored on this device.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(isDeleting ? "Deleting..." : "Delete All Data", systemImage: "trash")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.danger.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Theme.danger)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.danger.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting || runs.isEmpty)
        }
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("My Runs", systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Your running data, your way.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func deleteAllData() {
        isDeleting = true
        for run in runs { modelContext.delete(run) }
        for tp in storedTrackpoints { modelContext.delete(tp) }
        try? modelContext.save()
        TrackpointStore.deleteAll()
        Haptics.notification(.success)
        isDeleting = false
    }
}

protocol UnitDisplayable {
    var displayLabel: String { get }
}

extension DistanceUnit: UnitDisplayable {
    var displayLabel: String { label }
}
extension SpeedUnit: UnitDisplayable {
    var displayLabel: String { label }
}
extension PaceUnit: UnitDisplayable {
    var displayLabel: String { label }
}
extension AltitudeUnit: UnitDisplayable {
    var displayLabel: String { label }
}
