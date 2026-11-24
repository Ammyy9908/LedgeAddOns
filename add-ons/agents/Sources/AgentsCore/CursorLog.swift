import Foundation

/// Cursor's agent transcripts, `~/.cursor/projects/<project>/agent-transcripts/<id>/<id>.jsonl`: one record per
/// line, `{role, message: {content: [...]}}` with text and `tool_use` parts, and `{type: "turn_ended"}` after a turn.
/// They carry no times, so the caller gives the file's.
extension SessionBoard {
    /// Applies one record of a Cursor transcript. Returns whether the session changed.
    @discardableResult
    public mutating func applyCursor(_ record: [String: Any], session id: String, folder: String, at date: Date) -> Bool {
        var session = sessions[id] ?? {
            var new = AgentSession(id: id, folder: folder, updated: date)
            new.agent = .cursor
            return new
        }()
        if record["type"] as? String == "turn_ended" {
            session.state = .done
            session.step = "Done"
            for index in session.steps.indices { session.steps[index].done = true }
        } else {
            let parts = (record["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            guard !parts.isEmpty else { return false }
            switch record["role"] as? String {
            case "user":
                let text = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
                session.prompt = Self.line(Self.cursorQuery(text), limit: 200)
                session.message = nil
                session.state = .working
                session.step = "Thinking"
                session.steps = []
                session.card = nil
            case "assistant":
                for part in parts {
                    if let text = part["text"] as? String, let said = Self.line(text, limit: 400) {
                        session.message = said
                    } else if part["type"] as? String == "tool_use", let tool = part["name"] as? String {
                        let input = part["input"] as? [String: Any] ?? [:]
                        // No results are written, so a tool is done once the next one starts.
                        for index in session.steps.indices { session.steps[index].done = true }
                        let stepID = "\(id)-\(session.steps.count)-\(tool)"
                        session.steps = Array((session.steps + [Step(id: stepID, text: Describe.done(tool: tool, input: input))]).suffix(Self.keptSteps))
                        session.step = Describe.step(tool: tool, input: input)
                    }
                }
                session.state = .working
            default:
                return false
            }
        }
        session.updated = max(session.updated, date)
        sessions[id] = session
        return true
    }

    /// What the person typed: Cursor wraps it in `<user_query>`, beside blocks such as `<timestamp>`.
    static func cursorQuery(_ text: String) -> String {
        if let range = text.range(of: "(?<=<user_query>)[\\s\\S]*?(?=</user_query>)", options: .regularExpression) {
            return String(text[range])
        }
        return text.replacingOccurrences(of: "<([a-z_]+)>[\\s\\S]*?</\\1>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[Image]", with: " ")
    }

    /// A project folder's name from Cursor's: the path with "/" turned into "-", so its last part.
    /// shortcut: a folder whose own name has a dash shows only what follows it; fine for a label.
    public static func cursorFolder(_ project: String) -> String {
        project.split(separator: "-").last.map(String.init) ?? "Cursor"
    }
}
