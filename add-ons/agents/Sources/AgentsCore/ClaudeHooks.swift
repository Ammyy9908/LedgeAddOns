import Foundation

/// Ledge's hooks in Claude Code's `settings.json`: puts them in, takes them out, and says whether they're there.
/// Everything else in the file stays as it was, apart from key order and spacing.
///
/// Each hook pipes Claude Code's event to the add-on's socket with `nc` and prints what the add-on answers, which
/// is nothing except for a permission decision. When Ledge isn't running, `nc` fails and `|| true` keeps that quiet,
/// so Claude Code carries on as if the hook weren't there.
public enum ClaudeHooks {
    /// Ends every command Ledge adds, so Ledge finds its own and nobody else's.
    public static let marker = "# ledge-agents"

    /// The events Ledge listens to, whether they take a tool matcher, and how long Claude Code waits for an answer.
    /// A permission request waits for the person, so longer than Ledge asks them.
    static let events: [(name: String, matcher: Bool, timeout: Int)] = [
        ("SessionStart", false, 5), ("UserPromptSubmit", false, 5), ("PreToolUse", true, 5), ("PostToolUse", true, 5),
        ("PermissionRequest", true, 120), ("Notification", false, 5), ("Stop", false, 5), ("SessionEnd", false, 5),
    ]

    public struct Unreadable: Error, CustomStringConvertible {
        public var description: String { "Claude Code's settings.json isn't a JSON object Ledge can read" }
    }

    public static func command(socket: String) -> String {
        "/usr/bin/nc -U '\(socket.replacingOccurrences(of: "'", with: "'\\''"))' 2>/dev/null || true \(marker)"
    }

    public static func isConnected(_ data: Data?) -> Bool {
        guard let settings = try? object(data), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { ($0 as? [Any])?.contains(where: isOurs) == true }
    }

    /// The settings with Ledge's hooks, replacing any it added before.
    public static func connect(_ data: Data?, command: String) throws -> Data {
        var settings = try without(object(data))
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": event.timeout]]]
            if event.matcher { entry["matcher"] = "*" }
            hooks[event.name] = (hooks[event.name] as? [Any] ?? []) + [entry]
        }
        settings["hooks"] = hooks
        // Claude Code tells only a status line how much of the plan is used. Ledge adds one that prints nothing, and
        // only where there's none: someone else's stays, and then the usage stays unknown.
        if settings["statusLine"] == nil { settings["statusLine"] = ["type": "command", "command": command] }
        return try serialize(settings)
    }

    /// The settings without Ledge's hooks.
    public static func disconnect(_ data: Data?) throws -> Data {
        try serialize(without(object(data)))
    }

    /// Whether the status line is Ledge's, so Claude Code passes it the plan's usage.
    public static func relaysUsage(_ data: Data?) -> Bool {
        guard let settings = try? object(data) else { return false }
        return isOurStatusLine(settings["statusLine"])
    }

    /// Whether someone else's status line is set, so connecting leaves Claude Code's usage unknown.
    public static func hasOtherStatusLine(_ data: Data?) -> Bool {
        guard let line = (try? object(data))?["statusLine"] else { return false }
        return !isOurStatusLine(line)
    }

    static func isOurStatusLine(_ value: Any?) -> Bool {
        ((value as? [String: Any])?["command"] as? String)?.hasSuffix(marker) == true
    }

    /// The decision a permission request hook prints.
    public static func decision(allow: Bool) -> Data {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = "The person denied this in Ledge." }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: output)) ?? Data()
    }

    static func object(_ data: Data?) throws -> [String: Any] {
        guard let data, data.contains(where: { !Set<UInt8>([0x20, 0x09, 0x0A, 0x0D]).contains($0) }) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Unreadable() }
        if let hooks = object["hooks"], !(hooks is [String: Any]) { throw Unreadable() }
        return object
    }

    static func isOurs(_ entry: Any) -> Bool {
        ((entry as? [String: Any])?["hooks"] as? [Any])?.contains {
            (($0 as? [String: Any])?["command"] as? String)?.hasSuffix(marker) == true
        } == true
    }

    static func without(_ settings: [String: Any]) -> [String: Any] {
        var settings = settings
        if isOurStatusLine(settings["statusLine"]) { settings["statusLine"] = nil }
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, entries) in hooks {
            guard let list = entries as? [Any] else { continue }
            let kept = list.filter { !isOurs($0) }
            if kept.count != list.count { hooks[event] = kept.isEmpty ? nil : kept }
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    static func serialize(_ settings: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
    }
}
