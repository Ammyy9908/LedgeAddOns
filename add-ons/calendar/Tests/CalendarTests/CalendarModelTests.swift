import Foundation
import LedgeKit
import Testing
@testable import CalendarCore

private let now = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
private func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

private func model(_ events: [CalendarEvent], access: Access = .allowed) -> CalendarModel {
    var model = CalendarModel()
    model.access = access
    model.events = events
    return model
}

private let meeting = CalendarEvent(id: "m", title: "Design review", start: at(8), end: at(38),
                                    url: URL(string: "https://us02web.zoom.us/j/123"))
private let lunch = CalendarEvent(id: "l", title: "Lunch", start: at(90), end: at(150))

@Test func withoutAccessEverySurfaceSaysWhereToAllowIt() {
    let calendar = model([meeting], access: .notAsked)
    #expect(calendar.activities(now: now).isEmpty)
    #expect(calendar.widget(now: now).content == .text(CalendarModel.needsAccess, style: .secondary))
}

@Test func reminderCountsDownAndFillsItsRing() throws {
    let calendar = model([meeting, lunch])
    let reminder = try #require(calendar.activities(now: now).first)
    #expect(reminder.text == "Design review in 8 min")
    guard case .fraction(let filled) = reminder.progress else { Issue.record("no ring"); return }
    #expect(abs(filled - 0.2) < 0.001)
    var off = calendar
    off.saved.remindMinutes = 0
    #expect(off.activities(now: now).isEmpty)
}

@Test func joinOpensTheNextMeetingsLink() {
    var calendar = model([meeting, lunch])
    let effect = calendar.handle(SurfaceEvent(surface: Surface.widget, widget: "next", control: "join", action: .pressed), now: now)
    #expect(effect == .open(URL(string: "https://us02web.zoom.us/j/123")!))
    var noLink = model([lunch])
    #expect(noLink.handle(SurfaceEvent(surface: Surface.widget, widget: "next", control: "join", action: .pressed), now: now) == nil)
}

@Test func remindChoiceIsSavedOnlyWhenItsOffered() {
    var calendar = model([])
    _ = calendar.handle(SurfaceEvent(surface: Surface.settingsPage, control: "remind", action: .picked("5")), now: now)
    #expect(calendar.saved.remindMinutes == 5)
    _ = calendar.handle(SurfaceEvent(surface: Surface.settingsPage, control: "remind", action: .picked("7")), now: now)
    #expect(calendar.saved.remindMinutes == 5)
}

@Test func surfacesAreValid() throws {
    for calendar in [model([meeting, lunch]), model([]), model([meeting], access: .denied)] {
        try calendar.widget(now: now).validate()
        try calendar.page(now: now).validate()
        try calendar.settingsPage().validate()
    }
}
