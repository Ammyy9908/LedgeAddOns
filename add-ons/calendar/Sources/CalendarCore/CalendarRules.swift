import Foundation

/// An event from the Mac's calendars, as the widget, the page and the meeting reminder see it. The program fills it
/// from EventKit; the rules here only decide what to show.
public struct CalendarEvent: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isDeclined: Bool
    public let url: URL?
    public let location: String?
    public let notes: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, isDeclined: Bool = false,
                url: URL? = nil, location: String? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.url = url
        self.location = location
        self.notes = notes
    }
}

public enum CalendarRules {
    /// How long after an event starts the reminder stays up, and the countdown says "now".
    public static let nowWindow: TimeInterval = 5 * 60

    /// Events still worth showing, soonest first: not all-day, not declined, not over. One on now comes before one
    /// starting later.
    public static func upcoming(_ events: [CalendarEvent], at now: Date) -> [CalendarEvent] {
        events
            .filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }
            .sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
    }

    public static func next(_ events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        upcoming(events, at: now).first
    }

    /// The event the closed notch should remind about: from `before` ahead of its start until `nowWindow` after it
    /// (or its end, if sooner). Nil `before` means reminders are off.
    public static func reminding(_ events: [CalendarEvent], at now: Date, before: TimeInterval?) -> CalendarEvent? {
        guard let before else { return nil }
        return upcoming(events, at: now).first { event in
            now >= event.start.addingTimeInterval(-before) && now < min(event.start.addingTimeInterval(nowWindow), event.end)
        }
    }

    /// When what's shown next changes, so one timer can wait for it instead of polling.
    public static func nextChange(_ events: [CalendarEvent], at now: Date, before: TimeInterval?) -> Date? {
        upcoming(events, at: now)
            .flatMap { event in
                [before.map { event.start.addingTimeInterval(-$0) }, event.start,
                 event.start.addingTimeInterval(nowWindow), event.end].compactMap { $0 }
            }
            .filter { $0 > now }
            .min()
    }

    // MARK: - Countdown

    /// "in 8 min", "in 1 hr 5 min", "now", "ends in 12 min".
    public static func countdown(to event: CalendarEvent, at now: Date) -> String {
        if now < event.start {
            return "in " + duration(event.start.timeIntervalSince(now))
        }
        if now < event.start.addingTimeInterval(nowWindow) || now >= event.end {
            return "now"
        }
        return "ends in " + duration(event.end.timeIntervalSince(now))
    }

    /// Whole minutes, rounded up, so "in 1 min" lasts until it starts.
    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(rest) min"
        }
    }

    // MARK: - Meeting links

    /// Meeting services Join opens, by host. Matched exactly or as a subdomain (us02web.zoom.us).
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "facetime.apple.com"]

    /// The event's meeting link: its URL, then its location, then its notes. Only known meeting services, with a path,
    /// so a homepage or any other link in the notes isn't offered as Join.
    public static func meetingLink(for event: CalendarEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            if let found = links(in: text).first(where: isMeeting) { return found }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        return url.path.count > 1
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }
}
