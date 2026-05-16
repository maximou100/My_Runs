import HealthKit
import CoreLocation

final class HealthKitService {
    static let shared = HealthKitService()

    private var store: HKHealthStore?
    private(set) var isAuthorized = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.notAvailable }
        let s = getOrCreateStore()

        let shareTypes: Set<HKSampleType> = [
            HKWorkoutType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning)
        ]

        let readTypes: Set<HKObjectType> = [
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning)
        ]

        try await s.requestAuthorization(toShare: shareTypes, read: readTypes)
        isAuthorized = true
    }

    // MARK: - Push (Export)

    func syncRun(_ run: Run) async throws {
        guard isAvailable else { throw HealthError.notAvailable }
        let s = getOrCreateStore()

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: s, configuration: config, device: nil)
        try await builder.beginCollection(at: run.startTime)

        let end = run.startTime.addingTimeInterval(run.totalTimeS)

        var samples: [HKQuantitySample] = []
        if run.calories > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(run.calories)),
                start: run.startTime, end: end
            ))
        }
        samples.append(HKQuantitySample(
            type: HKQuantityType(.distanceWalkingRunning),
            quantity: HKQuantity(unit: .meter(), doubleValue: run.totalDistanceM),
            start: run.startTime, end: end
        ))

        try await builder.addSamples(samples)
        try await builder.endCollection(at: end)
        try await builder.finishWorkout()
    }

    // MARK: - Pull (Import)

    func fetchRunningWorkouts() async throws -> [HKWorkout] {
        guard isAvailable else { throw HealthError.notAvailable }
        let s = getOrCreateStore()

        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(runningPredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try await descriptor.result(for: s)
    }

    func fetchRouteLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let s = getOrCreateStore()

        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(workoutPredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let routes = try await routeDescriptor.result(for: s)

        var allLocations: [CLLocation] = []
        for route in routes {
            let routeQuery = HKWorkoutRouteQueryDescriptor(route)
            let locations = routeQuery.results(for: s)
            for try await location in locations {
                allLocations.append(location)
            }
        }
        return allLocations.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Heart Rate Samples

    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [(date: Date, bpm: Double)] {
        guard isAvailable else { throw HealthError.notAvailable }
        let s = getOrCreateStore()

        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: s)
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.map { (date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit)) }
    }

    // MARK: - Private

    private func getOrCreateStore() -> HKHealthStore {
        if let store { return store }
        let s = HKHealthStore()
        store = s
        return s
    }

    enum HealthError: LocalizedError {
        case notAvailable
        var errorDescription: String? { "HealthKit is not available on this device." }
    }
}
