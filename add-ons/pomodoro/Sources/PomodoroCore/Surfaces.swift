import Foundation
import LedgeKit

extension Mode {
    public var symbol: String { self == .focus ? "timer" : "cup.and.saucer.fill" }
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
        } else if let done = saved.finished {
            screen = PageScreen("timer", content: finished(done))
        } else {
            screen = PageScreen("timer", content: picker())
        }
        return NotchPage(title: "Pomodoro", symbol: "timer", size: .small, screen: screen)
    }

    private func picker() -> PageNode {
        let mode = saved.mode, length = minutes(mode)
        let ambientOn = saved.ambient != .off
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
                                    accessibilityLabel: "Ambient sound: " + saved.ambient.name)),
                .control(PageButton("edit-title", title: "", role: saved.title.isEmpty ? .secondary : .selected, symbol: "pencil",
                                    accessibilityLabel: "Focus title")),
                .spacer,
                .text(problem ?? clock(TimeInterval(length * 60)), style: problem == nil ? .title : .caption),
            ]),
        ])
    }

    private func running(_ run: Run, now: Date) -> PageNode {
        let left = run.remaining(at: now)
        let label = run.isPaused ? "Paused" : run.mode.name
        return .vstack(spacing: 10, children: [
            // A button grid, unlike inline buttons, makes Ledge run the row across the page's whole width.
            .hstack(spacing: 6, children: [
                .buttonGrid(columns: 2, rowHeight: 28, buttons: [
                    run.isPaused ? PageButton("resume", title: "", role: .accent, symbol: "play.fill", accessibilityLabel: "Resume")
                                 : PageButton("pause", title: "", role: .accent, symbol: "pause.fill", accessibilityLabel: "Pause"),
                    PageButton("stop", title: "", role: .secondary, symbol: "xmark", accessibilityLabel: "Stop"),
                ]),
                .spacer,
                .text(label, style: .secondary),
                .text(clock(left), style: .title),
            ]),
        ] + (saved.title.isEmpty ? [] : [.text(saved.title, style: .secondary)]))
    }

    private func finished(_ done: Mode) -> PageNode {
        .vstack(spacing: 10, children: [
            .hstack(spacing: 6, children: [
                .symbol("checkmark.circle.fill", size: 18),
                .text(done == .focus ? "Focus done" : "Break over", style: .title),
                .spacer,
                .text(done.next.name + " · " + clock(TimeInterval(minutes(done.next) * 60)), style: .secondary),
            ]),
            .buttonGrid(columns: 2, rowHeight: 28, buttons: [
                PageButton("next", title: done == .focus ? "Start break" : "Start focus", role: .accent),
                PageButton("dismiss", title: "Not now", role: .secondary),
            ]),
        ])
    }

    // MARK: Widget (also the iPhone tile)

    public func widget(now: Date) -> Widget {
        let line: String, time: String, buttons: [WidgetNode]
        if let run = saved.run {
            line = run.isPaused ? "Paused" : run.mode.name
            time = clock(run.remaining(at: now))
            buttons = [run.isPaused ? .button(id: "resume", title: "Resume", symbol: "play.fill") : .button(id: "pause", title: "Pause", symbol: "pause.fill"),
                       .button(id: "stop", title: "Stop", symbol: "xmark")]
        } else if let done = saved.finished {
            line = done == .focus ? "Focus done" : "Break over"
            time = clock(TimeInterval(minutes(done.next) * 60))
            buttons = [.button(id: "next", title: done == .focus ? "Start break" : "Start focus", symbol: done.next.symbol)]
        } else {
            line = saved.mode.name
            time = clock(TimeInterval(minutes(saved.mode) * 60))
            buttons = [.button(id: "start", title: "Start", symbol: "play.fill"),
                       .button(id: saved.mode == .focus ? "mode-rest" : "mode-focus", title: saved.mode.next.name, symbol: saved.mode.next.symbol)]
        }
        let title = saved.title.isEmpty ? line : line + " · " + saved.title
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
        if let run = saved.run {
            let left = run.remaining(at: now)
            return [LiveActivity("timer", symbol: run.isPaused ? "pause.fill" : run.mode.symbol, text: clock(left),
                                 progress: .fraction(run.total > 0 ? 1 - left / run.total : 1), importance: .normal,
                                 accessibilityValue: (run.isPaused ? "Paused, " : run.mode.name + ", ") + spoken(left) + " left")]
        }
        if let done = saved.finished {
            return [LiveActivity("timer", symbol: done.next.symbol, text: done == .focus ? "Focus done" : "Break over",
                                 progress: .done, importance: .attention, lasts: 30)]
        }
        return []
    }

    public func lockScreenRow(now: Date) -> LockScreenRow? {
        guard let run = saved.run else { return nil }
        return LockScreenRow(symbol: run.isPaused ? "pause.fill" : run.mode.symbol, label: run.isPaused ? "Paused" : run.mode.name,
                             value: clock(run.remaining(at: now)))
    }

    // MARK: Settings

    public func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("timer", title: "Timer", rows: [
                .toggle("start-instantly", "Start instantly", detail: "Opening the Pomodoro page starts your last timer.", isOn: saved.startInstantly),
                .toggle("auto-continue", "Move on automatically", detail: "Start the break when focus ends, and focus when the break ends.",
                        isOn: saved.autoContinue),
            ]),
            SettingsSection("sound", title: "Sound", footer: "Ambient sound plays while a timer runs and stops when it pauses or ends.", rows: [
                .picker("ambient", "Ambient sound", options: Ambient.allCases.map { .init($0.rawValue, $0.name) }, selected: saved.ambient.rawValue),
                .toggle("chime", "Chime when a session ends", isOn: saved.chime),
                .toggle("notice", "Show a notice when a session ends", isOn: saved.notice),
            ]),
        ], keywords: ["focus", "break", "timer", "pomodoro", "countdown", "brown noise", "pink noise"])
    }
}
