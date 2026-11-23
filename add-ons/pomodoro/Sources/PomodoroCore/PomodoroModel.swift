import Foundation
import LedgeKit

public enum Mode: String, Codable, Sendable {
    case focus, rest, stopwatch
    public var name: String { ["focus": "Focus", "rest": "Break", "stopwatch": "Stopwatch"][rawValue]! }
    public var next: Mode { self == .focus ? .rest : .focus }
}

/// A sound to play while a session runs: macOS's own Background Sounds, in Droppy's order.
public enum Ambient: String, Codable, Sendable, CaseIterable {
    case rain, rainOnRoof, ocean, stream, fire, night, quietNight, brownNoise, pinkNoise, whiteNoise, airplane, babble, boat, bus,
         steam, train
    public var name: String {
        ["rain": "Rain", "rainOnRoof": "Rain on Roof", "ocean": "Ocean", "stream": "Stream", "fire": "Fireplace", "night": "Night",
         "quietNight": "Quiet Night", "brownNoise": "Brown Noise", "pinkNoise": "Pink Noise", "whiteNoise": "White Noise",
         "airplane": "Airplane", "babble": "Babble", "boat": "Boat", "bus": "Bus", "steam": "Steam", "train": "Train"][rawValue]!
    }

    /// Where macOS keeps the Background Sounds (System Settings › Accessibility › Audio), each a short seamless loop.
    public static let folder = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/HearingUtilities.framework/Versions/A/Resources")
    /// This sound's file, such as RainOnRoof.m4a.
    public var file: URL { Self.folder.appendingPathComponent(rawValue.prefix(1).uppercased() + rawValue.dropFirst() + ".m4a") }

    /// The noise generated instead when this Mac doesn't have the file.
    public var fallback: NoiseGenerator.Kind {
        switch self {
        case .pinkNoise, .rain, .stream, .steam: .pink
        case .whiteNoise: .white
        default: .brown
        }
    }
}

/// The macOS alert sounds, offered as the end sound.
public let endSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
                        "Submarine", "Tink"]

/// A small reminder shown while you work, every `minutes` of a focus session or stopwatch.
public struct Reminder: Equatable, Sendable {
    public var id: String
    public var title: String
    public var message: String
    public var symbol: String
    public var minutes: Int

    public static let eyeBreak = Reminder(id: "eye-break", title: "Eye break", message: "Look about 6 meters (20 feet) away for 20 seconds",
                                          symbol: "eye", minutes: 20)
    public static let drinkWater = Reminder(id: "drink-water", title: "Drink water", message: "Have a glass of water", symbol: "drop.fill",
                                            minutes: 30)
    public static let standUp = Reminder(id: "stand-up", title: "Stand up", message: "Stand up and stretch for a minute",
                                         symbol: "figure.stand", minutes: 60)
    static func custom(_ text: String) -> Reminder {
        Reminder(id: "custom:" + text, title: "Reminder", message: text, symbol: "bell.fill", minutes: 30)
    }
}

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
    /// How many times each reminder has been shown in this session, by its id.
    public var reminded: [String: Int]?

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
    /// "None" or one of ``endSounds``.
    public var endSound = "Glass"
    public var startInstantly = false
    /// The timer beside the notch for the whole session; off, it shows on the page, widget and lock screen only.
    public var alwaysShow = true
    public var showSeconds = true
    public var eyeBreak = false
    public var drinkWater = false
    public var standUp = false
    public var customReminders: [String] = []
    public var ambientOn = false
    public var ambient = Ambient.rain
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
        endSound = read(.endSound, d.endSound)
        startInstantly = read(.startInstantly, d.startInstantly)
        alwaysShow = read(.alwaysShow, d.alwaysShow)
        showSeconds = read(.showSeconds, d.showSeconds)
        eyeBreak = read(.eyeBreak, d.eyeBreak)
        drinkWater = read(.drinkWater, d.drinkWater)
        standUp = read(.standUp, d.standUp)
        customReminders = read(.customReminders, d.customReminders)
        ambientOn = read(.ambientOn, d.ambientOn)
        ambient = read(.ambient, d.ambient)
        volume = read(.volume, d.volume)
        ambientInBreaks = read(.ambientInBreaks, d.ambientInBreaks)
        run = (try? c.decodeIfPresent(Run.self, forKey: .run)) ?? nil
    }

    /// The reminders that are on, built-in first.
    public var reminders: [Reminder] {
        [(eyeBreak, Reminder.eyeBreak), (drinkWater, .drinkWater), (standUp, .standUp)].filter(\.0).map(\.1)
            + customReminders.map(Reminder.custom)
    }
}

/// Lengths, in whole minutes, from 1 to 8 hours.
public enum Length {
    public static let range = 1...480
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
    /// What's typed in Settings' New reminder field, not yet added.
    public var newReminder = ""
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
        case ("length", .changed(let value)): setMinutes(Length.clamp(Int(value.rounded())))
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
        case ("always-show", .toggled(let on)): saved.alwaysShow = on
        case ("start-instantly", .toggled(let on)): saved.startInstantly = on
        case ("eye-break", .toggled(let on)): saved.eyeBreak = on
        case ("drink-water", .toggled(let on)): saved.drinkWater = on
        case ("stand-up", .toggled(let on)): saved.standUp = on
        case ("new-reminder", .edited(let text)), ("new-reminder", .ended(let text)): newReminder = text
        case ("add-reminder", .pressed): addReminder()
        case (let control, .pressed) where control.hasPrefix("remove-reminder:"):
            if let index = Int(control.dropFirst("remove-reminder:".count)), saved.customReminders.indices.contains(index) {
                saved.customReminders.remove(at: index)
            }
        default: break
        }
    }

    /// The shortcut: start when nothing runs, otherwise pause or resume.
    public mutating func toggle(now: Date) {
        guard let run = saved.run else { return start(saved.mode, now: now) }
        run.isPaused ? resume(now: now) : pause(now: now)
    }

    /// Opening the page with Start as soon as you open it on starts the last timer.
    public mutating func opened(now: Date) {
        if saved.startInstantly, saved.run == nil { start(saved.mode, now: now) }
    }

    /// Whether ambient sound should be playing now: while a session counts down, and in breaks only if asked.
    public func ambientPlaying(at now: Date) -> Bool {
        guard saved.ambientOn, let run = saved.run, !run.isPaused, run.overtime(at: now) == nil else { return false }
        return run.mode != .rest || saved.ambientInBreaks
    }

    /// Moves the clock on. Returns the session that just reached its length, once, so the program can sound and say
    /// so; it then counts overtime until the next session is started. Also returns the reminders now due.
    public mutating func tick(now: Date) -> (ended: Mode?, reminders: [Reminder]) {
        guard var run = saved.run else { return (nil, []) }
        var due: [Reminder] = []
        // Reminders are for working: a focus session or a stopwatch, while it runs.
        if run.mode != .rest, !run.isPaused {
            let minutes = Int(run.elapsed(at: now) / 60)
            var reminded = run.reminded ?? [:]
            for reminder in saved.reminders {
                let count = minutes / reminder.minutes
                if count > reminded[reminder.id, default: 0] { due.append(reminder) }
                reminded[reminder.id] = count
            }
            run.reminded = reminded
        }
        var ended: Mode?
        if !run.ended, run.overtime(at: now) != nil {
            run.ended = true
            ended = run.mode
        }
        if run != saved.run { saved.run = run }
        return (ended, due)
    }

    mutating func addReminder() {
        let text = String(newReminder.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !text.isEmpty, !saved.customReminders.contains(text), saved.customReminders.count < 10 else { return }
        saved.customReminders.append(text)
        newReminder = ""
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
}
