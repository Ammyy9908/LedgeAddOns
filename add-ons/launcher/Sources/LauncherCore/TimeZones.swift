import Foundation

/// "time in tokyo", "london time", "3pm london in nyc", "9:30 in delhi": a time in one place, shown in another.
public enum TimeZones {
    public struct Answer: Equatable, Sendable {
        /// Like "11:00 AM".
        public var time: String
        /// Like "New York · Sun, Oct 25 · UTC−4".
        public var detail: String
    }

    /// `now` and `here` stand in for the clock and this Mac's time zone, so the answers can be tested.
    public static func answer(_ text: String, now: Date = Date(), here: TimeZone = .current) -> Answer? {
        let text = text.lowercased().trimmingCharacters(in: .whitespaces)
        let clock = #"(\d{1,2}(?::\d{2})?\s*(?:am|pm)?|noon|midnight)"#
        // "time in tokyo", "tokyo time"
        if let match = text.firstMatch(#"^(?:what\s+)?time\s+(?:is\s+it\s+)?(?:in|at)\s+(.+)$"#) ?? text.firstMatch(#"^(.+?)\s+time$"#),
           let place = place(match[1]) {
            return show(now, in: place)
        }
        // "3pm london in nyc", "15:30 tokyo to london"
        if let match = text.firstMatch("^\(clock)\\s+(?:in\\s+)?(.+?)\\s+(?:in|to)\\s+(.+)$"),
           let from = place(match[2]), let to = place(match[3]),
           let moment = moment(match[1], in: from.zone, now: now) {
            return show(moment, in: to)
        }
        // "3pm in tokyo": this Mac's 3pm, there.
        if let match = text.firstMatch("^\(clock)\\s+(?:in|to)\\s+(.+)$"), let to = place(match[2]),
           let moment = moment(match[1], in: here, now: now) {
            return show(moment, in: to)
        }
        return nil
    }

    struct Place {
        var name: String
        var zone: TimeZone
    }

    /// A city, country or abbreviation people type, to a time zone and how it reads back.
    static func place(_ text: String) -> Place? {
        let key = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let (name, identifier) = aliases[key], let zone = TimeZone(identifier: identifier) { return Place(name: name, zone: zone) }
        let underscored = key.replacingOccurrences(of: " ", with: "_")
        if let identifier = TimeZone.knownTimeZoneIdentifiers.first(where: { $0.lowercased().split(separator: "/").last.map(String.init) == underscored }),
           let zone = TimeZone(identifier: identifier) {
            return Place(name: identifier.split(separator: "/").last!.replacingOccurrences(of: "_", with: " "), zone: zone)
        }
        if key.count <= 5, key.allSatisfy(\.isLetter), let zone = TimeZone(abbreviation: key.uppercased()) {
            return Place(name: key.uppercased(), zone: zone)
        }
        return nil
    }

    private static let aliases: [String: (String, String)] = [
        "nyc": ("New York", "America/New_York"), "new york": ("New York", "America/New_York"), "ny": ("New York", "America/New_York"),
        "la": ("Los Angeles", "America/Los_Angeles"), "sf": ("San Francisco", "America/Los_Angeles"),
        "san francisco": ("San Francisco", "America/Los_Angeles"), "seattle": ("Seattle", "America/Los_Angeles"),
        "boston": ("Boston", "America/New_York"), "washington": ("Washington", "America/New_York"), "miami": ("Miami", "America/New_York"),
        "dallas": ("Dallas", "America/Chicago"), "austin": ("Austin", "America/Chicago"), "chicago": ("Chicago", "America/Chicago"),
        "toronto": ("Toronto", "America/Toronto"), "vancouver": ("Vancouver", "America/Vancouver"),
        "london": ("London", "Europe/London"), "uk": ("London", "Europe/London"), "paris": ("Paris", "Europe/Paris"),
        "berlin": ("Berlin", "Europe/Berlin"), "madrid": ("Madrid", "Europe/Madrid"), "rome": ("Rome", "Europe/Rome"),
        "amsterdam": ("Amsterdam", "Europe/Amsterdam"), "dublin": ("Dublin", "Europe/Dublin"), "zurich": ("Zurich", "Europe/Zurich"),
        "india": ("India", "Asia/Kolkata"), "delhi": ("Delhi", "Asia/Kolkata"), "new delhi": ("New Delhi", "Asia/Kolkata"),
        "mumbai": ("Mumbai", "Asia/Kolkata"), "bangalore": ("Bangalore", "Asia/Kolkata"), "bengaluru": ("Bengaluru", "Asia/Kolkata"),
        "pune": ("Pune", "Asia/Kolkata"), "chennai": ("Chennai", "Asia/Kolkata"), "hyderabad": ("Hyderabad", "Asia/Kolkata"),
        "dubai": ("Dubai", "Asia/Dubai"), "singapore": ("Singapore", "Asia/Singapore"), "hong kong": ("Hong Kong", "Asia/Hong_Kong"),
        "beijing": ("Beijing", "Asia/Shanghai"), "shanghai": ("Shanghai", "Asia/Shanghai"), "china": ("China", "Asia/Shanghai"),
        "tokyo": ("Tokyo", "Asia/Tokyo"), "japan": ("Japan", "Asia/Tokyo"), "seoul": ("Seoul", "Asia/Seoul"),
        "sydney": ("Sydney", "Australia/Sydney"), "melbourne": ("Melbourne", "Australia/Melbourne"),
        "auckland": ("Auckland", "Pacific/Auckland"), "utc": ("UTC", "UTC"), "gmt": ("GMT", "GMT"),
    ]

    /// "3pm", "3:30 pm", "15:30", "noon" on `now`'s day in `zone`.
    static func moment(_ text: String, in zone: TimeZone, now: Date) -> Date? {
        var hour: Int
        var minute = 0
        switch text.replacingOccurrences(of: " ", with: "") {
        case "noon": hour = 12
        case "midnight": hour = 0
        case let clock:
            guard let match = clock.firstMatch(#"^(\d{1,2})(?::(\d{2}))?(am|pm)?$"#), let parsed = Int(match[1]) else { return nil }
            hour = parsed
            minute = Int(match[2]) ?? 0
            switch match[3] {
            case "am": guard (1...12).contains(hour) else { return nil }; if hour == 12 { hour = 0 }
            case "pm": guard (1...12).contains(hour) else { return nil }; if hour != 12 { hour += 12 }
            default: guard (0...23).contains(hour), !match[2].isEmpty || clock.count <= 2 else { return nil }
            }
            guard (0...59).contains(minute) else { return nil }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    private static func show(_ moment: Date, in place: Place) -> Answer {
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.timeZone = place.zone
        time.dateFormat = "h:mm a"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = place.zone
        day.dateFormat = "EEE, MMM d"
        let seconds = place.zone.secondsFromGMT(for: moment)
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        let offset = "UTC" + (seconds == 0 ? "" : (seconds > 0 ? "+" : "−") + "\(abs(hours))" + (minutes > 0 ? ":\(String(format: "%02d", minutes))" : ""))
        return Answer(time: time.string(from: moment), detail: "\(place.name) · \(day.string(from: moment)) · \(offset)")
    }
}
