import Foundation
import LedgeKit

extension Mode {
    public var symbol: String { ["focus": "timer", "rest": "cup.and.saucer.fill", "stopwatch": "stopwatch"][rawValue]! }
    /// Focus and the stopwatch are orange, Break is blue.
    public var tint: PageTint { self == .rest ? .blue : .orange }
}

extension PomodoroModel {
    // MARK: Notch page

    /// Like a kitchen timer in the notch: pick Focus or Break, drag the tape to a length, start, then pause or stop.
    public func page(now: Date) -> NotchPage {
        NotchPage(title: "Pomodoro", symbol: "timer", size: .small,
                  screen: PageScreen("timer", content: saved.run.map { running($0, now: now) } ?? picker()))
    }

    private func picker() -> PageNode {
        let mode = saved.mode, tint = mode.tint
        let ambientOn = saved.ambientOn
        return .vstack(spacing: 8, children: [
            .hstack(spacing: 6, children: [
                .spacer,
                .control(PageButton("mode-focus", title: "Focus", role: mode == .focus ? .selected : .secondary, tint: Mode.focus.tint)),
                .control(PageButton("mode-rest", title: "Break", role: mode == .rest ? .selected : .secondary, tint: Mode.rest.tint)),
                .spacer,
            ]),
            .tape(PageTape("length", value: minutes(mode), minimum: Length.range.lowerBound, maximum: Length.range.upperBound,
                           labelEvery: 5, tint: tint, accessibilityLabel: "\(mode.name) length in minutes")),
            .hstack(spacing: 6, children: [
                .control(PageButton("start", title: "Start Timer", role: .accent, tint: tint)),
                .control(PageButton("ambient", title: "", role: ambientOn ? .selected : .secondary,
                                    symbol: ambientOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                    accessibilityLabel: ambientOn ? "Turn off ambient sound" : "Turn on ambient sound", tint: tint)),
                .control(PageButton("stopwatch", title: "", role: .secondary, symbol: "stopwatch", accessibilityLabel: "Start a stopwatch")),
                .spacer,
                problem.map { .text($0, style: .caption) } ?? .display(clock(TimeInterval(minutes(mode) * 60)), tint: tint),
            ]),
        ])
    }

    private func running(_ run: Run, now: Date) -> PageNode {
        let label = run.isPaused && run.mode != .stopwatch ? "Paused" : run.mode.name
        return .hstack(spacing: 8, children: controls(run, now: now).map(PageNode.control) + [
            .spacer,
            .text(label, style: .secondary),
            .display(run.reading(at: now), tint: run.mode.tint),
        ])
    }

    /// Pause or resume, then, once the session has reached its length, the next one, then stop.
    private func controls(_ run: Run, now: Date) -> [PageButton] {
        let tint = run.mode.tint
        var buttons = [run.isPaused ? PageButton("resume", title: "", role: .accent, symbol: "play.fill", accessibilityLabel: "Resume", tint: tint)
                                    : PageButton("pause", title: "", role: .accent, symbol: "pause.fill", accessibilityLabel: "Pause", tint: tint)]
        if run.overtime(at: now) != nil {
            buttons.append(PageButton("next", title: "", role: .selected, symbol: "arrow.clockwise",
                                      accessibilityLabel: "Start " + (run.mode.next == .rest ? "the break" : "focusing"), tint: tint))
        }
        return buttons + [PageButton("stop", title: "", role: .secondary, symbol: "xmark", accessibilityLabel: "Stop")]
    }

    // MARK: Widget (also the iPhone tile)

    public func widget(now: Date) -> Widget {
        let line: String, time: String, buttons: [WidgetNode]
        if let run = saved.run {
            line = run.isPaused && run.mode != .stopwatch ? "Paused" : run.mode.name
            time = run.reading(at: now)
            buttons = [run.isPaused ? .button(id: "resume", title: "Resume", symbol: "play.fill") : .button(id: "pause", title: "Pause", symbol: "pause.fill")]
                + (run.overtime(at: now) != nil ? [.button(id: "next", title: run.mode.next.name, symbol: run.mode.next.symbol)] : [])
                + [.button(id: "stop", title: "Stop", symbol: "xmark")]
        } else {
            line = saved.mode.name
            time = clock(TimeInterval(minutes(saved.mode) * 60))
            buttons = [.button(id: "start", title: "Start", symbol: "play.fill"),
                       .button(id: saved.mode == .focus ? "mode-rest" : "mode-focus", title: saved.mode.next.name, symbol: saved.mode.next.symbol)]
        }
        let full: WidgetNode = .vstack(spacing: 8, children: [
            .hstack(spacing: 8, children: [.text(line, style: .secondary), .spacer, .text(time, style: .title)]),
            .hstack(spacing: 8, children: buttons + [.spacer]),
        ])
        let compact: WidgetNode = .vstack(spacing: 6, children: [
            .hstack(spacing: 6, children: [.text(line, style: .caption), .spacer, .text(time, style: .title)]),
            buttons[0],
        ])
        return Widget("pomodoro", title: "Pomodoro", symbol: "timer", content: full, compactContent: compact)
    }

    // MARK: Beside the notch and on the lock screen

    public func activities(now: Date) -> [LiveActivity] {
        guard saved.alwaysShow, let run = saved.run else { return [] }
        let over = run.overtime(at: now)
        let spokenTime = run.mode == .stopwatch ? spoken(run.elapsed(at: now).rounded(.down))
            : over.map { spoken($0.rounded(.down)) + " over" } ?? spoken(run.remaining(at: now)) + " left"
        return [LiveActivity("timer", symbol: run.isPaused ? "pause.fill" : run.mode.symbol, text: run.reading(at: now, seconds: saved.showSeconds),
                             progress: run.mode == .stopwatch ? nil : over == nil ? .fraction(run.progress(at: now)) : .done,
                             importance: over == nil ? .normal : .high,
                             accessibilityValue: (run.isPaused ? "Paused, " : run.mode.name + ", ") + spokenTime)]
    }

    public func lockScreenRow(now: Date) -> LockScreenRow? {
        guard let run = saved.run else { return nil }
        return LockScreenRow(symbol: run.isPaused ? "pause.fill" : run.mode.symbol,
                             label: run.isPaused && run.mode != .stopwatch ? "Paused" : run.mode.name,
                             value: run.reading(at: now, seconds: saved.showSeconds))
    }

    /// The notice when a session reaches its length.
    public static func notice(for mode: Mode, minutes: Int) -> (title: String, message: String) {
        ("Pomodoro complete", "\(mode.name) is done · \(minutes) minute \(mode.name) finished")
    }

    // MARK: Settings

    public func settingsPage() -> SettingsPage {
        let custom = saved.customReminders.enumerated().map { index, text in
            SettingsRow.button("remove-reminder:\(index)", "Remove", detail: text, destructive: true)
        }
        return SettingsPage([
            SettingsSection("timer", rows: [
                .toggle("start-instantly", "Start as soon as you open it", detail: "Opening Pomodoro starts your last timer.",
                        isOn: saved.startInstantly),
                .toggle("always-show", "Always show the timer in the notch",
                        detail: "Show the timer beside the notch for the whole session, not only on the page and lock screen.",
                        isOn: saved.alwaysShow),
                .picker("end-sound", "End sound", options: (["None"] + endSounds).map { .init($0, $0) }, selected: saved.endSound),
                .button("preview-end-sound", "Play", detail: "Hear the end sound."),
            ]),
            SettingsSection("more", title: "More options", rows: [
                .toggle("show-seconds", "Show seconds in the notch", isOn: saved.showSeconds),
            ]),
            SettingsSection("reminders", title: "Reminders", footer: "Small reminders in the notch while you work.", rows: [
                .toggle("eye-break", "Eye break", detail: "Look about 6 meters (20 feet) away for 20 seconds, every 20 minutes.",
                        isOn: saved.eyeBreak),
                .toggle("drink-water", "Drink water", detail: "Every 30 minutes.", isOn: saved.drinkWater),
                .toggle("stand-up", "Stand up", detail: "Every hour.", isOn: saved.standUp),
            ] + custom + [
                .textField("new-reminder", "New reminder", detail: "Shown every 30 minutes.", text: newReminder, placeholder: "Stretch your shoulders"),
                .button("add-reminder", "Add"),
            ]),
            SettingsSection("ambient", title: "Ambient sound", rows: [
                .toggle("ambient-on", "Enable ambient sound", isOn: saved.ambientOn),
                .picker("ambient-sound", "Sound", options: Ambient.allCases.map { .init($0.rawValue, $0.name) }, selected: saved.ambient.rawValue),
                .button("preview-ambient", "Play", detail: "Hear a few seconds of it."),
                .slider("volume", "Volume", range: 0...100, step: 5, value: (saved.volume * 100).rounded(), unit: "%"),
                .toggle("ambient-in-breaks", "Play during breaks", isOn: saved.ambientInBreaks),
            ]),
        ], keywords: ["focus", "break", "timer", "pomodoro", "countdown", "stopwatch", "reminders", "rain", "ocean", "brown noise",
                      "white noise"])
    }
}
