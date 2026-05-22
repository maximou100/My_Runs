import Foundation

/// Parses GPX files (Runkeeper exports, Strava bulk archive, generic GPS).
/// Produces a LiteResult compatible with the import pipeline plus raw trackpoints
/// so the caller can persist them as JSON via TrackpointStore.
nonisolated final class GPXParserService: NSObject, XMLParserDelegate {

    struct LiteResult {
        var sport: String
        var startTime: Date
        var laps: [TCXParserService.ParsedLap]
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
        var trackpoints: [TrackpointData]
    }

    private var currentText = ""
    private var sport = "Running"

    private struct RawTrackpoint {
        var time: Date?
        var lat: Double?
        var lng: Double?
        var ele: Double?
        var hr: Int?
        var speed: Double?
    }

    private var raw: [RawTrackpoint] = []
    private var current: RawTrackpoint?

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

    func parseLite(data: Data) -> LiteResult? {
        currentText = ""
        sport = "Running"
        raw = []
        current = nil

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        parser.delegate = nil

        let valid = raw.filter { $0.time != nil && $0.lat != nil && $0.lng != nil }
        guard valid.count >= 2 else { return nil }

        var totalDist = 0.0
        var maxSpeed = 0.0
        var elevGain = 0.0
        var elevLoss = 0.0
        var lastAlt: Double?
        var lastLat: Double?
        var lastLng: Double?
        var hrSum = 0
        var hrCount = 0
        var maxHR = 0

        var trackpoints: [TrackpointData] = []
        trackpoints.reserveCapacity(valid.count)

        for r in valid {
            let lat = r.lat!
            let lng = r.lng!
            let time = r.time!
            let alt = r.ele ?? 0

            if let llat = lastLat, let llng = lastLng {
                totalDist += haversine(llat, llng, lat, lng)
            }
            if let prev = lastAlt {
                let d = alt - prev
                if d > 0 { elevGain += d } else { elevLoss += -d }
            }
            if let s = r.speed, s > maxSpeed { maxSpeed = s }
            if let hr = r.hr {
                hrSum += hr; hrCount += 1
                if hr > maxHR { maxHR = hr }
            }

            trackpoints.append(TrackpointData(
                time: time, lat: lat, lng: lng,
                altitudeM: alt, distanceM: totalDist,
                heartRate: r.hr, speedMps: r.speed
            ))

            lastAlt = alt; lastLat = lat; lastLng = lng
        }

        let startTime = trackpoints.first!.time
        let endTime = trackpoints.last!.time
        let totalTimeS = endTime.timeIntervalSince(startTime)

        let lap = TCXParserService.ParsedLap(
            startTime: startTime,
            totalTimeS: totalTimeS,
            distanceM: totalDist,
            calories: 0,
            avgHeartRate: hrCount > 0 ? hrSum / hrCount : nil,
            maxHeartRate: maxHR > 0 ? maxHR : nil
        )

        return LiteResult(
            sport: sport,
            startTime: startTime,
            laps: [lap],
            totalDistanceM: totalDist,
            totalTimeS: totalTimeS,
            totalCalories: 0,
            avgHeartRate: hrCount > 0 ? hrSum / hrCount : nil,
            maxHeartRate: maxHR > 0 ? maxHR : nil,
            maxSpeedMps: maxSpeed,
            elevationGainM: elevGain,
            elevationLossM: elevLoss,
            firstLat: trackpoints.first?.lat ?? 0,
            firstLng: trackpoints.first?.lng ?? 0,
            trackpoints: trackpoints
        )
    }

    private func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: - XMLParserDelegate

    private func localName(_ name: String) -> String {
        if let colon = name.firstIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentText = ""
        switch localName(elementName) {
        case "trkpt":
            var tp = RawTrackpoint()
            tp.lat = attributes["lat"].flatMap(Double.init)
            tp.lng = attributes["lon"].flatMap(Double.init)
            current = tp
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
        let name = localName(elementName)

        if current != nil {
            switch name {
            case "ele":   current?.ele = Double(text)
            case "time":  current?.time = Self.parseDate(text)
            case "hr":    current?.hr = Int(text)
            case "speed": current?.speed = Double(text)
            case "trkpt":
                if let tp = current { raw.append(tp) }
                current = nil
            default: break
            }
        } else {
            switch name {
            case "type":
                if !text.isEmpty { sport = normalizedSport(text) }
            default: break
            }
        }
        currentText = ""
    }

    private func normalizedSport(_ s: String) -> String {
        let lower = s.lowercased()
        if lower.contains("run") { return "Running" }
        if lower.contains("bike") || lower.contains("cycling") || lower.contains("ride") { return "Cycling" }
        if lower.contains("walk") || lower.contains("hike") { return "Walking" }
        return s
    }
}
