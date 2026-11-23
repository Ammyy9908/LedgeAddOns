import Foundation
import LedgeKit

extension Mode {
    public var symbol: String { ["focus": "timer", "rest": "cup.and.saucer.fill", "stopwatch": "stopwatch"][rawValue]! }
}

extension PomodoroModel {
    // MARK: Notch page

    /// Like a kitchen timer in the notch: pick Focus or Break and a length, start, then pause or stop.
    public func page(now: Date) -> NotchPage {
        let screen: PageScreen
        if editingTitle {
            screen = PageScreen("title", depth: 1, title: "Focus title", back: true, actions: saved.title.isEmpty ? [] : [
                PageAction("clear-title", symbol: "xmark.circle", label: "Clear title"),
            ], content: .editor(id: "title", text: saved.title, placeholder: "What are you working on?", autofocus: true))
        } else if let run = saved.run {
            screen = PageScreen("timer", content: running(run, now: now))
        } else {
            screen = PageScreen("timer", content: picker())
        }
        return NotchPage(title: "Pomodoro", symbol: "timer", size: .small, screen: screen)
    }

    private func picker() -> PageNode {
        let mode = saved.mode, length = minutes(mode)
        let ambientOn = saved.ambientOn
        return .vstack(spacing: 8, children: [
            .hstack(spacing: 6, children: [
                .control(PageButton("mode-focus", title: "Focus", role: mode == .focus ? .selected : .secondary)),
                .spacer,
            ] + (saved.title.isEmpty ? [] : [.text(saved.title, style: .secondary), .spacer]) + [
                .control(PageButton("mode-rest", title: "Break", role: mode == .rest ? .selected : .secondary)),
            ]),
            .hstack(spacing: 6, children: [
                .control(PageButton("shorter", title: "", role: .secondary, symbol: "minus", accessibilityLabel: "A minute shorter")),
                .slider(id: "length", value: Length.slider(minutes: length), maximum: nil, label: nil, image: nil),
                .control(PageButton("longer", title: "", role: .secondary, symbol: "plus", accessibilityLabel: "A minute longer")),
            ]),
            .hstack(spacing: 6, children: [
                .control(PageButton("start", title: "Start timer", role: .accent)),
                .control(PageButton("ambient", title: "", role: ambientOn ? .selected : .secondary,
                                    symbol: ambientOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                    accessibilityLabel: ambientOn ? "Turn off ambient sound" : "Turn on ambient sound")),
                .control(PageButton("stopwatch", title: "", role: .secondary, symbol: "stopwatch", accessibilityLabel: "Start a stopwatch")),
                .control(PageButton("edit-title", title: "", role: saved.title.isEmpty ? .secondary : .selected, symbol: "pencil",
                                    accessibilityLabel: "Focus title")),
                .spacer,
                .text(problem ?? clock(TimeInterval(length * 60)), style: problem == nil ? .title : .caption),
            ]),
        ])
    }

    private func running(_ run: Run, now: Date) -> PageNode {
        let label = run.isPaused ? (run.mode == .stopwatch ? run.mode.name : "Paused") : run.mode.name
        return .vstack(spacing: 10, children: [
            // A button grid, unlike inline buttons, makes Ledge run the row across the page's whole width.
            .hstack(spacing: 6, children: [
                .buttonGrid(columns: controls(run, now: now).count, rowHeight: 28, buttons: controls(run, now: now)),
                .spacer,
                .text(label, style: .secondary),
                .text(run.reading(at: now), style: .title),
            ]),
        ] + (saved.title.isEmpty || run.mode == .stopwatch ? [] : [.text(saved.title, style: .secondary)]))
    }

    /// Pause or resume, then, once the session has reached its length, the next one, then stop.
    private func controls(_ run: Run, now: Date) -> [PageButton] {
        var buttons = [run.isPaused ? PageButton("resume", title: "", role: .accent, symbol: "play.fill", accessibilityLabel: "Resume")
                                    : PageButton("pause", title: "", role: .accent, symbol: "pause.fill", accessibilityLabel: "Pause")]
        if run.overtime(at: now) != nil {
            buttons.append(PageButton("next", title: "", role: .accent, symbol: "arrow.clockwise",
                                      accessibilityLabel: "Start " + (run.mode.next == .rest ? "the break" : "focusing")))
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
        let title = saved.title.isEmpty || saved.run?.mode == .stopwatch ? line : line + " · " + saved.title
        let full: WidgetNode = .vstack(spacing: 8, children: [
            .hstack(spacing: 8, children: [.text(String(title.prefix(40)), style: .secondary), .spacer, .text(time, style: .title)]),
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
        guard let run = saved.run else { return [] }
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

    /// The notice when a session reaches its length, as Droppy words it.
    public static func notice(for mode: Mode, minutes: Int) -> (title: String, message: String) {
        ("Pomodoro complete", "\(mode.name) is done · \(minutes) minute \(mode.name) finished")
    }

    // MARK: Settings

    public func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("timer", rows: [
                .toggle("start-instantly", "Start as soon as you open it", detail: "Opening the Pomodoro page starts your last timer.",
                        isOn: saved.startInstantly),
                .picker("end-sound", "End sound", options: (["None"] + endSounds).map { .init($0, $0) }, selected: saved.endSound),
                .button("preview-end-sound", "Play", detail: "Hear the end sound."),
                .toggle("notice", "Show a notice when a session ends", isOn: saved.notice),
            ]),
            SettingsSection("more", title: "More options", rows: [
                .toggle("show-seconds", "Show seconds beside the notch", detail: "Off, the timer beside the notch and on the lock screen reads in minutes.",
                        isOn: saved.showSeconds),
                .toggle("auto-continue", "Move on automatically",
                        detail: "Start the break when focus ends, and focus when the break ends, instead of counting overtime.",
                        isOn: saved.autoContinue),
            ]),
            SettingsSection("ambient", title: "Ambient sound", footer: "Generated on this Mac. It plays while a session counts down.", rows: [
                .toggle("ambient-on", "Enable ambient sound", isOn: saved.ambientOn),
                .picker("ambient-sound", "Sound", options: Ambient.allCases.map { .init($0.rawValue, $0.name) }, selected: saved.ambient.rawValue),
                .slider("volume", "Volume", range: 0...100, step: 5, value: (saved.volume * 100).rounded(), unit: "%"),
                .toggle("ambient-in-breaks", "Play during breaks", isOn: saved.ambientInBreaks),
            ]),
        ], keywords: ["focus", "break", "timer", "pomodoro", "countdown", "stopwatch", "brown noise", "pink noise", "white noise"])
    }
}
