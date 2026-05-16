import Foundation

enum DistanceUnit: String, CaseIterable {
    case km, miles
    var label: String { self == .km ? "Kilometers" : "Miles" }
    var short: String { self == .km ? "km" : "mi" }
}

enum SpeedUnit: String, CaseIterable {
    case kmh, mph
    var label: String { self == .kmh ? "km/h" : "mph" }
}

enum PaceUnit: String, CaseIterable {
    case minPerKm, minPerMile
    var label: String { self == .minPerKm ? "min/km" : "min/mi" }
    var short: String { self == .minPerKm ? "/km" : "/mi" }
}

enum AltitudeUnit: String, CaseIterable {
    case meters, feet
    var label: String { self == .meters ? "Meters" : "Feet" }
    var short: String { self == .meters ? "m" : "ft" }
}

enum Fmt {
    static var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "") ?? .km
    }
    static var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: UserDefaults.standard.string(forKey: "speedUnit") ?? "") ?? .kmh
    }
    static var paceUnit: PaceUnit {
        PaceUnit(rawValue: UserDefaults.standard.string(forKey: "paceUnit") ?? "") ?? .minPerKm
    }
    static var altitudeUnit: AltitudeUnit {
        AltitudeUnit(rawValue: UserDefaults.standard.string(forKey: "altitudeUnit") ?? "") ?? .meters
    }

    static func pace(_ minPerKm: Double) -> String {
        guard minPerKm.isFinite && minPerKm > 0 && minPerKm < 100 else { return "--:--" }
        let value = paceUnit == .minPerMile ? minPerKm * 1.60934 : minPerKm
        let totalSeconds = Int(value * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static var paceLabel: String { paceUnit.short }

    static func distance(_ meters: Double) -> String {
        let unit = distanceUnit
        let value = unit == .miles ? meters / 1609.34 : meters / 1000
        let abbr = unit.short
        if value >= 100 {
            return String(format: "%.0f %@", value, abbr)
        } else if value >= 10 {
            return String(format: "%.1f %@", value, abbr)
        } else {
            return String(format: "%.2f %@", value, abbr)
        }
    }

    static func distanceShort(_ meters: Double) -> String {
        let value = distanceUnit == .miles ? meters / 1609.34 : meters / 1000
        if value >= 10 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }

    static var distanceLabel: String { distanceUnit.short }

    static func distanceValue(_ meters: Double) -> Double {
        distanceUnit == .miles ? meters / 1609.34 : meters / 1000
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    static func durationLong(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    static func elevation(_ meters: Double) -> String {
        let value = altitudeUnit == .feet ? meters * 3.28084 : meters
        let abbr = altitudeUnit.short
        if meters >= 0 {
            return String(format: "+%.0f %@", value, abbr)
        } else {
            return String(format: "%.0f %@", value, abbr)
        }
    }

    static func altitudeValue(_ meters: Double) -> Double {
        altitudeUnit == .feet ? meters * 3.28084 : meters
    }

    static var altitudeLabel: String { altitudeUnit.short }

    static func calories(_ cal: Int) -> String {
        if cal >= 1000 {
            return String(format: "%.1fk", Double(cal) / 1000)
        }
        return "\(cal)"
    }

    static func flag(_ countryCode: String?) -> String {
        guard let code = countryCode, code.count == 2 else { return "" }
        let base: UInt32 = 127397
        var emoji = ""
        for scalar in code.uppercased().unicodeScalars {
            if let flag = Unicode.Scalar(base + scalar.value) {
                emoji.append(String(flag))
            }
        }
        return emoji
    }

    static func dateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func dateLong(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d yyyy"
        return f.string(from: date)
    }

    static func timeOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func speed(_ mps: Double) -> String {
        let value = speedUnit == .mph ? mps * 2.23694 : mps * 3.6
        return String(format: "%.1f %@", value, speedUnit.label)
    }

    static func speedValue(_ mps: Double) -> Double {
        speedUnit == .mph ? mps * 2.23694 : mps * 3.6
    }

    static var speedLabel: String { speedUnit.label }

    static func runSummary(_ run: Run) -> String {
        var lines = [
            "MyRuns",
            Fmt.dateLong(run.startTime)
        ]
        if let city = run.city, let country = run.country {
            lines.append("\(city), \(country)")
        }
        lines.append("\(distance(run.totalDistanceM)) - \(run.category.displayName)")
        lines.append("\(duration(run.totalTimeS)) - Pace: \(pace(run.avgPaceMinPerKm)) \(paceLabel)")
        if run.elevationGainM > 0 {
            lines.append("\(elevation(run.elevationGainM)) elevation")
        }
        if run.calories > 0 {
            lines.append("\(run.calories) kcal")
        }
        return lines.joined(separator: "\n")
    }
}
