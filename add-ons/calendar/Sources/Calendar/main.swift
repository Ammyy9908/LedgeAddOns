import AppKit
import CalendarCore
import EventKit
import Foundation
import LedgeKit

// Calendar: today's and tomorrow's events in the notch, read with EventKit and never changed. macOS counts this
// program as part of Ledge, so Ledge holds the Calendars permission and asks for it from this add-on's settings.
// Titles and links stay on the Mac and out of the log.

actor CalendarAddOn {
    private var model = CalendarModel()
    private let store = EKEventStore()
    private var clock: Task<Void, Never>?

    func start() async {
        do {
            if let saved = try await LedgeHost.value(Saved.self, forKey: "calendar") { model = CalendarModel(saved: saved) }
        } catch { model.problem = "Settings unavailable" }
        await refresh()
        clock = Task {
            while !Task.isCancelled {
                let next = await self.nextChange()
                try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
                await self.refresh()
            }
        }
    }

    func stop() { clock?.cancel() }

    func handle(_ event: SurfaceEvent) async {
        let before = model.saved
        let effect = model.handle(event, now: Date())
        if model.saved != before {
            do { try await LedgeHost.set(model.saved, forKey: "calendar") } catch { model.problem = "Couldn't save" }
        }
        switch effect {
        case .open(let url): _ = await MainActor.run { NSWorkspace.shared.open(url) }
        case .openCalendar: _ = await MainActor.run { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
        case nil: break
        }
        await refresh()
    }

    private func nextChange() -> Date { model.nextChange(after: Date()) }

    /// Reads the access and the events again, then sends every surface. Runs each minute and at each boundary, which
    /// also picks up access granted in Ledge and events changed in Calendar.
    // shortcut: rereads each minute instead of watching EKEventStoreChanged; that's one small local query a minute.
    private func refresh() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: model.access = .allowed
        case .notDetermined: model.access = .notAsked
        default: model.access = .denied
        }
        model.events = model.access == .allowed ? read() : []
        let now = Date()
        AddOnSession.show(model.settingsPage())
        AddOnSession.show(widgets: [model.widget(now: now)])
        AddOnSession.show(notchPage: model.page(now: now))
        AddOnSession.show(activities: model.activities(now: now))
    }

    private func read() -> [CalendarEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 2, to: start) else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).map { event in
            CalendarEvent(id: "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)", title: event.title ?? "",
                          start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                          isDeclined: event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined,
                          url: event.url, location: event.location, notes: event.notes)
        }
    }
}

let calendar = CalendarAddOn()
var handlers = AddOnHandlers()
handlers.activate = { await calendar.start() }
handlers.deactivate = { await calendar.stop() }
handlers.onEvent = { await calendar.handle($0) }
exit(await AddOnSession.run(id: "calendar", handlers: handlers))
