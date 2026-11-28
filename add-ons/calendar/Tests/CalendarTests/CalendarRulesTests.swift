import Foundation
import Testing
@testable import CalendarCore

private let nine = Date(timeIntervalSince1970: 1_800_000_000)
private func at(minutes: Double) -> Date { nine.addingTimeInterval(minutes * 60) }
private func event(_ title: String, from start: Double, to end: Double, allDay: Bool = false, declined: Bool = false,
                   url: String? = nil, location: String? = nil, notes: String? = nil) -> CalendarEvent {
    CalendarEvent(id: title, title: title, start: at(minutes: start), end: at(minutes: end), isAllDay: allDay,
                  isDeclined: declined, url: url.flatMap(URL.init(string:)), location: location, notes: notes)
}

@Test func nextSkipsAllDayDeclinedAndFinishedEvents() {
    let events = [
        event("Holiday", from: -540, to: 900, allDay: true),
        event("Declined", from: 10, to: 40, declined: true),
        event("Standup", from: -30, to: -15),
        event("Review", from: 60, to: 90),
        event("Design", from: 20, to: 50),
    ]
    #expect(CalendarRules.next(events, at: nine)?.title == "Design")
    #expect(CalendarRules.upcoming(events, at: nine).map(\.title) == ["Design", "Review"])
}

@Test func anEventOnNowComesFirst() {
    let events = [event("Later", from: 10, to: 40), event("Now", from: -5, to: 25)]
    #expect(CalendarRules.next(events, at: nine)?.title == "Now")
}

@Test func reminderRunsFromBeforeTheStartToFiveMinutesAfter() {
    let events = [event("Design", from: 20, to: 50)]
    #expect(CalendarRules.reminding(events, at: at(minutes: 9), before: 600) == nil)
    #expect(CalendarRules.reminding(events, at: at(minutes: 10), before: 600)?.title == "Design")
    #expect(CalendarRules.reminding(events, at: at(minutes: 24), before: 600)?.title == "Design")
    #expect(CalendarRules.reminding(events, at: at(minutes: 25), before: 600) == nil)
    #expect(CalendarRules.reminding(events, at: at(minutes: 15), before: nil) == nil)
}

@Test func aLongBlockDoesNotHideTheMeetingInsideIt() {
    let events = [event("Focus", from: -60, to: 180), event("Design", from: 60, to: 90)]
    #expect(CalendarRules.reminding(events, at: at(minutes: 55), before: 600)?.title == "Design")
}

@Test func nextChangeIsTheNearestBoundary() {
    let events = [event("Design", from: 20, to: 50)]
    #expect(CalendarRules.nextChange(events, at: nine, before: 600) == at(minutes: 10))
    #expect(CalendarRules.nextChange(events, at: at(minutes: 10), before: 600) == at(minutes: 20))
    #expect(CalendarRules.nextChange(events, at: at(minutes: 20), before: 600) == at(minutes: 25))
    #expect(CalendarRules.nextChange(events, at: at(minutes: 25), before: 600) == at(minutes: 50))
    #expect(CalendarRules.nextChange(events, at: nine, before: nil) == at(minutes: 20))
    #expect(CalendarRules.nextChange(events, at: at(minutes: 50), before: 600) == nil)
}

@Test func countdownWording() {
    let design = event("Design", from: 65, to: 125)
    #expect(CalendarRules.countdown(to: design, at: nine) == "in 1 hr 5 min")
    #expect(CalendarRules.countdown(to: design, at: at(minutes: 5)) == "in 1 hr")
    #expect(CalendarRules.countdown(to: design, at: at(minutes: 57)) == "in 8 min")
    #expect(CalendarRules.countdown(to: design, at: at(minutes: 64.9)) == "in 1 min")
    #expect(CalendarRules.countdown(to: design, at: at(minutes: 66)) == "now")
    #expect(CalendarRules.countdown(to: design, at: at(minutes: 113)) == "ends in 12 min")
}

@Test func meetingLinkFromURLThenLocationThenNotes() {
    #expect(CalendarRules.meetingLink(for: event("A", from: 0, to: 30, url: "https://us02web.zoom.us/j/123"))?
        .absoluteString == "https://us02web.zoom.us/j/123")
    #expect(CalendarRules.meetingLink(for: event("B", from: 0, to: 30, location: "https://meet.google.com/abc-defg-hij"))?
        .absoluteString == "https://meet.google.com/abc-defg-hij")
    let notes = "Agenda: https://docs.example.com/x\nJoin: https://teams.microsoft.com/l/meetup-join/19%3a"
    #expect(CalendarRules.meetingLink(for: event("C", from: 0, to: 30, notes: notes))?.host == "teams.microsoft.com")
}

@Test func otherLinksAreNotOfferedAsJoin() {
    #expect(CalendarRules.meetingLink(for: event("A", from: 0, to: 30, url: "https://example.com/j/123")) == nil)
    #expect(CalendarRules.meetingLink(for: event("B", from: 0, to: 30, notes: "See https://zoom.us")) == nil)
    #expect(CalendarRules.meetingLink(for: event("C", from: 0, to: 30, notes: "https://notzoom.us/j/1")) == nil)
    #expect(CalendarRules.meetingLink(for: event("D", from: 0, to: 30, url: "http://zoom.us/j/1")) == nil)
    #expect(CalendarRules.meetingLink(for: event("E", from: 0, to: 30, location: "Room 4")) == nil)
}
