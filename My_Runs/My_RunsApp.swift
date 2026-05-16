import SwiftUI
import SwiftData

@main
struct My_RunsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Run.self, Lap.self, StoredTrackpoints.self])
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("[MyRuns] ModelContainer initialized with CloudKit sync.")
            return container
        } catch {
            print("[MyRuns] CloudKit ModelContainer failed: \(error)")
            print("[MyRuns] Falling back to local-only ModelContainer.")
        }

        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
