import Foundation
import Testing
@testable import AgentsCore

private let command = ClaudeHooks.command(socket: "/Users/sam/Library/Application Support/Ledge/AddOnData/agents/hooks.sock")

private func json(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

// MARK: Claude Code's settings

@Test func connectingKeepsEverythingElseAndDisconnectingTakesOnlyLedgesHooks() throws {
    let theirs = """
    {"model": "opus", "permissions": {"allow": ["Bash(ls:*)"]},
     "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "./check.sh"}]}],
               "SubagentStop": []}}
    """
    let connected = try ClaudeHooks.connect(Data(theirs.utf8), command: command)
    #expect(ClaudeHooks.isConnected(connected))
    let settings = try json(connected)
    #expect(settings["model"] as? String == "opus")
    #expect((settings["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
    let hooks = try #require(settings["hooks"] as? [String: Any])
    #expect((hooks["PreToolUse"] as? [Any])?.count == 2)
    #expect((hooks["PermissionRequest"] as? [Any])?.count == 1)
    #expect(hooks["SubagentStop"] as? [Any] != nil)

    // Connecting again replaces Ledge's hooks rather than adding a second set.
    let again = try json(ClaudeHooks.connect(connected, command: command))
    #expect(((again["hooks"] as? [String: Any])?["PreToolUse"] as? [Any])?.count == 2)

    let disconnected = try ClaudeHooks.disconnect(connected)
    #expect(!ClaudeHooks.isConnected(disconnected))
    let left = try #require(try json(disconnected)["hooks"] as? [String: Any])
    #expect(Set(left.keys) == ["PreToolUse", "SubagentStop"])
    #expect((left["PreToolUse"] as? [Any])?.count == 1)
}

@Test func aMissingOrEmptyFileConnectsAndAFileItCantReadIsLeftAlone() throws {
    #expect(ClaudeHooks.isConnected(try ClaudeHooks.connect(nil, command: command)))
    #expect(ClaudeHooks.isConnected(try ClaudeHooks.connect(Data(" \n".utf8), command: command)))
    #expect(try json(ClaudeHooks.disconnect(try ClaudeHooks.connect(nil, command: command))).isEmpty)
    for unreadable in ["{ \"model\": ", "[1, 2]", "{\"hooks\": []}"] {
        #expect(throws: ClaudeHooks.Unreadable.self) { try ClaudeHooks.connect(Data(unreadable.utf8), command: command) }
        #expect(!ClaudeHooks.isConnected(Data(unreadable.utf8)))
    }
}

@Test func theCommandQuotesThePathAndNeverFailsTheHook() {
    let quoted = ClaudeHooks.command(socket: "/Users/o'brien/Library/Application Support/x.sock")
    #expect(quoted == "/usr/bin/nc -U '/Users/o'\\''brien/Library/Application Support/x.sock' 2>/dev/null || true # ledge-agents")
}

@Test func decisionsAreWhatClaudeCodeReads() throws {
    let allow = try json(ClaudeHooks.decision(allow: true))["hookSpecificOutput"] as? [String: Any]
    #expect(allow?["hookEventName"] as? String == "PermissionRequest")
    #expect((allow?["decision"] as? [String: Any])?["behavior"] as? String == "allow")
    let deny = try json(ClaudeHooks.decision(allow: false))["hookSpecificOutput"] as? [String: Any]
    #expect((deny?["decision"] as? [String: Any])?["behavior"] as? String == "deny")
}

// MARK: Sessions

@Test func aSessionFollowsItsHooks() {
    var board = SessionBoard()
    func send(_ name: String, _ extra: [String: Any] = [:]) {
        board.apply(["session_id": "s1", "cwd": "/Users/sam/code/ledge", "hook_event_name": name].merging(extra) { $1 })
    }
    send("SessionStart")
    #expect(board.sessions["s1"]?.folder == "ledge")
    #expect(board.sessions["s1"]?.state == .ready)
    send("UserPromptSubmit", ["prompt": "fix it"])
    #expect(board.sessions["s1"]?.step == "Thinking")
    send("PreToolUse", ["tool_name": "Edit", "tool_use_id": "t1", "tool_input": ["file_path": "/Users/sam/code/ledge/App/Notch.swift"]])
    #expect(board.sessions["s1"]?.step == "Editing Notch.swift")
    #expect(board.sessions["s1"]?.steps == [Step(id: "t1", text: "Edit Notch.swift")])
    #expect(board.sessions["s1"]?.card?.title == "App/Notch.swift")
    #expect(board.sessions["s1"]?.card?.finished == nil)
    send("PostToolUse", ["tool_name": "Edit", "tool_use_id": "t1",
                         "tool_input": ["file_path": "/x/Notch.swift", "old_string": "a\nb\nc", "new_string": "a\nB\nc\nd"]])
    #expect(board.sessions["s1"]?.added == 2)
    #expect(board.sessions["s1"]?.removed == 1)
    #expect(board.sessions["s1"]?.steps.first?.done == true)
    #expect(board.sessions["s1"]?.card?.finished != nil)
    #expect(board.sessions["s1"]?.card?.detail == "+2 −1")
    send("PreToolUse", ["tool_name": "Bash", "tool_use_id": "t2", "tool_input": ["command": "swift build"]])
    send("PreToolUse", ["tool_name": "Grep", "tool_use_id": "t3", "tool_input": ["pattern": "x"]])
    #expect(board.sessions["s1"]?.card?.kind == .command)
    #expect(board.sessions["s1"]?.card?.title == "swift build")
    #expect(board.sessions["s1"]?.steps.map(\.text) == ["Edit Notch.swift", "Run swift build", "Searching the code"])
    send("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "rm -rf build"]])
    #expect(board.sessions["s1"]?.state == .asking)
    board.answered("s1", allowed: true)
    #expect(board.sessions["s1"]?.state == .working)
    send("Stop")
    #expect(board.sessions["s1"]?.state == .done)
    #expect(board.sessions["s1"]?.card?.finished != nil)
    #expect(board.sessions["s1"]?.steps.allSatisfy(\.done) == true)
    send("UserPromptSubmit")
    #expect(board.sessions["s1"]?.steps.isEmpty == true)
    #expect(board.sessions["s1"]?.card == nil)
    send("SessionEnd")
    #expect(board.sessions.isEmpty)
}

@Test func eventsWithoutASessionAreIgnoredAndQuietSessionsAreForgotten() {
    var board = SessionBoard()
    #expect(board.apply(["hook_event_name": "Stop"]) == nil)
    board.apply(["session_id": "old", "cwd": "/a", "hook_event_name": "Stop"], at: Date(timeIntervalSinceNow: -3600))
    board.apply(["session_id": "new", "cwd": "/", "hook_event_name": "UserPromptSubmit"])
    #expect(board.sessions["new"]?.folder == "Claude Code")
    board.forget(quietSince: Date(timeIntervalSinceNow: -1800))
    #expect(Array(board.sessions.keys) == ["new"])
}

@Test func theBoardSurvivesASaveAndLoad() throws {
    var board = SessionBoard()
    board.apply(["session_id": "s1", "cwd": "/a/ledge", "hook_event_name": "PreToolUse", "tool_name": "Bash",
                 "tool_use_id": "t1", "tool_input": ["command": "swift build"]])
    let loaded = try JSONDecoder().decode(SessionBoard.self, from: JSONEncoder().encode(board))
    #expect(loaded.sessions == board.sessions)
}

@Test func toolsReadAsShortSteps() {
    #expect(Describe.step(tool: "Bash", input: ["command": "swift build\n--quiet", "description": "Build the app"]) == "Build the app")
    #expect(Describe.step(tool: "Bash", input: ["command": "swift build\n--quiet"]) == "Running swift build")
    #expect(Describe.step(tool: "mcp__github__create_pr", input: [:]) == "Using github")
    #expect(Describe.step(tool: "Grep", input: ["pattern": "x"]) == "Searching the code")
    #expect(Describe.permission(tool: "Bash", input: ["command": "rm -rf build"], folder: "ledge")
        == ("Claude Code in ledge wants to run a command", "rm -rf build"))
    let read = Describe.cardDetail(tool: "Read", input: [:], response: ["type": "text", "file": ["numLines": 184]], changes: (0, 0))
    #expect(read == "Lines 184")
    #expect(Describe.card(tool: "Read", input: ["file_path": "/etc/hosts"], cwd: "/Users/sam/x", id: "r", at: Date())?.title == "hosts")
    #expect(Describe.lineChanges(tool: "Write", input: ["content": "a\nb\n"]) == (3, 0))
    #expect(Describe.lineChanges(tool: "MultiEdit", input: ["edits": [["old_string": "a", "new_string": "b"], ["old_string": "", "new_string": "c"]]]) == (2, 1))
}
