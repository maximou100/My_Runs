import Foundation

nonisolated enum TrackpointStore {
    private static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trackpoints", isDirectory: true)
    }

    static func saveRawTCX(runId: UUID, data: Data) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(runId.uuidString).tcx")
        try? data.write(to: url, options: .atomic)
    }

    static func saveTrackpoints(runId: UUID, trackpoints: [TrackpointData]) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(runId.uuidString).json")
        guard let data = try? JSONEncoder().encode(trackpoints) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadTrackpoints(runId: UUID, maxCount: Int = 500) -> [TrackpointData]? {
        let jsonURL = directory.appendingPathComponent("\(runId.uuidString).json")
        if let data = try? Data(contentsOf: jsonURL),
           let pts = try? JSONDecoder().decode([TrackpointData].self, from: data) {
            return downsample(pts, maxCount: maxCount)
        }

        let tcxURL = directory.appendingPathComponent("\(runId.uuidString).tcx")
        guard let data = try? Data(contentsOf: tcxURL) else { return nil }
        let parser = TCXParserService()
        guard let result = parser.parse(data: data) else { return nil }
        return downsample(result.trackpoints, maxCount: maxCount)
    }

    static func loadDistances(runId: UUID) -> [TCXParserService.DistancePoint]? {
        let jsonURL = directory.appendingPathComponent("\(runId.uuidString).json")
        if let data = try? Data(contentsOf: jsonURL),
           let pts = try? JSONDecoder().decode([TrackpointData].self, from: data) {
            return pts.map { TCXParserService.DistancePoint(time: $0.time, distanceM: $0.distanceM) }
        }

        let tcxURL = directory.appendingPathComponent("\(runId.uuidString).tcx")
        guard let data = try? Data(contentsOf: tcxURL) else { return nil }
        let parser = TCXParserService()
        return parser.parseDistances(data: data)
    }

    static func delete(runId: UUID) {
        let tcxURL = directory.appendingPathComponent("\(runId.uuidString).tcx")
        let jsonURL = directory.appendingPathComponent("\(runId.uuidString).json")
        try? FileManager.default.removeItem(at: tcxURL)
        try? FileManager.default.removeItem(at: jsonURL)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        clearSplitsCache()
    }

    // MARK: - Splits Cache

    private static var splitsCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("splits_cache.json")
    }

    struct CachedSplit: Codable {
        let targetName: String
        let targetM: Double
        let timeS: Double
        let paceMinKm: Double
        let runId: UUID
        let date: Date
        let location: String
    }

    static func saveSplitsCache(_ splits: [CachedSplit]) {
        guard let data = try? JSONEncoder().encode(splits) else { return }
        try? data.write(to: splitsCacheURL, options: .atomic)
    }

    static func loadSplitsCache() -> [CachedSplit]? {
        guard let data = try? Data(contentsOf: splitsCacheURL) else { return nil }
        return try? JSONDecoder().decode([CachedSplit].self, from: data)
    }

    static func clearSplitsCache() {
        try? FileManager.default.removeItem(at: splitsCacheURL)
    }

    private static func downsample(_ points: [TrackpointData], maxCount: Int) -> [TrackpointData] {
        guard points.count > maxCount else { return points }
        let step = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { i in
            points[min(Int(Double(i) * step), points.count - 1)]
        }
    }
}
