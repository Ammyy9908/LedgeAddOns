import Foundation
import LedgeKit
import Testing
@testable import PomodoroCore

private func press(_ control: String) -> SurfaceEvent { SurfaceEvent(surface: Surface.notchPage, control: control, action: .pressed) }
private func length(_ minutes: Double) -> SurfaceEvent { SurfaceEvent(surface: Surface.notchPage, control: "length", action: .changed(minutes)) }
private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func clockReadsLikeATimer() {
    #expect(clock(1500) == "25:00")
    #expect(clock(299.2) == "05:00")
    #expect(clock(3900) == "1:05:00")
    #expect(spoken(61) == "1 minute 1 second")
}

@Test func eachModeKeepsItsOwnLength() {
    var model = PomodoroModel()
    model.handle(length(26), now: t0)
    #expect(model.saved.focusMinutes == 26)
    model.handle(press("mode-rest"), now: t0)
    model.handle(length(10), now: t0)
    #expect(model.saved.breakMinutes == 10)
    #expect(model.saved.focusMinutes == 26)
    model.handle(length(900), now: t0)
    #expect(model.saved.breakMinutes == 480)
}

@Test func pauseHoldsTheTimeAndResumeCarriesOn() {
    var model = PomodoroModel()
    model.handle(press("start"), now: t0)
    model.handle(press("pause"), now: t0 + 60)
    #expect(model.saved.run?.remaining(at: t0 + 600) == 1440)
    #expect(model.saved.run?.reading(at: t0 + 600) == "24:00")
    // Lengths can't change under a running session.
    model.handle(length(40), now: t0 + 60)
    #expect(model.saved.focusMinutes == 25)
    model.handle(press("resume"), now: t0 + 600)
    #expect(model.saved.run?.remaining(at: t0 + 660) == 1380)
    #expect(model.tick(now: t0 + 600 + 1439).ended == nil)
    #expect(model.tick(now: t0 + 600 + 1440).ended == .focus)
    // It keeps counting, as overtime, and says so only once.
    #expect(model.tick(now: t0 + 600 + 1500).ended == nil)
    #expect(model.saved.run?.reading(at: t0 + 600 + 1462) == "+00:22")
    model.handle(press("next"), now: t0 + 2100)
    #expect(model.saved.run?.mode == .rest)
    #expect(model.saved.run?.total == 300)
}

@Test func stopwatchCountsUpAndKeepsTheMode() {
    var model = PomodoroModel()
    model.handle(press("mode-rest"), now: t0)
    model.handle(press("stopwatch"), now: t0)
    #expect(model.saved.run?.reading(at: t0 + 35.6) == "00:35")
    #expect(model.tick(now: t0 + 9999).ended == nil)
    model.handle(press("next"), now: t0 + 40)
    #expect(model.saved.run?.mode == .stopwatch)
    model.handle(press("stop"), now: t0 + 41)
    #expect(model.saved.mode == .rest)
}

@Test func ambientPlaysOnlyWhileCountingDown() {
    var model = PomodoroModel()
    model.handle(press("ambient"), now: t0)
    #expect(model.saved.ambientOn)
    model.handle(press("mode-rest"), now: t0)
    model.handle(press("start"), now: t0)
    #expect(model.ambientPlaying(at: t0 + 1))
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "ambient-in-breaks", action: .toggled(false)), now: t0)
    #expect(!model.ambientPlaying(at: t0 + 1))
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "ambient-in-breaks", action: .toggled(true)), now: t0)
    #expect(!model.ambientPlaying(at: t0 + 400))
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "volume", action: .changed(55)), now: t0)
    #expect(model.saved.volume == 0.55)
}

@Test func secondsCanBeLeftOut() {
    #expect(clock(1499, seconds: false) == "25m")
    #expect(clock(30, seconds: false) == "1m")
    #expect(clock(3900, seconds: false) == "1h 05m")
    #expect(PomodoroModel.notice(for: .rest, minutes: 1).message == "Break is done · 1 minute Break finished")
}

@Test func startInstantlyOnlyWhenIdle() {
    var model = PomodoroModel()
    model.opened(now: t0)
    #expect(model.saved.run == nil)
    model.saved.startInstantly = true
    model.opened(now: t0)
    #expect(model.saved.run != nil)
}

@Test func savedStateSurvivesMissingFields() throws {
    let saved = try JSONDecoder().decode(Saved.self, from: Data(#"{"focusMinutes": 50}"#.utf8))
    #expect(saved.focusMinutes == 50)
    #expect(saved.breakMinutes == 5)
    // A setting from 0.1.0 that no longer reads ("off") falls back without losing the rest.
    let old = try JSONDecoder().decode(Saved.self, from: Data(#"{"focusMinutes": 40, "ambient": "off", "run": {"mode": "focus"}}"#.utf8))
    #expect(old.focusMinutes == 40)
    #expect(old.ambient == .rain)
    #expect(old.run == nil)
}

@Test func noiseStaysInRange() {
    for kind in Ambient.allCases {
        var noise = NoiseGenerator(kind)
        let samples = (0..<48_000).map { _ in noise.next() }
        #expect(samples.allSatisfy { abs($0) <= 1 })
        #expect(samples.contains { abs($0) > 0.05 })
    }
}

@Test func everySurfacePassesLedgesChecks() throws {
    var model = PomodoroModel()
    model.saved.customReminders = ["Stretch"]
    var states: [PomodoroModel] = [model]
    model.handle(press("start"), now: t0); states.append(model)
    model.handle(press("pause"), now: t0 + 5); states.append(model)
    model.handle(press("stop"), now: t0 + 5)
    model.handle(press("start"), now: t0); _ = model.tick(now: t0 + 1500); states.append(model)
    model.saved.showSeconds = false; states.append(model)
    model.handle(press("stop"), now: t0)
    model.handle(press("stopwatch"), now: t0); states.append(model)
    model.handle(press("stop"), now: t0)
    model.handle(press("mode-rest"), now: t0); states.append(model)
    for state in states {
        try state.page(now: t0 + 10).validate()
        try state.widget(now: t0 + 10).validate()
        try LiveActivity.validate(state.activities(now: t0 + 10))
        try state.lockScreenRow(now: t0 + 10)?.validate()
        try state.settingsPage().validate()
    }
}

@Test func remindersComeWhileWorkingAndOnlyOnceEach() {
    var model = PomodoroModel()
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "eye-break", action: .toggled(true)), now: t0)
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "new-reminder", action: .edited("  Stretch ")), now: t0)
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "add-reminder", action: .pressed), now: t0)
    #expect(model.saved.customReminders == ["Stretch"])
    #expect(model.newReminder.isEmpty)
    model.handle(length(60), now: t0)
    model.handle(press("start"), now: t0)
    #expect(model.tick(now: t0 + 1199).reminders.isEmpty)
    #expect(model.tick(now: t0 + 1200).reminders.map(\.id) == ["eye-break"])
    #expect(model.tick(now: t0 + 1260).reminders.isEmpty)
    #expect(model.tick(now: t0 + 1800).reminders.map(\.message) == ["Stretch"])
    // Not in a break.
    model.handle(press("next"), now: t0 + 3600)
    #expect(model.tick(now: t0 + 3600 + 1300).reminders.isEmpty)
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "remove-reminder:0", action: .pressed), now: t0)
    #expect(model.saved.customReminders.isEmpty)
}

@Test func alwaysShowOffKeepsTheTimerOffTheNotch() {
    var model = PomodoroModel()
    model.handle(press("start"), now: t0)
    #expect(model.activities(now: t0).count == 1)
    model.handle(SurfaceEvent(surface: Surface.settingsPage, control: "always-show", action: .toggled(false)), now: t0)
    #expect(model.activities(now: t0).isEmpty)
    #expect(model.lockScreenRow(now: t0) != nil)
}
