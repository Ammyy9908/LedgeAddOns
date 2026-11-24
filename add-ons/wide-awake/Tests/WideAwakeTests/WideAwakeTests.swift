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

@Test func aiToolsStartStopAndReport() throws {
    var model = WideAwakeModel()
    try AddOnTool.validate(WideAwakeModel.tools)
    let started = try model.tool(ToolCall(tool: "keep_awake_start", arguments: ["minutes": .number(90), "mode": .string("system")]), now: t0)
    #expect(started == .text("The Mac is being kept awake (mac stays awake, screen can turn off) for 1 hour 30 minutes more."))
    #expect(model.saved.session?.until == t0 + 90 * 60)
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
