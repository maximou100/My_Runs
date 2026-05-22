import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
            RunsView()
                .tabItem { Label("Runs", systemImage: "list.bullet") }
            RecordsView()
                .tabItem { Label("Records", systemImage: "trophy.fill") }
            HealthView()
                .tabItem { Label("Health", systemImage: "heart.fill") }
            ImportView()
                .tabItem { Label("Import", systemImage: "arrow.down.circle.fill") }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Run.self, Lap.self, StoredTrackpoints.self], inMemory: true)
        .preferredColorScheme(.dark)
}
