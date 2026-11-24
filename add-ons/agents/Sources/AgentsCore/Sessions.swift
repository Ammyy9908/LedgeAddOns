import Foundation

/// One coding agent's session: Claude Code's as its hooks describe it, Codex's as its session log does.
public struct AgentSession: Equatable, Sendable, Codable {
    public enum Agent: String, Equatable, Sendable, Codable {
        case claude, codex, cursor
        public var name: String {
            switch self {
            case .claude: "Claude"
            case .codex: "Codex"
            case .cursor: "Cursor"
            }
        }
    }

    public enum State: Equatable, Sendable, Codable {
        /// Started, no prompt yet.
        case ready
        case working
        /// Wants permission for a tool.
        case asking
        /// Waiting for the person's next prompt.
        case waiting
        case done
    }

    public let id: String
    /// The last part of the session's working directory.
    public var folder: String
    public var state: State = .ready
    /// What it's doing, in a few words: "Editing Foo.swift".
    public var step = "Ready"
    /// What it did since the last prompt, oldest first: "Edit Hero.swift", "Run swift build".
    public var steps: [Step] = []
    /// The file or command it's on, or was on last.
    public var card: Card?
    /// Lines added and removed by its edits so far.
    public var added = 0
    public var removed = 0
    public var updated: Date
    /// What the person last asked, on one line.
    public var prompt: String?
    /// What the agent last said: its reply, or its words between tools.
    public var message: String?
    /// Nil for Claude Code, so boards saved before Codex came along still load.
    var agentKind: Agent?

    /// Which agent the session belongs to.
    public var agent: Agent {
        get { agentKind ?? .claude }
        set { agentKind = newValue == .claude ? nil : newValue }
    }
}

public struct Step: Equatable, Sendable, Codable {
    public let id: String
    public var text: String
    public var done = false
}

/// The file a tool is reading or changing, or the command it runs.
public struct Card: Equatable, Sendable, Codable {
    public enum Kind: Equatable, Sendable, Codable { case file, command }
    public let id: String
    public let kind: Kind
    /// The file's path inside the session's folder, or the command's first line.
    public let title: String
    public let started: Date
    public var finished: Date?
    /// "Lines 184", "+12 −3".
    public var detail: String?
}

/// Every session Ledge heard from, kept up to date from hook events. Saved, so a restart of Ledge or the add-on
/// doesn't empty the page until the next hook.
public struct SessionBoard: Sendable, Codable {
    public internal(set) var sessions: [String: AgentSession] = [:]

    public init() {}

    /// Most recently active first.
    public var sorted: [AgentSession] { sessions.values.sorted { $0.updated > $1.updated } }

    /// Applies one hook event, as Claude Code sends it. Returns the session it was about, if any.
    @discardableResult
    public mutating func apply(_ event: [String: Any], at date: Date = Date()) -> String? {
        guard let id = event["session_id"] as? String, !id.isEmpty, let name = event["hook_event_name"] as? String else { return nil }
        if name == "SessionEnd" {
            sessions[id] = nil
            return id
        }
        let cwd = event["cwd"] as? String ?? ""
        var session = sessions[id] ?? AgentSession(id: id, folder: Self.folder(cwd), updated: date)
        if !cwd.isEmpty { session.folder = Self.folder(cwd) }
        session.updated = date
        let tool = event["tool_name"] as? String ?? ""
        let input = event["tool_input"] as? [String: Any] ?? [:]
        switch name {
        case "SessionStart":
            if session.state == .done { session.state = .ready; session.step = "Ready" }
        case "UserPromptSubmit":
            session.prompt = Self.line(Self.typed(event["prompt"] as? String), limit: 200)
            session.message = nil
            session.state = .working
            session.step = "Thinking"
            session.steps = []
            session.card = nil
        case "PreToolUse":
            let toolID = event["tool_use_id"] as? String ?? UUID().uuidString
            session.state = .working
            session.step = Describe.step(tool: tool, input: input)
            session.steps = Array((session.steps + [Step(id: toolID, text: Describe.done(tool: tool, input: input))]).suffix(Self.keptSteps))
            if let card = Describe.card(tool: tool, input: input, cwd: cwd, id: toolID, at: date) { session.card = card }
        case "PostToolUse":
            let toolID = event["tool_use_id"] as? String
            let changes = Describe.lineChanges(tool: tool, input: input)
            session.added += changes.added
            session.removed += changes.removed
            session.state = .working
            session.step = "Thinking"
            if let index = session.steps.lastIndex(where: { $0.id == toolID }) { session.steps[index].done = true }
            if session.card?.id == toolID {
                session.card?.finished = date
                session.card?.detail = Describe.cardDetail(tool: tool, input: input, response: event["tool_response"], changes: changes)
            }
        case "PermissionRequest":
            session.state = .asking
            session.step = "Wants to \(Describe.verb(tool: tool, input: input))"
        case "Notification":
            switch event["notification_type"] as? String {
            case "idle_prompt": session.state = .waiting; session.step = "Waiting for you"
            case "permission_prompt": session.state = .asking; session.step = "Waiting for approval"
            default: break
            }
        case "Stop":
            if let said = Self.line(event["last_assistant_message"] as? String, limit: 400) { session.message = said }
            session.state = .done
            session.step = "Done"
            for index in session.steps.indices { session.steps[index].done = true }
            // Its tool's PostToolUse can go missing (the tool failed, or Ledge restarted while it ran); stopped, it's over.
            if session.card?.finished == nil { session.card?.finished = date }
        default:
            break
        }
        sessions[id] = session
        return id
    }

    /// After the person answered a permission request in Ledge.
    public mutating func answered(_ id: String, allowed: Bool) {
        guard var session = sessions[id], session.state == .asking else { return }
        session.state = .working
        session.step = allowed ? "Thinking" : "Denied"
        session.updated = Date()
        sessions[id] = session
    }

    /// What the person typed, without the `<system-reminder>` blocks Claude Code puts around a prompt.
    static func typed(_ prompt: String?) -> String? {
        prompt?.replacingOccurrences(of: "<system-reminder>[\\s\\S]*?</system-reminder>", with: " ", options: .regularExpression)
    }

    /// Text on one line, cut to `limit`; nil when there's nothing.
    static func line(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let joined = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return joined.count > limit ? String(joined.prefix(limit - 1)) + "…" : joined
    }

    /// Forgets one session, before its log is read again from the start.
    public mutating func remove(_ id: String) { sessions[id] = nil }

    /// Forgets sessions that went quiet, such as ones whose terminal closed without a SessionEnd.
    public mutating func forget(quietSince date: Date) {
        sessions = sessions.filter { $0.value.updated >= date }
    }

    static let keptSteps = 20

    static func folder(_ cwd: String, or fallback: String = "Claude Code") -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? fallback : name
    }
}

/// Words for what a tool does, for the notch.
public enum Describe {
    public static func step(tool: String, input: [String: Any]) -> String {
        let file = fileName(input)
        let text: String
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": text = "Editing \(file ?? "a file")"
        case "Read": text = "Reading \(file ?? "a file")"
        case "Bash":
            if let description = input["description"] as? String, !description.isEmpty { text = description }
            else { text = "Running \(firstLine(input["command"]) ?? "a command")" }
        case "Grep", "Glob": text = "Searching the code"
        case "WebFetch", "WebSearch": text = "Searching the web"
        case "Task", "Agent": text = "Running a subagent"
        case "TodoWrite": text = "Planning"
        default:
            if tool.hasPrefix("mcp__") { text = "Using \(server(tool))" }
            else { text = "Using \(tool.isEmpty ? "a tool" : tool)" }
        }
        return short(text)
    }

    /// A step in the list: "Edit Hero.swift", "Run swift build".
    public static func done(tool: String, input: [String: Any]) -> String {
        let file = fileName(input) ?? "a file"
        switch tool {
        case "Edit", "MultiEdit", "NotebookEdit": return short("Edit \(file)")
        case "Write": return short("Write \(file)")
        case "Read": return short("Read \(file)")
        case "Bash": return short("Run \(firstLine(input["command"]) ?? "a command")")
        default: return step(tool: tool, input: input)
        }
    }

    /// The card for a tool that works on a file or runs a command; nil for others.
    public static func card(tool: String, input: [String: Any], cwd: String, id: String, at date: Date) -> Card? {
        switch tool {
        case "Bash":
            guard let command = firstLine(input["command"]) else { return nil }
            return Card(id: id, kind: .command, title: command, started: date)
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
            guard let path = (input["file_path"] ?? input["notebook_path"]) as? String else { return nil }
            let inside = !cwd.isEmpty && path.hasPrefix(cwd + "/") ? String(path.dropFirst(cwd.count + 1)) : (path as NSString).lastPathComponent
            return Card(id: id, kind: .file, title: inside, started: date)
        default:
            return nil
        }
    }

    /// What the card says once its tool finished.
    static func cardDetail(tool: String, input: [String: Any], response: Any?, changes: (added: Int, removed: Int)) -> String? {
        switch tool {
        case "Read":
            let lines = ((response as? [String: Any])?["file"] as? [String: Any])?["numLines"] as? Int
            return lines.map { "Lines \($0)" }
        case "Write": return "Lines \(changes.added)"
        case "Edit", "MultiEdit": return "+\(changes.added) −\(changes.removed)"
        default: return nil
        }
    }

    static func short(_ text: String) -> String {
        text.count > 50 ? text.prefix(49).trimmingCharacters(in: .whitespaces) + "…" : text
    }

    /// "run a command", "edit Foo.swift": what a permission request is for.
    public static func verb(tool: String, input: [String: Any]) -> String {
        switch tool {
        case "Bash": return "run a command"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "edit \(fileName(input) ?? "a file")"
        case "Read": return "read \(fileName(input) ?? "a file")"
        case "WebFetch": return "open a web page"
        case "WebSearch": return "search the web"
        default: return tool.hasPrefix("mcp__") ? "use \(server(tool))" : "use \(tool.isEmpty ? "a tool" : tool)"
        }
    }

    /// The question Ledge asks for a permission request.
    public static func permission(tool: String, input: [String: Any], folder: String) -> (title: String, message: String?) {
        let detail = (input["command"] ?? input["file_path"] ?? input["url"] ?? input["query"] ?? input["description"]) as? String
        return (String("Claude Code in \(folder) wants to \(verb(tool: tool, input: input))".prefix(120)),
                detail.map { String($0.prefix(400)) })
    }

    /// Lines an edit added and removed, from the text it replaced.
    public static func lineChanges(tool: String, input: [String: Any]) -> (added: Int, removed: Int) {
        switch tool {
        case "Edit": return diff(input["old_string"], input["new_string"])
        case "MultiEdit":
            return (input["edits"] as? [[String: Any]] ?? []).reduce((0, 0)) { total, edit in
                let change = diff(edit["old_string"], edit["new_string"])
                return (total.0 + change.added, total.1 + change.removed)
            }
        case "Write": return (lines(input["content"]).count, 0)
        default: return (0, 0)
        }
    }

    static func diff(_ old: Any?, _ new: Any?) -> (added: Int, removed: Int) {
        let before = lines(old), after = lines(new)
        // shortcut: counts whole blocks past 2,000 lines instead of diffing them, as a diff that size is slow.
        guard before.count <= 2_000, after.count <= 2_000 else { return (after.count, before.count) }
        let difference = after.difference(from: before)
        return (difference.insertions.count, difference.removals.count)
    }

    static func lines(_ text: Any?) -> [Substring] {
        guard let text = text as? String, !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    static func fileName(_ input: [String: Any]) -> String? {
        ((input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String).map { ($0 as NSString).lastPathComponent }
    }

    static func firstLine(_ text: Any?) -> String? {
        (text as? String)?.split(separator: "\n").first.map { String($0.prefix(40)) }
    }

    static func server(_ tool: String) -> String {
        // mcp__<server>__<tool>
        let parts = tool.components(separatedBy: "__")
        return parts.count >= 2 && !parts[1].isEmpty ? parts[1] : "a tool"
    }
}
