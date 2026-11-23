import Foundation
import LedgeKit

public enum Mode: String, Codable, Sendable {
    case focus, rest, stopwatch
    public var name: String { ["focus": "Focus", "rest": "Break", "stopwatch": "Stopwatch"][rawValue]! }
    public var next: Mode { self == .focus ? .rest : .focus }
}

/// Generated noise to play while a session runs.
public enum Ambient: String, Codable, Sendable, CaseIterable {
    case brown, pink, white
    public var name: String { ["brown": "Brown noise", "pink": "Pink noise", "white": "White noise"][rawValue]! }
}

/// The macOS alert sounds, offered as the end sound.
public let endSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
                        "Submarine", "Tink"]

/// A session under way. It keeps counting past its length, as overtime, until it's stopped or the next one starts; a
/// stopwatch has no length and only counts up. Running while `since` is set, paused while it's nil.
public struct Run: Codable, Sendable, Equatable {
    public var mode: Mode
    /// Seconds it's set for; 0 for a stopwatch.
    public var total: TimeInterval
    /// When it last started or resumed.
    public var since: Date?
    /// Seconds counted before `since`.
    public var counted: TimeInterval = 0
    /// The end has been announced, so it isn't again.
    public var ended = false

    public init(mode: Mode, total: TimeInterval, since: Date?) {
        self.mode = mode
        self.total = total
        self.since = since
    }

    public func elapsed(at now: Date) -> TimeInterval { counted + (since.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    public func remaining(at now: Date) -> TimeInterval { max(0, total - elapsed(at: now)) }
    public func overtime(at now: Date) -> TimeInterval? { mode == .stopwatch || elapsed(at: now) < total ? nil : elapsed(at: now) - total }
    public var isPaused: Bool { since == nil }

    /// What the time reads: "24:59" counting down, "+00:22" in overtime, "00:35" on a stopwatch.
    public func reading(at now: Date, seconds: Bool = true) -> String {
        if mode == .stopwatch { return clock(elapsed(at: now).rounded(.down), seconds: seconds) }
        if let over = overtime(at: now) { return "+" + clock(over.rounded(.down), seconds: seconds) }
        return clock(remaining(at: now), seconds: seconds)
    }

    public func progress(at now: Date) -> Double { total > 0 ? min(1, elapsed(at: now) / total) : 0 }
}

/// Everything kept between launches. The run is kept by when it started, so a restarted add-on picks up where it was.
public struct Saved: Codable, Sendable, Equatable {
    public var focusMinutes = 25
    public var breakMinutes = 5
    public var mode = Mode.focus
    public var title = ""
    /// "None" or one of ``endSounds``.
    public var endSound = "Glass"
    public var notice = true
    public var autoContinue = false
    public var startInstantly = false
    public var showSeconds = true
    public var ambientOn = false
    public var ambient = Ambient.brown
    public var volume = 0.3
    public var ambientInBreaks = true
    public var run: Run?
    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field optional, and one that no longer reads is dropped, so a change to the settings never throws
        // away the rest.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Saved()
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback }
        focusMinutes = read(.focusMinutes, d.focusMinutes)
        breakMinutes = read(.breakMinutes, d.breakMinutes)
        mode = read(.mode, d.mode)
        title = read(.title, d.title)
        endSound = read(.endSound, d.endSound)
        notice = read(.notice, d.notice)
        autoContinue = read(.autoContinue, d.autoContinue)
        startInstantly = read(.startInstantly, d.startInstantly)
        showSeconds = read(.showSeconds, d.showSeconds)
        ambientOn = read(.ambientOn, d.ambientOn)
        ambient = read(.ambient, d.ambient)
        volume = read(.volume, d.volume)
        ambientInBreaks = read(.ambientInBreaks, d.ambientInBreaks)
        run = (try? c.decodeIfPresent(Run.self, forKey: .run)) ?? nil
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

/// "25:00", "04:59", or "1:05:00" from an hour; without seconds "25m", "1m" or "1h 05m", rounded up.
public func clock(_ seconds: TimeInterval, seconds showSeconds: Bool = true) -> String {
    let s = Int(seconds.rounded(.up))
    guard showSeconds else {
        let m = (s + 59) / 60
        return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m)m"
    }
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

    public func minutes(_ mode: Mode) -> Int { mode == .rest ? saved.breakMinutes : saved.focusMinutes }

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
        case ("stopwatch", .pressed): start(.stopwatch, now: now)
        case ("pause", .pressed): pause(now: now)
        case ("resume", .pressed): resume(now: now)
        case ("toggle", .pressed): toggle(now: now)
        case ("stop", .pressed): saved.run = nil
        case ("next", .pressed): if let run = saved.run, run.mode != .stopwatch { start(run.mode.next, now: now) }
        case ("ambient", .pressed): saved.ambientOn.toggle()
        case ("ambient-on", .toggled(let on)): saved.ambientOn = on
        case ("ambient-sound", .picked(let id)): saved.ambient = Ambient(rawValue: id) ?? saved.ambient
        case ("volume", .changed(let value)): saved.volume = min(max(value / 100, 0), 1)
        case ("ambient-in-breaks", .toggled(let on)): saved.ambientInBreaks = on
        case ("end-sound", .picked(let id)): saved.endSound = id == "None" || endSounds.contains(id) ? id : saved.endSound
        case ("show-seconds", .toggled(let on)): saved.showSeconds = on
        case ("edit-title", .pressed): editingTitle = true
        case (PageScreen.backControl, .pressed): editingTitle = false
        case ("title", .edited(let text)), ("title", .ended(let text)): saved.title = Self.title(from: text)
        case ("clear-title", .pressed): saved.title = ""
        case ("notice", .toggled(let on)): saved.notice = on
        case ("auto-continue", .toggled(let on)): saved.autoContinue = on
        case ("start-instantly", .toggled(let on)): saved.startInstantly = on
        default: break
        }
    }

    /// The shortcut: start when nothing runs, otherwise pause or resume.
    public mutating func toggle(now: Date) {
        guard let run = saved.run else { return start(saved.mode, now: now) }
        run.isPaused ? resume(now: now) : pause(now: now)
    }

    /// Opening the page with Start instantly on starts the last timer.
    public mutating func opened(now: Date) {
        if saved.startInstantly, saved.run == nil { start(saved.mode, now: now) }
    }

    /// Whether ambient sound should be playing now: while a session counts down, and in breaks only if asked.
    public func ambientPlaying(at now: Date) -> Bool {
        guard saved.ambientOn, let run = saved.run, !run.isPaused, run.overtime(at: now) == nil else { return false }
        return run.mode != .rest || saved.ambientInBreaks
    }

    /// Moves the clock on. Returns the session that just reached its length, once, so the program can sound and say
    /// so. It then counts overtime, unless Move on automatically starts the next session.
    public mutating func tick(now: Date) -> Mode? {
        guard var run = saved.run, !run.ended, run.overtime(at: now) != nil else { return nil }
        run.ended = true
        saved.run = run
        if saved.autoContinue { start(run.mode.next, now: now) }
        return run.mode
    }

    mutating func choose(_ mode: Mode) {
        guard saved.run == nil else { return }
        saved.mode = mode
    }

    mutating func setMinutes(_ minutes: Int) {
        guard saved.run == nil else { return }
        if saved.mode == .rest { saved.breakMinutes = minutes } else { saved.focusMinutes = minutes }
    }

    mutating func start(_ mode: Mode, now: Date) {
        if mode != .stopwatch { saved.mode = mode }
        saved.run = Run(mode: mode, total: mode == .stopwatch ? 0 : TimeInterval(minutes(mode) * 60), since: now)
    }

    mutating func pause(now: Date) {
        guard var run = saved.run, !run.isPaused else { return }
        run.counted = run.elapsed(at: now)
        run.since = nil
        saved.run = run
    }

    mutating func resume(now: Date) {
        guard var run = saved.run, run.isPaused else { return }
        run.since = now
        saved.run = run
    }

    /// The editor hands back Markdown; a title is its first line, plain, up to 60 characters.
    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_>- ").union(.whitespaces)).prefix(60))
    }
}
