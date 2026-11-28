import Foundation
import LedgeKit

/// What's saved: how long before an event the closed notch reminds about it, in minutes; 0 is off.
public struct Saved: Codable, Sendable, Equatable {
    public var remindMinutes: Int = 10
    public init() {}
}

/// Whether macOS lets Ledge read the calendars. Ledge asks for it from Calendar's settings, not the add-on.
public enum Access: Sendable, Equatable {
    case allowed, notAsked, denied
}

/// Everything the surfaces show, built from the events the program reads and the time.
public struct CalendarModel: Sendable {
    public static let reminderChoices = [0, 5, 10, 15]

    public var saved = Saved()
    public var access = Access.notAsked
    /// Today's and tomorrow's events, as read; the model leaves out what's over.
    public var events: [CalendarEvent] = []
    public var problem: String?

    public init(saved: Saved = Saved()) {
        self.saved = saved
    }

    public var remindBefore: TimeInterval? {
        saved.remindMinutes > 0 ? TimeInterval(saved.remindMinutes * 60) : nil
    }

    // MARK: What the person did

    /// What to do outside the model: open a meeting link, or Calendar.
    public enum Effect: Equatable, Sendable {
        case open(URL)
        case openCalendar
    }

    public mutating func handle(_ event: SurfaceEvent, now: Date) -> Effect? {
        switch (event.control, event.action) {
        case ("remind", .picked(let value)):
            if let minutes = Int(value), Self.reminderChoices.contains(minutes) { saved.remindMinutes = minutes }
            return nil
        case ("join", .pressed):
            return joinable(at: now).flatMap(CalendarRules.meetingLink).map(Effect.open)
        case ("events", .pressed), ("open-calendar", .pressed):
            return .openCalendar
        default:
            return nil
        }
    }

    /// The event Join is for: the next one today, while it has a meeting link.
    func joinable(at now: Date) -> CalendarEvent? {
        guard let next = today(at: now).first, CalendarRules.meetingLink(for: next) != nil else { return nil }
        return next
    }

    private func today(at now: Date) -> [CalendarEvent] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return CalendarRules.upcoming(events, at: now).filter { $0.start < tomorrow }
    }

    // MARK: Words

    static let needsAccess = "Allow Calendars in Calendar's settings in Ledge."

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "In 8 min · 7:39 PM" for the first event, "9:06 PM" for the rest, "Tomorrow 9:00 AM" after today.
    func when(_ event: CalendarEvent, first: Bool, now: Date) -> String {
        let startOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        if event.start >= startOfTomorrow { return "Tomorrow " + Self.time(event.start) }
        guard first else { return Self.time(event.start) }
        let countdown = CalendarRules.countdown(to: event, at: now)
        return countdown.prefix(1).uppercased() + countdown.dropFirst() + " · " + Self.time(event.start)
    }

    static func title(_ event: CalendarEvent) -> String { event.title.isEmpty ? "Untitled" : event.title }

    // MARK: Widget

    public func widget(now: Date) -> Widget {
        Widget("next", title: "Calendar", symbol: "calendar", content: widgetBody(limit: 2, now: now),
               compactContent: widgetBody(limit: 1, now: now))
    }

    private func widgetBody(limit: Int, now: Date) -> WidgetNode {
        guard access == .allowed else { return .text(problem ?? Self.needsAccess, style: .secondary) }
        let today = today(at: now)
        guard !today.isEmpty else {
            let tomorrow = CalendarRules.upcoming(events, at: now).first
            return .vstack(spacing: 4, children: [
                .text("Nothing else today", style: .body),
                .text(tomorrow.map { Self.title($0) + " · " + when($0, first: false, now: now) } ?? "Nothing tomorrow either",
                      style: .secondary),
            ])
        }
        let join = joinable(at: now) != nil
        return .vstack(spacing: 6, children: today.prefix(limit).enumerated().map { index, event in
            var row: [WidgetNode] = [
                .vstack(spacing: 1, children: [.text(Self.title(event), style: .body),
                                               .text(when(event, first: index == 0, now: now), style: .secondary)]),
                .spacer,
            ]
            if index == 0, join { row.append(.button(id: "join", title: "Join", symbol: "video.fill")) }
            return .hstack(spacing: 8, children: row)
        })
    }

    // MARK: Notch page

    public func page(now: Date) -> NotchPage {
        NotchPage(title: "Calendar", symbol: "calendar", size: .medium, screen: PageScreen("today", content: pageBody(now: now)))
    }

    private func pageBody(now: Date) -> PageNode {
        guard access == .allowed else {
            return .empty(symbol: "calendar", title: "Calendar needs access",
                          detail: problem ?? "In Ledge's Settings, open Calendar under Add-ons and choose Allow… beside calendars.")
        }
        let upcoming = CalendarRules.upcoming(events, at: now)
        guard !upcoming.isEmpty else {
            return .empty(symbol: "calendar", title: "Nothing today or tomorrow", detail: nil)
        }
        var header: [PageNode] = []
        if let next = upcoming.first {
            header = [.hstack(spacing: 8, children: [
                .text(Self.title(next), style: .title),
                .spacer,
                .text(when(next, first: true, now: now), style: .secondary),
            ] + (joinable(at: now) == next ? [.control(PageButton("join", title: "Join", role: .accent, symbol: "video.fill", tint: .blue))] : []))]
        }
        let rows = upcoming.dropFirst().prefix(8).map { event in
            ListRow(event.id, title: Self.title(event), subtitle: when(event, first: false, now: now), symbol: "circle.fill")
        }
        return .vstack(spacing: 8, children: header + (rows.isEmpty ? [] : [.list(id: "events", rows: Array(rows))]))
    }

    // MARK: Beside the notch

    /// From Remind me before ahead of an event until 5 minutes after it starts: "Design review in 8 min", then "now".
    /// A click opens the page, where Join is.
    public func activities(now: Date) -> [LiveActivity] {
        guard access == .allowed, let before = remindBefore,
              let event = CalendarRules.reminding(events, at: now, before: before) else { return [] }
        let countdown = CalendarRules.countdown(to: event, at: now)
        let left = event.start.timeIntervalSince(now)
        return [LiveActivity("meeting", symbol: "calendar", text: Self.title(event) + " " + countdown,
                             progress: left > 0 ? .fraction(1 - left / before) : .done,
                             importance: left > 0 ? .normal : .high,
                             accessibilityValue: Self.title(event) + ", " + countdown)]
    }

    /// When what shows next changes: the next event boundary or whole minute, for the countdown.
    public func nextChange(after now: Date) -> Date {
        let minute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(60)
        return min(minute, CalendarRules.nextChange(events, at: now, before: remindBefore) ?? minute)
    }

    // MARK: Settings

    public func settingsPage() -> SettingsPage {
        let access: SettingsRow = switch self.access {
        case .allowed: .note("access", "Ledge can read your calendars. It never changes them, and nothing leaves this Mac.")
        case .notAsked: .note("access", "To show your events, choose Allow… beside calendars above, and allow Calendars when macOS asks.")
        case .denied: .note("access", "Calendars is turned off for Ledge. Choose Open Settings beside calendars above to turn it on.")
        }
        return SettingsPage([
            SettingsSection("calendar", rows: [
                .picker("remind", "Remind me before", detail: "Shows the event beside the notch, counting down, until 5 minutes after it starts. Click it for Join.",
                        options: Self.reminderChoices.map { .init(String($0), $0 == 0 ? "Off" : "\($0) minutes") },
                        selected: String(saved.remindMinutes)),
                access,
            ]),
        ], keywords: ["calendar", "events", "meetings", "zoom", "google meet", "teams", "agenda", "schedule"])
    }
}
