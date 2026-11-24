import Foundation
import LedgeKit

extension Mode {
    public var symbol: String { self == .display ? "sun.max.fill" : "desktopcomputer" }
}

extension WideAwakeModel {
    /// What the time reads: what's left, or ∞ until stopped.
    func reading(_ session: Session, now: Date) -> String { session.remaining(at: now).map(clock) ?? "∞" }

    // MARK: Notch page

    /// Pick Display or System, drag the tape to a length, start or keep awake until stopped; then stop or add time.
    public func page(now: Date) -> NotchPage {
        NotchPage(title: "Wide Awake", symbol: "eye", size: .small,
                  screen: PageScreen("awake", content: saved.session.map { running($0, now: now) } ?? picker(now: now)))
    }

    private func picker(now: Date) -> PageNode {
        let mode = saved.mode
        let note: PageNode = problem.map { .text($0, style: .caption) }
            ?? reasons.first.map { .text($0, style: .secondary) }
            ?? .display(clock(TimeInterval(saved.minutes * 60)), tint: .orange)
        return .vstack(spacing: 8, children: [
            .hstack(spacing: 6, children: [
                .spacer,
                .control(PageButton("mode-display", title: "Display", role: mode == .display ? .selected : .secondary, tint: .orange)),
                .control(PageButton("mode-system", title: "System", role: mode == .system ? .selected : .secondary, tint: .orange)),
                .spacer,
            ]),
            .tape(PageTape("length", value: saved.minutes, minimum: Length.range.lowerBound, maximum: Length.range.upperBound,
                           labelEvery: 15, tint: .orange, accessibilityLabel: "Stay awake for, in minutes")),
            .hstack(spacing: 6, children: [
                .control(PageButton("start", title: "Stay Awake", role: .accent, tint: .orange)),
                .control(PageButton("forever", title: "", role: .secondary, symbol: "infinity", accessibilityLabel: "Stay awake until stopped")),
                .spacer,
                note,
            ]),
        ])
    }

    private func running(_ session: Session, now: Date) -> PageNode {
        var buttons = [PageButton("stop", title: "", role: .accent, symbol: "xmark", accessibilityLabel: "Stop", tint: tint(at: now))]
        if session.until != nil {
            buttons.append(PageButton("more", title: "+15", role: .secondary, accessibilityLabel: "Add 15 minutes"))
        }
        return .hstack(spacing: 8, children: buttons.map(PageNode.control) + [
            .spacer,
            .text(session.mode.name, style: .secondary),
            .display(reading(session, now: now), tint: tint(at: now)),
        ])
    }

    // MARK: Widget (also the iPhone tile)

    public func widget(now: Date) -> Widget {
        let line: String, time: String, buttons: [WidgetNode]
        if let session = saved.session {
            line = session.mode.name
            time = reading(session, now: now)
            buttons = (session.until != nil ? [.button(id: "more", title: "+15 min", symbol: "plus")] : [])
                + [.button(id: "stop", title: "Stop", symbol: "xmark")]
        } else {
            line = reasons.first ?? "Sleeps normally"
            time = clock(TimeInterval(saved.minutes * 60))
            buttons = [.button(id: "start", title: "Stay Awake", symbol: "eye.fill"),
                       .button(id: "forever", title: "Until stopped", symbol: "infinity")]
        }
        let full: WidgetNode = .vstack(spacing: 8, children: [
            .hstack(spacing: 8, children: [.text(line, style: .secondary), .spacer, .text(time, style: .title)]),
            .hstack(spacing: 8, children: buttons + [.spacer]),
        ])
        let compact: WidgetNode = .vstack(spacing: 6, children: [
            .hstack(spacing: 6, children: [.text(line, style: .caption), .spacer, .text(time, style: .title)]),
            buttons[0],
        ])
        return Widget("wide-awake", title: "Wide Awake", symbol: "eye", content: full, compactContent: compact)
    }

    // MARK: Beside the notch and on the lock screen

    public func activities(now: Date) -> [LiveActivity] {
        if let session = saved.session {
            let left = session.remaining(at: now)
            return [LiveActivity("awake", symbol: "eye.fill", text: reading(session, now: now),
                                 progress: session.progress(at: now).map { .fraction($0) } ?? .indeterminate,
                                 accessibilityValue: "Staying awake, " + (left.map { spoken($0) + " left" } ?? "until stopped"))]
        }
        guard let reason = reasons.first else { return [] }
        return [LiveActivity("awake", symbol: "eye", text: reason, accessibilityValue: "Staying awake: " + reason)]
    }

    public func lockScreenRow(now: Date) -> LockScreenRow? {
        guard saved.lockScreen else { return nil }
        if let session = saved.session {
            return LockScreenRow(symbol: "eye.fill", label: "Wide Awake", value: reading(session, now: now))
        }
        return reasons.first.map { LockScreenRow(symbol: "eye", label: "Wide Awake", value: $0) }
    }

    /// The notice when a timer runs out.
    public static let notice = (title: "Wide Awake is off", message: "Your Mac can sleep again.")

    // MARK: Settings

    public func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("awake", rows: [
                .toggle("start-instantly", "Start as soon as you open it", detail: "Opening Wide Awake starts your last length.",
                        isOn: saved.startInstantly),
                .picker("mode", "Mode", options: Mode.allCases.map { .init($0.rawValue, "\($0.name): \($0.detail)") }, selected: saved.mode.rawValue),
                .toggle("urgency-colors", "Colours as time runs out", detail: "Yellow in the last 15 minutes, red in the last 5.",
                        isOn: saved.urgencyColors),
                .toggle("lock-screen", "Show on the lock screen", isOn: saved.lockScreen),
            ]),
            SettingsSection("automatic", title: "Automatic",
                            footer: "Your Mac stays awake, in the mode above, while any of these is true.", rows: [
                .toggle("while-plugged-in", "While plugged in", isOn: saved.whilePluggedIn),
                .toggle("while-display", "While another display is connected", isOn: saved.whileDisplay),
                .toggle("while-downloading", "While a file downloads", detail: "Looks in Downloads. macOS asks once to allow it.",
                        isOn: saved.whileDownloading),
                .toggle("while-printing", "While printing", isOn: saved.whilePrinting),
                .toggle("while-agents", "While a coding agent runs", detail: "Claude Code, Codex, Gemini CLI, Aider and others.",
                        isOn: saved.whileAgents),
                .toggle("while-apps", "While these apps are open", isOn: saved.whileApps),
                .textField("apps", "Apps", detail: "Names separated by commas.", text: saved.apps, placeholder: "Keynote, Final Cut Pro"),
            ]),
        ], keywords: ["caffeine", "amphetamine", "keep awake", "stay awake", "sleep", "insomnia", "display", "screen saver", "presentation"])
    }
}
