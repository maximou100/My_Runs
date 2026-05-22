import Foundation

/// Minimal Garmin FIT (Flexible and Interoperable Data Transfer) parser
/// covering the message types needed for activity files: file_id (#0),
/// record (#20), lap (#19), session (#18), activity (#34). Sufficient for
/// Garmin Connect bulk-export .fit files.
///
/// FIT format reference:
///   - 12-byte header (or 14-byte with CRC) followed by definition + data records.
///   - Each record header byte selects a local message type (0–15) and indicates
///     whether the record is a definition or a data message.
///   - Multi-byte fields use the architecture flag from the definition.
nonisolated final class FITParserService {

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

    private struct FieldDef {
        let number: UInt8
        let size: Int
        let baseType: UInt8
    }

    private struct MessageDef {
        let globalNum: UInt16
        let littleEndian: Bool
        let fields: [FieldDef]
        var totalSize: Int { fields.reduce(0) { $0 + $1.size } }
    }

    private static let mFileId: UInt16  = 0
    private static let mSession: UInt16 = 18
    private static let mLap: UInt16     = 19
    private static let mRecord: UInt16  = 20
    private static let mActivity: UInt16 = 34

    /// FIT timestamps are seconds since 1989-12-31 00:00:00 UTC.
    private static let fitEpoch = Date(timeIntervalSince1970: 631_065_600)

    func parseLite(data: Data) -> LiteResult? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return nil }

        let headerSize = Int(bytes[0])
        guard headerSize == 12 || headerSize == 14, bytes.count >= headerSize + 2 else { return nil }
        guard bytes[8] == 0x2E, bytes[9] == 0x46, bytes[10] == 0x49, bytes[11] == 0x54 else { return nil }

        let dataSize = Int(bytes[4]) | (Int(bytes[5]) << 8) | (Int(bytes[6]) << 16) | (Int(bytes[7]) << 24)
        var idx = headerSize
        let endIdx = min(idx + dataSize, bytes.count - 2)

        var defs: [UInt8: MessageDef] = [:]

        var trackpoints: [TrackpointData] = []
        var laps: [TCXParserService.ParsedLap] = []
        var sessionStart: Date?
        var sessionTotalTimeS = 0.0
        var sessionTotalDistanceM = 0.0
        var sessionCalories = 0
        var sessionAvgHR: Int?
        var sessionMaxHR: Int?
        var sessionMaxSpeed = 0.0
        var sessionAscent = 0.0
        var sessionDescent = 0.0
        var sessionStartLat: Double?
        var sessionStartLng: Double?
        var sport = "Running"
        var activityStart: Date?

        while idx < endIdx {
            guard idx < bytes.count else { break }
            let header = bytes[idx]
            idx += 1

            // Skip compressed-timestamp records (uncommon in activity files).
            if (header & 0x80) != 0 { continue }

            let isDefinition = (header & 0x40) != 0
            let hasDevData   = (header & 0x20) != 0
            let localType    = header & 0x0F

            if isDefinition {
                guard idx + 4 < bytes.count else { break }
                idx += 1 // reserved
                let arch = bytes[idx]; idx += 1
                let le = (arch == 0)
                let globalNum = readU16(bytes, idx, le: le)
                idx += 2
                let numFields = Int(bytes[idx]); idx += 1

                var fields: [FieldDef] = []
                fields.reserveCapacity(numFields)
                for _ in 0..<numFields {
                    guard idx + 2 < bytes.count else { return nil }
                    fields.append(FieldDef(
                        number: bytes[idx],
                        size: Int(bytes[idx + 1]),
                        baseType: bytes[idx + 2]
                    ))
                    idx += 3
                }
                if hasDevData {
                    guard idx < bytes.count else { return nil }
                    let numDev = Int(bytes[idx]); idx += 1
                    idx += numDev * 3
                }
                defs[localType] = MessageDef(globalNum: globalNum, littleEndian: le, fields: fields)
            } else {
                guard let def = defs[localType] else { return nil }
                let msgEnd = idx + def.totalSize
                guard msgEnd <= bytes.count else { return nil }

                // Index fields by their definition number for easy lookup.
                var fieldRanges: [UInt8: (Range<Int>, FieldDef)] = [:]
                var cursor = idx
                for f in def.fields {
                    fieldRanges[f.number] = (cursor..<(cursor + f.size), f)
                    cursor += f.size
                }

                switch def.globalNum {
                case Self.mRecord:
                    if let tp = parseRecord(bytes: bytes, fields: fieldRanges, le: def.littleEndian) {
                        if sessionStartLat == nil {
                            sessionStartLat = tp.lat; sessionStartLng = tp.lng
                        }
                        trackpoints.append(tp)
                    }
                case Self.mLap:
                    if let lap = parseLap(bytes: bytes, fields: fieldRanges, le: def.littleEndian) {
                        laps.append(lap)
                    }
                case Self.mSession:
                    parseSession(
                        bytes: bytes, fields: fieldRanges, le: def.littleEndian,
                        sessionStart: &sessionStart,
                        totalTimeS: &sessionTotalTimeS,
                        totalDistanceM: &sessionTotalDistanceM,
                        calories: &sessionCalories,
                        avgHR: &sessionAvgHR, maxHR: &sessionMaxHR,
                        maxSpeed: &sessionMaxSpeed,
                        ascent: &sessionAscent, descent: &sessionDescent,
                        startLat: &sessionStartLat, startLng: &sessionStartLng,
                        sport: &sport
                    )
                case Self.mActivity:
                    if let v = readU32(bytes, fieldRanges[2], le: def.littleEndian) {
                        activityStart = fitDate(v)
                    }
                default:
                    break
                }

                idx = msgEnd
            }
        }

        guard !trackpoints.isEmpty else { return nil }

        // Fall back to first/last trackpoint if session didn't populate totals.
        let startTime = sessionStart ?? activityStart ?? trackpoints.first!.time
        let totalTimeS = sessionTotalTimeS > 0
            ? sessionTotalTimeS
            : trackpoints.last!.time.timeIntervalSince(trackpoints.first!.time)
        let totalDistanceM = sessionTotalDistanceM > 0
            ? sessionTotalDistanceM
            : trackpoints.last!.distanceM

        if laps.isEmpty {
            laps = [TCXParserService.ParsedLap(
                startTime: startTime,
                totalTimeS: totalTimeS,
                distanceM: totalDistanceM,
                calories: sessionCalories,
                avgHeartRate: sessionAvgHR,
                maxHeartRate: sessionMaxHR
            )]
        }

        return LiteResult(
            sport: sport,
            startTime: startTime,
            laps: laps,
            totalDistanceM: totalDistanceM,
            totalTimeS: totalTimeS,
            totalCalories: sessionCalories,
            avgHeartRate: sessionAvgHR,
            maxHeartRate: sessionMaxHR,
            maxSpeedMps: sessionMaxSpeed,
            elevationGainM: sessionAscent,
            elevationLossM: sessionDescent,
            firstLat: sessionStartLat ?? 0,
            firstLng: sessionStartLng ?? 0,
            trackpoints: trackpoints
        )
    }

    // MARK: - Message handlers

    private func parseRecord(bytes: [UInt8],
                             fields: [UInt8: (Range<Int>, FieldDef)],
                             le: Bool) -> TrackpointData? {
        guard let tsRaw = readU32(bytes, fields[253], le: le) else { return nil }
        guard let latRaw = readS32(bytes, fields[0], le: le) else { return nil }
        guard let lngRaw = readS32(bytes, fields[1], le: le) else { return nil }

        let lat = semicirclesToDegrees(latRaw)
        let lng = semicirclesToDegrees(lngRaw)

        let dist: Double = readU32(bytes, fields[5], le: le).map { Double($0) / 100.0 } ?? 0

        var altitude: Double = 0
        if let raw = readU16(bytes, fields[2], le: le) {
            altitude = Double(raw) / 5.0 - 500.0
        }
        if let raw = readU32(bytes, fields[78], le: le) {
            altitude = Double(raw) / 5.0 - 500.0
        }

        let hr: Int? = readU8(bytes, fields[3]).map { Int($0) }

        var speed: Double? = nil
        if let raw = readU16(bytes, fields[6], le: le) {
            speed = Double(raw) / 1000.0
        }
        if let raw = readU32(bytes, fields[73], le: le) {
            speed = Double(raw) / 1000.0
        }

        return TrackpointData(
            time: fitDate(tsRaw),
            lat: lat, lng: lng,
            altitudeM: altitude,
            distanceM: dist,
            heartRate: hr,
            speedMps: speed
        )
    }

    private func parseLap(bytes: [UInt8],
                          fields: [UInt8: (Range<Int>, FieldDef)],
                          le: Bool) -> TCXParserService.ParsedLap? {
        guard let startRaw = readU32(bytes, fields[2], le: le) else { return nil }
        let totalTime = readU32(bytes, fields[8], le: le).map { Double($0) / 1000.0 }
            ?? readU32(bytes, fields[7], le: le).map { Double($0) / 1000.0 }
            ?? 0
        let distance = readU32(bytes, fields[9], le: le).map { Double($0) / 100.0 } ?? 0
        let calories = readU16(bytes, fields[11], le: le).map { Int($0) } ?? 0
        let avgHR = readU8(bytes, fields[15]).map { Int($0) }
        let maxHR = readU8(bytes, fields[16]).map { Int($0) }
        return TCXParserService.ParsedLap(
            startTime: fitDate(startRaw),
            totalTimeS: totalTime,
            distanceM: distance,
            calories: calories,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR
        )
    }

    private func parseSession(bytes: [UInt8],
                              fields: [UInt8: (Range<Int>, FieldDef)],
                              le: Bool,
                              sessionStart: inout Date?,
                              totalTimeS: inout Double,
                              totalDistanceM: inout Double,
                              calories: inout Int,
                              avgHR: inout Int?, maxHR: inout Int?,
                              maxSpeed: inout Double,
                              ascent: inout Double, descent: inout Double,
                              startLat: inout Double?, startLng: inout Double?,
                              sport: inout String) {
        if let v = readU32(bytes, fields[2], le: le) { sessionStart = fitDate(v) }
        if let v = readU32(bytes, fields[8], le: le) { totalTimeS = Double(v) / 1000.0 }
        else if let v = readU32(bytes, fields[7], le: le) { totalTimeS = Double(v) / 1000.0 }
        if let v = readU32(bytes, fields[9], le: le) { totalDistanceM = Double(v) / 100.0 }
        if let v = readU16(bytes, fields[11], le: le) { calories = Int(v) }
        if let v = readU8(bytes, fields[16]) { avgHR = Int(v) }
        if let v = readU8(bytes, fields[17]) { maxHR = Int(v) }
        if let v = readU16(bytes, fields[15], le: le) { maxSpeed = Double(v) / 1000.0 }
        if let v = readU16(bytes, fields[22], le: le) { ascent = Double(v) }
        if let v = readU16(bytes, fields[23], le: le) { descent = Double(v) }
        if let v = readS32(bytes, fields[3], le: le) { startLat = semicirclesToDegrees(v) }
        if let v = readS32(bytes, fields[4], le: le) { startLng = semicirclesToDegrees(v) }
        if let v = readU8(bytes, fields[5]) { sport = fitSportName(v) }
    }

    // MARK: - Numeric helpers (with FIT invalid-sentinel handling)

    private func readU16(_ bytes: [UInt8], _ offset: Int, le: Bool) -> UInt16 {
        let b0 = UInt16(bytes[offset])
        let b1 = UInt16(bytes[offset + 1])
        return le ? (b0 | (b1 << 8)) : (b1 | (b0 << 8))
    }

    private func readU8(_ bytes: [UInt8], _ field: (Range<Int>, FieldDef)?) -> UInt8? {
        guard let (range, _) = field, !range.isEmpty else { return nil }
        let v = bytes[range.lowerBound]
        return v == 0xFF ? nil : v
    }

    private func readU16(_ bytes: [UInt8], _ field: (Range<Int>, FieldDef)?, le: Bool) -> UInt16? {
        guard let (range, _) = field, range.count >= 2 else { return nil }
        let v = readU16(bytes, range.lowerBound, le: le)
        return v == 0xFFFF ? nil : v
    }

    private func readU32(_ bytes: [UInt8], _ field: (Range<Int>, FieldDef)?, le: Bool) -> UInt32? {
        guard let (range, _) = field, range.count >= 4 else { return nil }
        let lo = range.lowerBound
        let b0 = UInt32(bytes[lo])
        let b1 = UInt32(bytes[lo + 1])
        let b2 = UInt32(bytes[lo + 2])
        let b3 = UInt32(bytes[lo + 3])
        let v: UInt32 = le ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
                           : (b3 | (b2 << 8) | (b1 << 16) | (b0 << 24))
        return v == 0xFFFFFFFF ? nil : v
    }

    private func readS32(_ bytes: [UInt8], _ field: (Range<Int>, FieldDef)?, le: Bool) -> Int32? {
        guard let raw = readU32(bytes, field, le: le) else { return nil }
        let signed = Int32(bitPattern: raw)
        return signed == 0x7FFFFFFF ? nil : signed
    }

    private func semicirclesToDegrees(_ s: Int32) -> Double {
        Double(s) * (180.0 / 2_147_483_648.0)
    }

    private func fitDate(_ raw: UInt32) -> Date {
        Date(timeInterval: TimeInterval(raw), since: Self.fitEpoch)
    }

    private func fitSportName(_ id: UInt8) -> String {
        switch id {
        case 1:  return "Running"
        case 2:  return "Cycling"
        case 11: return "Walking"
        case 5:  return "Hiking"
        case 6:  return "Hiking"
        default: return "Running"
        }
    }
}
