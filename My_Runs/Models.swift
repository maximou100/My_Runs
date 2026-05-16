import Foundation
import SwiftData

enum DataSource: String, Codable {
    case tcx
    case healthKit
}

enum RunCategory: String, Codable, CaseIterable {
    case marathon = "marathon"
    case halfMarathon = "half-marathon"
    case fifteenK = "15k"
    case tenK = "10k"
    case fiveK = "5k"
    case short_ = "short"

    static func from(distanceM: Double) -> RunCategory {
        let km = distanceM / 1000
        if km >= 40 { return .marathon }
        if km >= 19.5 && km <= 22 { return .halfMarathon }
        if km >= 14 && km <= 16 { return .fifteenK }
        if km >= 9 && km <= 11 { return .tenK }
        if km >= 4.5 && km <= 6 { return .fiveK }
        return .short_
    }

    var displayName: String {
        switch self {
        case .marathon: return "Marathon"
        case .halfMarathon: return "Half Marathon"
        case .fifteenK: return "15K"
        case .tenK: return "10K"
        case .fiveK: return "5K"
        case .short_: return "Short"
        }
    }

    var targetDistanceM: Double? {
        switch self {
        case .marathon: return 42195
        case .halfMarathon: return 21097.5
        case .fifteenK: return 15000
        case .tenK: return 10000
        case .fiveK: return 5000
        case .short_: return nil
        }
    }
}

@Model
final class Run {
    var id: UUID = UUID()
    var fileName: String = ""
    var sport: String = "Running"
    var startTime: Date = Date()
    var totalDistanceM: Double = 0
    var totalTimeS: Double = 0
    var calories: Int = 0
    var avgPaceMinPerKm: Double = 0
    var maxSpeedMps: Double = 0
    var elevationGainM: Double = 0
    var elevationLossM: Double = 0
    var startLat: Double = 0
    var startLng: Double = 0
    var city: String?
    var country: String?
    var countryCode: String?
    var categoryRaw: String = "short"
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var healthKitSynced: Bool = false
    var dataSourceRaw: String = "tcx"

    @Relationship(deleteRule: .cascade, inverse: \Lap.run)
    var laps: [Lap]?

    var category: RunCategory {
        get { RunCategory(rawValue: categoryRaw) ?? .short_ }
        set { categoryRaw = newValue.rawValue }
    }

    var dataSource: DataSource {
        get { DataSource(rawValue: dataSourceRaw) ?? .tcx }
        set { dataSourceRaw = newValue.rawValue }
    }

    var distanceKm: Double { totalDistanceM / 1000 }

    init(
        id: UUID = UUID(),
        fileName: String,
        sport: String = "Running",
        startTime: Date,
        totalDistanceM: Double,
        totalTimeS: Double,
        calories: Int = 0,
        avgPaceMinPerKm: Double,
        maxSpeedMps: Double = 0,
        elevationGainM: Double = 0,
        elevationLossM: Double = 0,
        startLat: Double = 0,
        startLng: Double = 0,
        city: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        category: RunCategory,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        laps: [Lap]? = nil,
        healthKitSynced: Bool = false,
        dataSource: DataSource = .tcx
    ) {
        self.id = id
        self.fileName = fileName
        self.sport = sport
        self.startTime = startTime
        self.totalDistanceM = totalDistanceM
        self.totalTimeS = totalTimeS
        self.calories = calories
        self.avgPaceMinPerKm = avgPaceMinPerKm
        self.maxSpeedMps = maxSpeedMps
        self.elevationGainM = elevationGainM
        self.elevationLossM = elevationLossM
        self.startLat = startLat
        self.startLng = startLng
        self.city = city
        self.country = country
        self.countryCode = countryCode
        self.categoryRaw = category.rawValue
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.laps = laps
        self.healthKitSynced = healthKitSynced
        self.dataSourceRaw = dataSource.rawValue
    }
}

@Model
final class Lap {
    var startTime: Date = Date()
    var totalTimeS: Double = 0
    var distanceM: Double = 0
    var calories: Int = 0
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var run: Run?

    init(
        startTime: Date,
        totalTimeS: Double,
        distanceM: Double,
        calories: Int = 0,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil
    ) {
        self.startTime = startTime
        self.totalTimeS = totalTimeS
        self.distanceM = distanceM
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
    }
}

@Model
final class StoredTrackpoints {
    var runId: UUID = UUID()
    var data: Data = Data()

    init(runId: UUID, data: Data) {
        self.runId = runId
        self.data = data
    }
}

struct TrackpointData: Codable, Equatable {
    var time: Date
    var lat: Double
    var lng: Double
    var altitudeM: Double
    var distanceM: Double
    var heartRate: Int?
    var speedMps: Double?
}
