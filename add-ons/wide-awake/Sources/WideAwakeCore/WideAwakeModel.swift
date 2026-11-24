import Foundation
import LedgeKit

/// What stays awake.
public enum Mode: String, Codable, Sendable, CaseIterable {
    /// The screen and the Mac.
    case display
    /// The Mac; the screen can dim and turn off.
    case system
    public var name: String { self == .display ? "Display" : "System" }
    public var detail: String { self == .display ? "Screen and Mac stay awake" : "Mac stays awake, screen can turn off" }
    /// The same, to go inside a sentence.
    var phrase: String { self == .display ? "the screen and the Mac stay awake" : "the Mac stays awake, the screen can turn off" }
}

/// A time the person asked for: until `until`, or until they stop it when that's nil.
public struct Session: Codable, Sendable, Equatable {
    public var mode: Mode
    public var started: Date
    public var until: Date?
    public init(mode: Mode, started: Date, until: Date?) {
        self.mode = mode
        self.started = started
        self.until = until
    }
    public func remaining(at now: Date) -> TimeInterval? { until.map { max(0, $0.timeIntervalSince(now)) } }
    public func progress(at now: Date) -> Double? {
        guard let until, until > started else { return nil }
        return min(1, max(0, now.timeIntervalSince(started) / until.timeIntervalSince(started)))
    }
}

/// What the Mac is doing now, as far as the automatic triggers care. The program fills it in.
public struct Conditions: Sendable, Equatable {
    public var pluggedIn = false
    public var externalDisplay = false
    public var downloading = false
    public var printing = false
    public var agentRunning = false
    /// Names of the apps open now, lowercased.
    public var openApps: Set<String> = []
    public init() {}
}

/// Everything kept between launches.
public struct Saved: Codable, Sendable, Equatable {
    public var minutes = 60
    public var mode = Mode.display
    public var startInstantly = false
    public var urgencyColors = true
    public var lockScreen = true
    public var whilePluggedIn = false
    public var whileDisplay = false
    public var whileDownloading = false
    public var whilePrinting = false
    public var whileAgents = false
    public var whileApps = false
    /// App names, separated by commas, such as "Keynote, Final Cut Pro".
    public var apps = ""
    public var session: Session?
    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field optional, so a change to the settings never throws away the rest.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Saved()
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback }
        minutes = read(.minutes, d.minutes)
        mode = read(.mode, d.mode)
        startInstantly = read(.startInstantly, d.startInstantly)
        urgencyColors = read(.urgencyColors, d.urgencyColors)
        lockScreen = read(.lockScreen, d.lockScreen)
        whilePluggedIn = read(.whilePluggedIn, d.whilePluggedIn)
        whileDisplay = read(.whileDisplay, d.whileDisplay)
        whileDownloading = read(.whileDownloading, d.whileDownloading)
        whilePrinting = read(.whilePrinting, d.whilePrinting)
        whileAgents = read(.whileAgents, d.whileAgents)
        whileApps = read(.whileApps, d.whileApps)
        apps = read(.apps, d.apps)
        session = (try? c.decodeIfPresent(Session.self, forKey: .session)) ?? nil
    }

    /// The apps that keep the Mac awake, lowercased.
    public var appNames: [String] {
        apps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    /// Whether any automatic trigger is on, so the program knows to watch.
    public var watches: Bool { whilePluggedIn || whileDisplay || whileDownloading || whilePrinting || whileAgents || (whileApps && !appNames.isEmpty) }
}

/// Lengths, in whole minutes, from a minute to a day.
public enum Length {
    public static let range = 1...1440
    static func clamp(_ minutes: Int) -> Int { min(max(minutes, range.lowerBound), range.upperBound) }
}

/// "59:59", or "1:05:00" from an hour.
public func clock(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.up))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
}

/// "1 hour 5 minutes", for VoiceOver and the AI tools.
public func spoken(_ seconds: TimeInterval) -> String {
    let m = Int((seconds / 60).rounded(.up)), h = m / 60, r = m % 60
    let parts = [(h, "hour"), (r, "minute")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
    return parts.isEmpty ? "less than a minute" : parts.joined(separator: " ")
}

public struct WideAwakeModel: Sendable {
    public var saved = Saved()
    public var conditions = Conditions()
    public var problem: String?

    public init(saved: Saved = Saved()) { self.saved = saved }

    // MARK: What keeps the Mac awake

    /// Why the automatic triggers keep the Mac awake now, in a few words each; empty when none does.
    public var reasons: [String] {
        var reasons: [String] = []
        if saved.whilePluggedIn, conditions.pluggedIn { reasons.append("Plugged in") }
        if saved.whileDisplay, conditions.externalDisplay { reasons.append("Display connected") }
        if saved.whileDownloading, conditions.downloading { reasons.append("Downloading") }
        if saved.whilePrinting, conditions.printing { reasons.append("Printing") }
        if saved.whileAgents, conditions.agentRunning { reasons.append("Agent running") }
        if saved.whileApps, let app = saved.appNames.first(where: conditions.openApps.contains) {
            reasons.append(app.capitalized + " is open")
        }
        return reasons
    }

    /// What to hold now: the person's session first, else the automatic triggers, in the chosen mode.
    public func holding(at now: Date) -> Mode? {
        if let session = saved.session, session.remaining(at: now) ?? 1 > 0 { return session.mode }
        return reasons.isEmpty ? nil : saved.mode
    }

    // MARK: Events

    /// What the person, an AI app or the shortcut did. Settings, the page and the widget share control ids.
    public mutating func handle(_ event: SurfaceEvent, now: Date) {
        problem = nil
        switch (event.control, event.action) {
        case ("mode-display", .pressed): saved.mode = .display
        case ("mode-system", .pressed): saved.mode = .system
        case ("mode", .picked(let id)): saved.mode = Mode(rawValue: id) ?? saved.mode
        case ("length", .changed(let value)): saved.minutes = Length.clamp(Int(value.rounded()))
        case ("start", .pressed): start(minutes: saved.minutes, mode: saved.mode, now: now)
        case ("forever", .pressed): start(minutes: nil, mode: saved.mode, now: now)
        case ("stop", .pressed): saved.session = nil
        case ("toggle", .pressed): saved.session == nil ? start(minutes: saved.minutes, mode: saved.mode, now: now) : (saved.session = nil)
        case ("more", .pressed): extend(by: 15, now: now)
        case (let control, .pressed) where control.hasPrefix("preset-"):
            if let minutes = Int(control.dropFirst("preset-".count)) { start(minutes: minutes, mode: saved.mode, now: now) }
        case ("start-instantly", .toggled(let on)): saved.startInstantly = on
        case ("urgency-colors", .toggled(let on)): saved.urgencyColors = on
        case ("lock-screen", .toggled(let on)): saved.lockScreen = on
        case ("while-plugged-in", .toggled(let on)): saved.whilePluggedIn = on
        case ("while-display", .toggled(let on)): saved.whileDisplay = on
        case ("while-downloading", .toggled(let on)): saved.whileDownloading = on
        case ("while-printing", .toggled(let on)): saved.whilePrinting = on
        case ("while-agents", .toggled(let on)): saved.whileAgents = on
        case ("while-apps", .toggled(let on)): saved.whileApps = on
        case ("apps", .edited(let text)), ("apps", .ended(let text)): saved.apps = String(text.prefix(300))
        default: break
        }
    }

    /// Opening the page with Start as soon as you open it on starts the last length.
    public mutating func opened(now: Date) {
        if saved.startInstantly, saved.session == nil { start(minutes: saved.minutes, mode: saved.mode, now: now) }
    }

    /// Starts keeping the Mac awake: for `minutes`, or until stopped when that's nil. Leaves the page's length and
    /// mode alone, so an AI app's timer doesn't change them.
    public mutating func start(minutes: Int?, mode: Mode, now: Date) {
        saved.session = Session(mode: mode, started: now, until: minutes.map { now.addingTimeInterval(TimeInterval(Length.clamp($0) * 60)) })
    }

    /// Adds time to a running timer, up to a day from now.
    mutating func extend(by minutes: Int, now: Date) {
        guard var session = saved.session, let until = session.until else { return }
        session.until = min(until.addingTimeInterval(TimeInterval(minutes * 60)), now.addingTimeInterval(TimeInterval(Length.range.upperBound * 60)))
        saved.session = session
    }

    /// Ends a timer that has run out. True when it just did, so the program can say so.
    public mutating func tick(now: Date) -> Bool {
        guard let remaining = saved.session?.remaining(at: now), remaining <= 0 else { return false }
        saved.session = nil
        return true
    }

    /// The colour for what's left: orange, then yellow in the last 15 minutes and red in the last 5.
    public func tint(at now: Date) -> PageTint {
        guard saved.urgencyColors, let remaining = saved.session?.remaining(at: now) else { return .orange }
        return remaining <= 300 ? .red : remaining <= 900 ? .yellow : .orange
    }

    // MARK: AI tools

    public static let tools = [
        AddOnTool("keep_awake_start", title: "Keep the Mac awake",
                  summary: "Keeps the Mac from sleeping, for the given minutes or until stopped when minutes is omitted. Mode display keeps the screen on too; system lets the screen turn off. Replaces any running timer.",
                  arguments: [.init("minutes", summary: "How long, 1 to 1440 (24 hours). Omit to stay awake until stopped.",
                                    kind: .number(minimum: 1, maximum: 1440, whole: true), required: false),
                              .init("mode", summary: "display (default) or system.", kind: .choice(["display", "system"]), required: false)]),
        AddOnTool("keep_awake_stop", title: "Let the Mac sleep again",
                  summary: "Stops a running keep-awake timer. Automatic triggers the person turned on in Settings still apply."),
        AddOnTool("keep_awake_status", title: "Is the Mac being kept awake",
                  summary: "Says whether the Mac is being kept awake, in which mode, for how much longer, and why."),
    ]

    public mutating func tool(_ call: ToolCall, now: Date) throws -> ToolResult {
        switch call.tool {
        case "keep_awake_start":
            start(minutes: call.number("minutes").map { Int($0) }, mode: call.text("mode").flatMap(Mode.init) ?? saved.mode, now: now)
            return .text(status(at: now))
        case "keep_awake_stop":
            saved.session = nil
            return .text(status(at: now))
        case "keep_awake_status":
            return .text(status(at: now))
        default:
            throw AddOnError("Wide Awake has no tool named \(call.tool).")
        }
    }

    /// One sentence on what's happening, for the AI tools.
    public func status(at now: Date) -> String {
        if let session = saved.session {
            let length = session.remaining(at: now).map { "for " + spoken($0) + " more" } ?? "until it's stopped"
            return "The Mac is being kept awake (\(session.mode.phrase)) \(length)."
        }
        if let mode = holding(at: now) {
            return "The Mac is being kept awake automatically (\(mode.phrase)): \(reasons.joined(separator: ", "))."
        }
        return "The Mac sleeps normally."
    }
}
