import Foundation

/// How much of an agent's plan is used: one entry per limit it reports, such as a 5-hour and a weekly one.
public struct AgentUsage: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        /// 0 to 100.
        public var usedPercent: Double
        public var minutes: Int?
        public var resetsAt: Date?

        public init(usedPercent: Double, minutes: Int?, resetsAt: Date?) {
            self.usedPercent = usedPercent; self.minutes = minutes; self.resetsAt = resetsAt
        }

        /// "5-hour" or "Weekly", from its length.
        public var name: String {
            switch minutes {
            case 10_080?: "Weekly"
            case let minutes? where minutes % 60 == 0: "\(minutes / 60)-hour"
            case let minutes?: "\(minutes)-minute"
            case nil: "Plan"
            }
        }
    }

    public var windows: [Window]
    public var plan: String?

    public init(windows: [Window], plan: String? = nil) {
        self.windows = windows; self.plan = plan
    }

    /// The limit closest to running out; a window whose reset has passed counts as unused.
    public func tightest(now: Date = Date()) -> Window? {
        windows.map { window in
            guard let reset = window.resetsAt, reset <= now else { return window }
            return Window(usedPercent: 0, minutes: window.minutes, resetsAt: nil)
        }.max { $0.usedPercent < $1.usedPercent }
    }

    /// Codex's `token_count` event: `rate_limits` with a `primary` and a `secondary` window.
    public static func codex(_ payload: [String: Any]) -> AgentUsage? {
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let windows = ["primary", "secondary"].compactMap { key -> Window? in
            guard let window = limits[key] as? [String: Any], let used = number(window["used_percent"]) else { return nil }
            return Window(usedPercent: used, minutes: number(window["window_minutes"]).map(Int.init),
                          resetsAt: number(window["resets_at"]).map(Date.init(timeIntervalSince1970:)))
        }
        return windows.isEmpty ? nil : AgentUsage(windows: windows, plan: limits["plan_type"] as? String)
    }

    /// Claude Code's status line input: `rate_limits` with `five_hour` and `seven_day`, for subscribers only.
    public static func claude(_ status: [String: Any]) -> AgentUsage? {
        guard let limits = status["rate_limits"] as? [String: Any] else { return nil }
        let windows = [("five_hour", 300), ("seven_day", 10_080)].compactMap { key, minutes -> Window? in
            guard let window = limits[key] as? [String: Any], let used = number(window["used_percentage"]) else { return nil }
            return Window(usedPercent: used, minutes: minutes,
                          resetsAt: number(window["resets_at"]).map(Date.init(timeIntervalSince1970:)))
        }
        return windows.isEmpty ? nil : AgentUsage(windows: windows)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber).map(\.doubleValue) ?? (value as? String).flatMap(Double.init)
    }
}

/// When to drop a notch alert about usage: once per window when a limit crosses the warning level, and once when a
/// limit that ran low is back to full. Saved, so a restart doesn't warn again about the same window.
public struct UsageAlerts: Codable, Equatable, Sendable {
    /// Windows already warned about: agent, limit and reset time.
    var warned: Set<String> = []
    /// Limits that ran low, by agent and limit, with when they reset.
    var low: [String: Date] = [:]

    public init() {}

    public enum Alert: Equatable, Sendable {
        case low(agent: String, window: AgentUsage.Window)
        case reset(agent: String, limit: String)
    }

    /// What an agent's new usage calls for. `threshold` is the percent used that warns.
    public mutating func update(agent: String, usage: AgentUsage, threshold: Double) -> [Alert] {
        var alerts: [Alert] = []
        for window in usage.windows {
            let limit = "\(agent)|\(window.name)"
            if window.usedPercent >= threshold {
                let key = "\(limit)|\(Int(window.resetsAt?.timeIntervalSince1970 ?? 0))"
                if warned.insert(key).inserted { alerts.append(.low(agent: agent, window: window)) }
                low[limit] = window.resetsAt ?? .distantFuture
            } else if let resets = low[limit], window.resetsAt != resets {
                // A new window began below the level: the one that ran low reset.
                low[limit] = nil
                alerts.append(.reset(agent: agent, limit: window.name))
            }
        }
        return alerts
    }

    /// Limits that ran low and whose reset time has passed, before the agent says so.
    public mutating func resets(now: Date = Date()) -> [Alert] {
        let passed = low.filter { $0.value <= now }.keys.sorted()
        return passed.map { key in
            low[key] = nil
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return .reset(agent: parts[0], limit: parts.count > 1 ? parts[1] : "")
        }
    }
}
