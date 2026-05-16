import Foundation

nonisolated final class TCXParserService: NSObject, XMLParserDelegate {

    struct ParseResult {
        var sport: String
        var startTime: Date
        var laps: [ParsedLap]
        var trackpoints: [TrackpointData]
        var totalDistanceM: Double
        var totalTimeS: Double
        var totalCalories: Int
        var avgHeartRate: Int?
        var maxHeartRate: Int?
        var maxSpeedMps: Double
        var elevationGainM: Double
        var elevationLossM: Double
    }

    struct ParsedLap {
        var startTime: Date
        var totalTimeS: Double = 0
        var distanceM: Double = 0
        var calories: Int = 0
        var avgHeartRate: Int?
        var maxHeartRate: Int?
    }

    private struct RawTrackpoint {
        var time: Date?
        var lat: Double?
        var lng: Double?
        var altitudeM: Double?
        var distanceM: Double?
        var heartRate: Int?
        var speedMps: Double?
        var hasPosition: Bool { lat != nil && lng != nil }
        var hasDistance: Bool { distanceM != nil }
    }

    private var currentText = ""
    private var elementStack: [String] = []
    private var sport = ""
    private var activityStartTime: Date?
    private var laps: [ParsedLap] = []
    private var rawTrackpoints: [RawTrackpoint] = []
    private var currentLap: ParsedLap?
    private var currentTrackpoint: RawTrackpoint?
    private var inLapAvgHR = false
    private var inLapMaxHR = false
    private var inTrackpointHR = false

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBase: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        isoFull.date(from: s) ?? isoBase.date(from: s)
    }

    struct LiteResult {
        var sport: String
        var startTime: Date
        var laps: [ParsedLap]
        var totalDistanceM: Double
        var totalTimeS: Double
        var totalCalories: Int
        var avgHeartRate: Int?
        var maxHeartRate: Int?
        var maxSpeedMps: Double
        var elevationGainM: Double
        var elevationLossM: Double
        var firstLat: Double
        var firstLng: Double
    }

    struct DistancePoint {
        var time: Date
        var distanceM: Double
    }

    /// Ultra-light parse: only extracts time + cumulative distance pairs.
    /// Skips all GPS/altitude/trackpoint processing. O(n) with minimal memory.
    func parseDistances(data: Data) -> [DistancePoint]? {
        resetState()

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        parser.delegate = nil

        guard activityStartTime != nil, !laps.isEmpty else {
            rawTrackpoints = []
            return nil
        }

        let metricPoints = rawTrackpoints.filter { $0.hasDistance }
        guard !metricPoints.isEmpty else {
            rawTrackpoints = []
            return nil
        }

        let distances = metricPoints.compactMap { $0.distanceM }
        let isSegment = detectSegmentBased(distances)

        var result: [DistancePoint] = []
        result.reserveCapacity(metricPoints.count)

        if isSegment {
            var cum = 0.0
            for mp in metricPoints {
                if let d = mp.distanceM, let t = mp.time {
                    cum += d
                    result.append(DistancePoint(time: t, distanceM: cum))
                }
            }
        } else {
            for mp in metricPoints {
                if let d = mp.distanceM, let t = mp.time {
                    result.append(DistancePoint(time: t, distanceM: d))
                }
            }
        }

        rawTrackpoints = []
        return result.count >= 2 ? result : nil
    }

    func parseLite(data: Data) -> LiteResult? {
        resetState()

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        parser.delegate = nil

        guard let startTime = activityStartTime, !laps.isEmpty else { return nil }

        let totalDistanceM = laps.reduce(0.0) { $0 + $1.distanceM }
        let totalTimeS = laps.reduce(0.0) { $0 + $1.totalTimeS }
        let totalCalories = laps.reduce(0) { $0 + $1.calories }

        let hrLaps = laps.compactMap { $0.avgHeartRate }
        let avgHR = hrLaps.isEmpty ? nil : hrLaps.reduce(0, +) / hrLaps.count
        let maxHR = laps.compactMap { $0.maxHeartRate }.max()

        // O(n) single-pass metadata extraction from raw trackpoints
        var maxSpeed = 0.0
        var elevGain = 0.0
        var elevLoss = 0.0
        var lastAlt: Double?
        var firstLat = 0.0
        var firstLng = 0.0

        for tp in rawTrackpoints {
            if let s = tp.speedMps, s > maxSpeed { maxSpeed = s }
            if let alt = tp.altitudeM {
                if let prev = lastAlt {
                    let diff = alt - prev
                    if diff > 0 { elevGain += diff }
                    else { elevLoss += abs(diff) }
                }
                lastAlt = alt
            }
            if firstLat == 0, let lat = tp.lat, let lng = tp.lng, lat != 0, lng != 0 {
                firstLat = lat
                firstLng = lng
            }
        }

        rawTrackpoints = []

        return LiteResult(
            sport: sport, startTime: startTime, laps: laps,
            totalDistanceM: totalDistanceM, totalTimeS: totalTimeS,
            totalCalories: totalCalories, avgHeartRate: avgHR, maxHeartRate: maxHR,
            maxSpeedMps: maxSpeed, elevationGainM: elevGain, elevationLossM: elevLoss,
            firstLat: firstLat, firstLng: firstLng
        )
    }

    func parse(data: Data) -> ParseResult? {
        resetState()

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        parser.delegate = nil

        guard let startTime = activityStartTime, !laps.isEmpty else { return nil }

        let processed = processTrackpoints(rawTrackpoints)
        rawTrackpoints = []

        let totalDistanceM = laps.reduce(0.0) { $0 + $1.distanceM }
        let totalTimeS = laps.reduce(0.0) { $0 + $1.totalTimeS }
        let totalCalories = laps.reduce(0) { $0 + $1.calories }

        let hrLaps = laps.compactMap { $0.avgHeartRate }
        let avgHR = hrLaps.isEmpty ? nil : hrLaps.reduce(0, +) / hrLaps.count
        let maxHR = laps.compactMap { $0.maxHeartRate }.max()

        var maxSpeed = 0.0
        for tp in processed {
            if let s = tp.speedMps, s > maxSpeed { maxSpeed = s }
        }

        var elevGain = 0.0
        var elevLoss = 0.0
        for i in 1..<processed.count {
            let diff = processed[i].altitudeM - processed[i - 1].altitudeM
            if diff > 0 { elevGain += diff }
            else { elevLoss += abs(diff) }
        }

        return ParseResult(
            sport: sport,
            startTime: startTime,
            laps: laps,
            trackpoints: processed,
            totalDistanceM: totalDistanceM,
            totalTimeS: totalTimeS,
            totalCalories: totalCalories,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            maxSpeedMps: maxSpeed,
            elevationGainM: elevGain,
            elevationLossM: elevLoss
        )
    }

    private func resetState() {
        currentText = ""
        elementStack = []
        sport = ""
        activityStartTime = nil
        laps = []
        rawTrackpoints = []
        currentLap = nil
        currentTrackpoint = nil
        inLapAvgHR = false
        inLapMaxHR = false
        inTrackpointHR = false
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "Activity":
            sport = attributes["Sport"] ?? "Running"
        case "Lap":
            if let s = attributes["StartTime"], let d = Self.parseDate(s) {
                currentLap = ParsedLap(startTime: d)
            }
        case "Trackpoint":
            currentTrackpoint = RawTrackpoint()
        case "AverageHeartRateBpm":
            if currentTrackpoint == nil { inLapAvgHR = true }
        case "MaximumHeartRateBpm":
            if currentTrackpoint == nil { inLapMaxHR = true }
        case "HeartRateBpm":
            if currentTrackpoint != nil { inTrackpointHR = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentTrackpoint != nil {
            handleTrackpointElement(elementName, text: text)
        } else if currentLap != nil {
            handleLapElement(elementName, text: text)
        } else {
            handleTopElement(elementName, text: text)
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
        currentText = ""
    }

    private func handleTrackpointElement(_ name: String, text: String) {
        switch name {
        case "Time":
            currentTrackpoint?.time = Self.parseDate(text)
        case "LatitudeDegrees":
            currentTrackpoint?.lat = Double(text)
        case "LongitudeDegrees":
            currentTrackpoint?.lng = Double(text)
        case "AltitudeMeters":
            currentTrackpoint?.altitudeM = Double(text)
        case "DistanceMeters":
            currentTrackpoint?.distanceM = Double(text)
        case "Value":
            if inTrackpointHR {
                currentTrackpoint?.heartRate = Int(Double(text) ?? 0)
            }
        case "Speed":
            currentTrackpoint?.speedMps = Double(text)
        case "HeartRateBpm":
            inTrackpointHR = false
        case "Trackpoint":
            if let tp = currentTrackpoint, tp.time != nil {
                rawTrackpoints.append(tp)
            }
            currentTrackpoint = nil
        default:
            if name.hasSuffix(":Speed") {
                currentTrackpoint?.speedMps = Double(text)
            }
        }
    }

    private func handleLapElement(_ name: String, text: String) {
        switch name {
        case "TotalTimeSeconds":
            currentLap?.totalTimeS = Double(text) ?? 0
        case "DistanceMeters":
            currentLap?.distanceM = Double(text) ?? 0
        case "Calories":
            currentLap?.calories = Int(text) ?? 0
        case "Value":
            if inLapAvgHR { currentLap?.avgHeartRate = Int(Double(text) ?? 0) }
            else if inLapMaxHR { currentLap?.maxHeartRate = Int(Double(text) ?? 0) }
        case "AverageHeartRateBpm":
            inLapAvgHR = false
        case "MaximumHeartRateBpm":
            inLapMaxHR = false
        case "Lap":
            if let lap = currentLap { laps.append(lap) }
            currentLap = nil
        default:
            break
        }
    }

    private func handleTopElement(_ name: String, text: String) {
        if name == "Id" && activityStartTime == nil {
            activityStartTime = Self.parseDate(text)
        }
    }

    // MARK: - Trackpoint Post-Processing

    private func processTrackpoints(_ raw: [RawTrackpoint]) -> [TrackpointData] {
        guard !raw.isEmpty else { return [] }

        let metricPoints = raw.filter { $0.hasDistance }
        let gpsPoints = raw.filter { $0.hasPosition }

        var distTimeline: [(time: Date, value: Double)] = []
        if !metricPoints.isEmpty {
            let distances = metricPoints.compactMap { $0.distanceM }
            let isSegment = detectSegmentBased(distances)

            if isSegment {
                var cum = 0.0
                for mp in metricPoints {
                    if let d = mp.distanceM, let t = mp.time {
                        cum += d
                        distTimeline.append((t, cum))
                    }
                }
            } else {
                for mp in metricPoints {
                    if let d = mp.distanceM, let t = mp.time {
                        distTimeline.append((t, d))
                    }
                }
            }
        }

        var gpsTimeline: [(time: Date, lat: Double, lng: Double)] = []
        for gp in gpsPoints {
            if let t = gp.time, let lat = gp.lat, let lng = gp.lng {
                gpsTimeline.append((t, lat, lng))
            }
        }

        var altTimeline: [(time: Date, value: Double)] = []
        for tp in raw {
            if let t = tp.time, let alt = tp.altitudeM {
                altTimeline.append((t, alt))
            }
        }

        // Build dictionary for O(1) lookup instead of O(n) linear scan
        var rawByTime: [Date: RawTrackpoint] = [:]
        rawByTime.reserveCapacity(raw.count)
        for tp in raw {
            if let t = tp.time { rawByTime[t] = tp }
        }

        let sortedTimes = rawByTime.keys.sorted()

        var result: [TrackpointData] = []
        result.reserveCapacity(sortedTimes.count)
        for time in sortedTimes {
            let dist = interpolateValue(at: time, in: distTimeline)
            let coords = interpolateCoords(at: time, in: gpsTimeline)
            let alt = interpolateValue(at: time, in: altTimeline)
            let original = rawByTime[time]

            guard let lat = coords?.lat ?? original?.lat,
                  let lng = coords?.lng ?? original?.lng else { continue }

            result.append(TrackpointData(
                time: time,
                lat: lat,
                lng: lng,
                altitudeM: alt ?? original?.altitudeM ?? 0,
                distanceM: dist ?? 0,
                heartRate: original?.heartRate,
                speedMps: original?.speedMps
            ))
        }

        return result
    }

    private func detectSegmentBased(_ distances: [Double]) -> Bool {
        guard distances.count >= 3 else { return false }
        var nonMono = 0
        for i in 1..<distances.count {
            if distances[i] < distances[i - 1] * 0.9 { nonMono += 1 }
        }
        return Double(nonMono) / Double(distances.count - 1) > 0.2
    }

    // Binary search to find the insertion point for a given time
    private func bsearch(time: Date, count: Int, timeAt: (Int) -> Date) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if timeAt(mid) < time { lo = mid + 1 }
            else { hi = mid }
        }
        return lo
    }

    private func interpolateValue(at time: Date, in timeline: [(time: Date, value: Double)]) -> Double? {
        guard !timeline.isEmpty else { return nil }

        let idx = bsearch(time: time, count: timeline.count) { timeline[$0].time }

        if idx < timeline.count && timeline[idx].time == time { return timeline[idx].value }
        if idx == 0 { return timeline.first?.value }
        if idx >= timeline.count { return timeline.last?.value }

        let prev = timeline[idx - 1]
        let next = timeline[idx]
        let total = next.time.timeIntervalSince(prev.time)
        guard total > 0 else { return prev.value }
        let frac = time.timeIntervalSince(prev.time) / total
        return prev.value + (next.value - prev.value) * frac
    }

    private func interpolateCoords(at time: Date, in timeline: [(time: Date, lat: Double, lng: Double)]) -> (lat: Double, lng: Double)? {
        guard !timeline.isEmpty else { return nil }

        let idx = bsearch(time: time, count: timeline.count) { timeline[$0].time }

        if idx < timeline.count && timeline[idx].time == time {
            return (timeline[idx].lat, timeline[idx].lng)
        }
        if idx == 0 {
            guard let first = timeline.first else { return nil }
            return (first.lat, first.lng)
        }
        if idx >= timeline.count {
            guard let last = timeline.last else { return nil }
            return (last.lat, last.lng)
        }

        let prev = timeline[idx - 1]
        let next = timeline[idx]
        let total = next.time.timeIntervalSince(prev.time)
        guard total > 0 else { return (prev.lat, prev.lng) }
        let frac = time.timeIntervalSince(prev.time) / total
        return (
            prev.lat + (next.lat - prev.lat) * frac,
            prev.lng + (next.lng - prev.lng) * frac
        )
    }
}
