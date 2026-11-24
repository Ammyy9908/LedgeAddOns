import Foundation

/// Codex's session logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`): one JSON record per line, written as the
/// session runs. `SessionBoard.applyCodex` turns them into the same sessions Claude Code's hooks make.
///
/// The records used: `session_meta` and `turn_context` (the folder), `event_msg` `task_started`, `task_complete` and
/// `turn_aborted` (working, done), and `response_item` tool calls and their outputs (the steps). Codex Desktop wraps
/// commands and edits in an `exec` tool whose input is JavaScript calling `tools.exec_command({cmd: "…"})` and
/// `tools.apply_patch("…")`; the CLI calls `exec_command`, `shell` and `apply_patch` directly. Anything else is a step
/// named after its tool.
public enum CodexLog {
    /// What one tool call is doing.
    public struct Call: Equatable {
        public var id: String
        /// "Running swift build", "Editing Hero.swift".
        public var step: String
        /// "Run swift build", "Edit Hero.swift".
        public var done: String
        public var card: (kind: Card.Kind, title: String, detail: String?)?
        public var added = 0
        public var removed = 0
        /// Codex is asking the person something, in Codex.
        public var asks = false

        public static func == (a: Call, b: Call) -> Bool {
            a.id == b.id && a.step == b.step && a.done == b.done && a.card?.title == b.card?.title && a.added == b.added
                && a.removed == b.removed && a.asks == b.asks
        }
    }

    /// The tool call a `function_call` or `custom_tool_call` payload makes.
    public static func call(_ payload: [String: Any]) -> Call? {
        guard let id = payload["call_id"] as? String, let name = payload["name"] as? String else { return nil }
        let namespace = payload["namespace"] as? String ?? ""
        let input = payload["input"] as? String ?? ""
        let arguments = (payload["arguments"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
            as? [String: Any] ?? [:]
        switch name {
        case "exec":
            if let patch = jsString(after: "tools.apply_patch(", in: input) { return edit(id, patch: patch) }
            if let command = jsString(after: "cmd:", in: input) ?? jsString(after: "\"cmd\":", in: input) {
                return run(id, command: command)
            }
            return Call(id: id, step: input.contains("tools.write_stdin(") ? "Using the terminal" : "Running code",
                        done: "Ran code")
        case "apply_patch":
            return edit(id, patch: input.isEmpty ? (arguments["input"] as? String ?? "") : input)
        case "exec_command", "shell", "local_shell":
            let command = (arguments["cmd"] ?? arguments["command"]).flatMap { value -> String? in
                if let text = value as? String { return text }
                return (value as? [String]).map { $0.count == 3 && $0[1] == "-lc" ? $0[2] : $0.joined(separator: " ") }
            }
            return run(id, command: command ?? "")
        case "request_user_input_async", "request_user_input":
            return Call(id: id, step: "Asking you", done: "Asked you", asks: true)
        default:
            if let title = arguments["title"] as? String, !title.isEmpty {
                return Call(id: id, step: Describe.short(title), done: Describe.short(title))
            }
            let tool = namespace.hasPrefix("mcp__") ? Describe.server(namespace + "__" + name) : name
            return Call(id: id, step: Describe.short("Using \(tool)"), done: Describe.short("Used \(tool)"))
        }
    }

    static func run(_ id: String, command: String) -> Call {
        var line = command.split(separator: "\n").first.map(String.init) ?? ""
        for prefix in ["bash -lc ", "zsh -lc "] where line.hasPrefix(prefix) { line = String(line.dropFirst(prefix.count)) }
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        guard !line.isEmpty else { return Call(id: id, step: "Running a command", done: "Ran a command") }
        let title = String(line.prefix(40))
        return Call(id: id, step: Describe.short("Running \(title)"), done: Describe.short("Run \(title)"),
                    card: (.command, title, nil))
    }

    static func edit(_ id: String, patch: String) -> Call {
        var files: [String] = [], added = 0, removed = 0
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("*** ") {
                for marker in ["*** Add File: ", "*** Update File: ", "*** Delete File: "] where line.hasPrefix(marker) {
                    files.append((String(line.dropFirst(marker.count)) as NSString).lastPathComponent)
                }
            } else if line.hasPrefix("+") { added += 1 }
            else if line.hasPrefix("-") { removed += 1 }
        }
        let file = files.first ?? "a file"
        let name = files.count > 1 ? "\(file) and \(files.count - 1) more" : file
        return Call(id: id, step: Describe.short("Editing \(name)"), done: Describe.short("Edit \(name)"),
                    card: (.file, file, "+\(added) −\(removed)"), added: added, removed: removed)
    }

    /// The JavaScript string literal right after `marker`, unescaped: `cmd: "swift build"` gives `swift build`.
    static func jsString(after marker: String, in code: String) -> String? {
        guard let start = code.range(of: marker) else { return nil }
        var rest = code[start.upperBound...].drop { $0 == " " || $0 == "\n" }
        guard let quote = rest.first, quote == "\"" || quote == "'" || quote == "`" else { return nil }
        rest = rest.dropFirst()
        var out = "", escaped = false
        for character in rest {
            if escaped {
                switch character {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == quote {
                return out
            } else {
                out.append(character)
            }
        }
        return nil
    }

    static func date(_ text: String) -> Date? {
        try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

extension SessionBoard {
    /// Applies one record of a Codex session log. Returns whether the session changed.
    @discardableResult
    public mutating func applyCodex(_ record: [String: Any], session id: String) -> Bool {
        guard let payload = record["payload"] as? [String: Any] else { return false }
        let date = (record["timestamp"] as? String).flatMap(CodexLog.date) ?? Date()
        var session = sessions[id] ?? {
            var new = AgentSession(id: id, folder: "Codex", updated: date)
            new.agent = .codex
            return new
        }()
        switch (record["type"] as? String, payload["type"] as? String) {
        case ("session_meta", _), ("turn_context", _):
            guard let cwd = payload["cwd"] as? String else { return false }
            session.folder = Self.folder(cwd, or: "Codex")
        case ("event_msg", "task_started"):
            session.state = .working
            session.step = "Thinking"
            session.steps = []
            session.card = nil
        case ("event_msg", "user_message"):
            guard let said = Self.line(payload["message"] as? String, limit: 200) else { return false }
            session.prompt = said
            session.message = nil
        case ("event_msg", "agent_message"):
            guard let said = Self.line(payload["message"] as? String, limit: 400) else { return false }
            session.message = said
        case ("event_msg", "task_complete"), ("event_msg", "turn_aborted"):
            if let said = Self.line(payload["last_agent_message"] as? String, limit: 400) { session.message = said }
            session.state = .done
            session.step = payload["type"] as? String == "turn_aborted" ? "Stopped" : "Done"
            for index in session.steps.indices { session.steps[index].done = true }
            if session.card?.finished == nil { session.card?.finished = date }
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
            guard let call = CodexLog.call(payload) else { return false }
            session.state = call.asks ? .waiting : .working
            session.step = call.step
            session.steps = Array((session.steps + [Step(id: call.id, text: call.done)]).suffix(Self.keptSteps))
            if let card = call.card {
                session.card = Card(id: call.id, kind: card.kind, title: card.title, started: date, detail: card.detail)
            }
            session.added += call.added
            session.removed += call.removed
        case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
            let callID = payload["call_id"] as? String
            if let index = session.steps.lastIndex(where: { $0.id == callID }) { session.steps[index].done = true }
            if session.card?.id == callID { session.card?.finished = date }
            if session.state == .waiting || session.state == .working { session.state = .working; session.step = "Thinking" }
        default:
            return false
        }
        session.updated = max(session.updated, date)
        sessions[id] = session
        return true
    }
}
