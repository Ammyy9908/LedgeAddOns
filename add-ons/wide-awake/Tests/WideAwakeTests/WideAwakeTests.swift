import Foundation
import LedgeKit
import Testing
@testable import WideAwakeCore

private func press(_ control: String) -> SurfaceEvent { SurfaceEvent(surface: Surface.notchPage, control: control, action: .pressed) }
private func toggle(_ control: String, _ on: Bool) -> SurfaceEvent { SurfaceEvent(surface: Surface.settingsPage, control: control, action: .toggled(on)) }
private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func clockAndSpokenTimes() {
    #expect(clock(3600) == "1:00:00")
    #expect(clock(299.2) == "05:00")
    #expect(spoken(3900) == "1 hour 5 minutes")
    #expect(spoken(20) == "1 minute")
}

@Test func timerHoldsTheModeThenEnds() {
    var model = WideAwakeModel()
    model.handle(SurfaceEvent(surface: Surface.notchPage, control: "length", action: .changed(2000)), now: t0)
    #expect(model.saved.minutes == 1440)
    model.handle(SurfaceEvent(surface: Surface.notchPage, control: "length", action: .changed(30)), now: t0)
    model.handle(press("mode-system"), now: t0)
    model.handle(press("start"), now: t0)
    #expect(model.holding(at: t0 + 60) == .system)
    #expect(model.tint(at: t0 + 60) == .orange)
    #expect(model.tint(at: t0 + 1000) == .yellow)
    #expect(model.tint(at: t0 + 1600) == .red)
    let early = model.tick(now: t0 + 1799), ended = model.tick(now: t0 + 1800)
    #expect(!early && ended)
    #expect(model.saved.session == nil)
    #expect(model.holding(at: t0 + 1800) == nil)
}

@Test func untilStoppedHasNoEndAndPlusFifteenOnlyExtendsTimers() {
    var model = WideAwakeModel()
    model.handle(press("forever"), now: t0)
    model.handle(press("more"), now: t0)
    #expect(model.saved.session?.until == nil)
    let ended = model.tick(now: t0 + 86_400 * 3)
    #expect(!ended)
    #expect(model.holding(at: t0 + 86_400 * 3) == .display)
    model.handle(press("stop"), now: t0)
    #expect(model.saved.session == nil)
    model.handle(press("start"), now: t0)
    model.handle(press("more"), now: t0)
    #expect(model.saved.session?.until == t0 + 75 * 60)
}

@Test func triggersOnlyCountWhenTurnedOn() {
    var model = WideAwakeModel()
    model.conditions.pluggedIn = true
    model.conditions.openApps = ["keynote"]
    #expect(model.reasons.isEmpty)
    #expect(!model.saved.watches)
    model.handle(toggle("while-plugged-in", true), now: t0)
    #expect(model.reasons == ["Plugged in"])
    model.handle(toggle("while-apps", true), now: t0)
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "apps", action: .edited(" Keynote , Final Cut Pro")), now: t0)
    #expect(model.saved.appNames == ["keynote", "final cut pro"])
    #expect(model.reasons == ["Plugged in", "Keynote is open"])
    #expect(model.holding(at: t0) == .display)
}

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

@Test func aiToolsStartStopAndReport() throws {
    var model = WideAwakeModel()
    model.calendar = utc()
    try AddOnTool.validate(WideAwakeModel.tools)
    let started = try model.tool(ToolCall(tool: "keep_awake_start", arguments: ["minutes": .number(90), "mode": .string("system")]), now: t0)
    #expect(started == .text("The Mac is being kept awake (the Mac stays awake, the screen can turn off) until 3:16\u{202F}PM, 1 hour 30 minutes from now."))
    #expect(model.saved.session?.until == t0 + 90 * 60)
    // The page keeps the person's own length and mode.
    #expect(model.saved.minutes == 60 && model.saved.mode == .display)
    _ = try model.tool(ToolCall(tool: "keep_awake_start"), now: t0)
    #expect(model.saved.session?.until == nil)
    let stopped = try model.tool(ToolCall(tool: "keep_awake_stop"), now: t0)
    #expect(stopped == .text("The Mac sleeps normally."))
    var other = model
    #expect(throws: AddOnError.self) { _ = try other.tool(ToolCall(tool: "nope"), now: t0) }
}

@Test func savedSettingsSurviveMissingFields() throws {
    let saved = try JSONDecoder().decode(Saved.self, from: Data(#"{"minutes": 45, "whilePrinting": true}"#.utf8))
    #expect(saved.minutes == 45 && saved.whilePrinting && saved.mode == .display && saved.lockScreen)
}

@Test func surfacesFollowTheState() {
    var model = WideAwakeModel()
    #expect(model.activities(now: t0).isEmpty)
    #expect(model.lockScreenRow(now: t0) == nil)
    model.handle(press("start"), now: t0)
    #expect(model.activities(now: t0 + 60).first?.text == "59:00")
    #expect(model.lockScreenRow(now: t0 + 60)?.value == "59:00")
    model.handle(toggle("lock-screen", false), now: t0)
    #expect(model.lockScreenRow(now: t0 + 60) == nil)
    model.handle(press("stop"), now: t0)
    model.handle(press("forever"), now: t0)
    #expect(model.activities(now: t0).first?.progress == .indeterminate)
    #expect(model.widget(now: t0).id == "wide-awake")
}

@Test func untilATimeOfDay() throws {
    var model = WideAwakeModel()
    model.calendar = utc()
    // t0 is 1970-01-12 13:46:40 UTC.
    #expect(model.time("18:30", after: t0) == t0 + (4 * 3600 + 43 * 60 + 20))
    #expect(model.time("6:30 pm", after: t0) == model.time("18:30", after: t0))
    #expect(model.time("6pm", after: t0) == t0 + (4 * 3600 + 13 * 60 + 20))
    #expect(model.time("9 a.m.", after: t0) == t0 + (19 * 3600 + 13 * 60 + 20))
    #expect(model.time("13:46", after: t0) == t0 + (86_400 - 40))
    #expect(model.time("25:00", after: t0) == nil)
    #expect(model.time("13 pm", after: t0) == nil)
    #expect(model.time("soon", after: t0) == nil)

    let reply = try model.tool(ToolCall(tool: "keep_awake_start", arguments: ["until": .string("6:30 pm")]), now: t0)
    #expect(model.saved.session?.until == t0 + (4 * 3600 + 43 * 60 + 20))
    #expect(reply == .text("The Mac is being kept awake (the screen and the Mac stay awake) until 6:30\u{202F}PM, 4 hours 44 minutes from now."))
    #expect(model.saved.minutes == 60)
    var other = model
    #expect(throws: AddOnError.self) { _ = try other.tool(ToolCall(tool: "keep_awake_start", arguments: ["until": .string("later")]), now: t0) }
}
