import Foundation
import LedgeKit

public enum Mode: String, Codable, Sendable, CaseIterable {
    case focus, rest
    public var name: String { self == .focus ? "Focus" : "Break" }
    public var next: Mode { self == .focus ? .rest : .focus }
}

public enum Ambient: String, Codable, Sendable, CaseIterable {
    case off, brown, pink
    public var name: String { ["off": "Off", "brown": "Brown noise", "pink": "Pink noise"][rawValue]! }
}

/// A session under way: running while `endsAt` is set, paused with `left` seconds to go while it's nil.
public struct Run: Codable, Sendable, Equatable {
    public var mode: Mode
    public var total: TimeInterval
    public var endsAt: Date?
    public var left: TimeInterval

    public func remaining(at now: Date) -> TimeInterval { endsAt.map { max(0, $0.timeIntervalSince(now)) } ?? left }
    public var isPaused: Bool { endsAt == nil }
}

/// Everything kept between launches. The run is kept by its end time, so a restarted add-on picks up where it was.
public struct Saved: Codable, Sendable, Equatable {
    public var focusMinutes = 25
    public var breakMinutes = 5
    public var mode = Mode.focus
    public var title = ""
    public var chime = true
    public var notice = true
    public var autoContinue = false
    public var startInstantly = false
    public var ambient = Ambient.off
    public var run: Run?
    /// The session that just ended, while its "start the next one" offer is up.
    public var finished: Mode?
    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field optional, so a setting added later doesn't throw away the rest.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Saved()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? d.breakMinutes
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? d.mode
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? d.title
        chime = try c.decodeIfPresent(Bool.self, forKey: .chime) ?? d.chime
        notice = try c.decodeIfPresent(Bool.self, forKey: .notice) ?? d.notice
        autoContinue = try c.decodeIfPresent(Bool.self, forKey: .autoContinue) ?? d.autoContinue
        startInstantly = try c.decodeIfPresent(Bool.self, forKey: .startInstantly) ?? d.startInstantly
        ambient = try c.decodeIfPresent(Ambient.self, forKey: .ambient) ?? d.ambient
        run = try c.decodeIfPresent(Run.self, forKey: .run)
        finished = try c.decodeIfPresent(Mode.self, forKey: .finished)
    }
}

/// Lengths, in minutes, from 1 to 8 hours: the slider is squared so the short end, where most sessions are, gets
/// most of its width. Under an hour it moves by a minute, above by five.
public enum Length {
    public static let range = 1...480

    public static func minutes(slider value: Double) -> Int {
        let raw = 1 + 479 * min(max(value, 0), 1) * min(max(value, 0), 1)
        return clamp(raw < 60 ? Int(raw.rounded()) : Int((raw / 5).rounded()) * 5)
    }

    public static func slider(minutes: Int) -> Double { ((Double(clamp(minutes)) - 1) / 479).squareRoot() }

    public static func step(_ minutes: Int, by direction: Int) -> Int {
        if direction > 0 { return clamp(minutes < 60 ? minutes + 1 : minutes / 5 * 5 + 5) }
        return clamp(minutes <= 60 ? minutes - 1 : (minutes + 4) / 5 * 5 - 5)
    }

    static func clamp(_ minutes: Int) -> Int { min(max(minutes, range.lowerBound), range.upperBound) }
}

/// "25:00", "4:59", or "1:05:00" from an hour.
public func clock(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.up))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
}

/// "24 minutes 59 seconds", for VoiceOver.
public func spoken(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.up)), h = s / 3600, m = s / 60 % 60, r = s % 60
    let parts = [(h, "hour"), (m, "minute"), (r, "second")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
    return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
}

public struct PomodoroModel: Sendable {
    public var saved = Saved()
    /// The notch page's title editor is open.
    public var editingTitle = false
    public var problem: String?

    public init(saved: Saved = Saved()) { self.saved = saved }

    public func minutes(_ mode: Mode) -> Int { mode == .focus ? saved.focusMinutes : saved.breakMinutes }

    // MARK: Events

    /// What the person did. Settings, the page, the widget (on the Mac or iPhone) and the shortcut share control ids.
    public mutating func handle(_ event: SurfaceEvent, now: Date) {
        problem = nil
        switch (event.control, event.action) {
        case ("mode-focus", .pressed): choose(.focus)
        case ("mode-rest", .pressed): choose(.rest)
        case ("length", .changed(let value)): setMinutes(Length.minutes(slider: value))
        case ("shorter", .pressed): setMinutes(Length.step(minutes(saved.mode), by: -1))
        case ("longer", .pressed): setMinutes(Length.step(minutes(saved.mode), by: 1))
        case ("start", .pressed): start(saved.mode, now: now)
        case ("pause", .pressed): pause(now: now)
        case ("resume", .pressed): resume(now: now)
        case ("toggle", .pressed): toggle(now: now)
        case ("stop", .pressed): saved.run = nil; saved.finished = nil
        case ("next", .pressed): start(saved.finished?.next ?? saved.mode, now: now)
        case ("dismiss", .pressed): saved.finished = nil
        case ("ambient", .pressed):
            let all = Ambient.allCases
            saved.ambient = all[(all.firstIndex(of: saved.ambient)! + 1) % all.count]
        case ("ambient", .picked(let id)): saved.ambient = Ambient(rawValue: id) ?? .off
        case ("edit-title", .pressed): editingTitle = true
        case (PageScreen.backControl, .pressed): editingTitle = false
        case ("title", .edited(let text)), ("title", .ended(let text)): saved.title = Self.title(from: text)
        case ("clear-title", .pressed): saved.title = ""
        case ("chime", .toggled(let on)): saved.chime = on
        case ("notice", .toggled(let on)): saved.notice = on
        case ("auto-continue", .toggled(let on)): saved.autoContinue = on
        case ("start-instantly", .toggled(let on)): saved.startInstantly = on
        default: break
        }
    }

    /// The shortcut: start when nothing runs, otherwise pause or resume.
    public mutating func toggle(now: Date) {
        guard let run = saved.run else { return start(saved.finished?.next ?? saved.mode, now: now) }
        run.isPaused ? resume(now: now) : pause(now: now)
    }

    /// Opening the page with Start instantly on starts the last timer.
    public mutating func opened(now: Date) {
        if saved.startInstantly, saved.run == nil, saved.finished == nil { start(saved.mode, now: now) }
    }

    /// Moves the clock on. Returns the session that just ended, once, so the program can chime and say so.
    public mutating func tick(now: Date) -> Mode? {
        guard let run = saved.run, !run.isPaused, run.remaining(at: now) <= 0 else { return nil }
        if saved.autoContinue {
            start(run.mode.next, now: now)
        } else {
            saved.run = nil
            saved.finished = run.mode
            saved.mode = run.mode.next
        }
        return run.mode
    }

    mutating func choose(_ mode: Mode) {
        guard saved.run == nil else { return }
        saved.mode = mode
        saved.finished = nil
    }

    mutating func setMinutes(_ minutes: Int) {
        guard saved.run == nil else { return }
        if saved.mode == .focus { saved.focusMinutes = minutes } else { saved.breakMinutes = minutes }
    }

    mutating func start(_ mode: Mode, now: Date) {
        let total = TimeInterval(minutes(mode) * 60)
        saved.mode = mode
        saved.finished = nil
        saved.run = Run(mode: mode, total: total, endsAt: now.addingTimeInterval(total), left: total)
    }

    mutating func pause(now: Date) {
        guard var run = saved.run, !run.isPaused else { return }
        run.left = run.remaining(at: now)
        run.endsAt = nil
        saved.run = run
    }

    mutating func resume(now: Date) {
        guard var run = saved.run, run.isPaused else { return }
        run.endsAt = now.addingTimeInterval(run.left)
        saved.run = run
    }

    /// The editor hands back Markdown; a title is its first line, plain, up to 60 characters.
    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_>- ").union(.whitespaces)).prefix(60))
    }
}
