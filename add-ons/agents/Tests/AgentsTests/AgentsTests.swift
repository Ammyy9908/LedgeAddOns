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

@Suite struct CodexLogTests {
    private func record(_ type: String, _ payload: [String: Any], at time: String = "2026-11-24T10:00:00.000Z") -> [String: Any] {
        ["timestamp": time, "type": type, "payload": payload]
    }

    @Test func desktopExecCommandsAndPatchesBecomeSteps() {
        let run = CodexLog.call(["call_id": "a", "name": "exec", "input": #"const r = await tools.exec_command({cmd:"swift build --product Ledge", yield_time_ms: 1000});"#])
        #expect(run?.step == "Running swift build --product Ledge")
        #expect(run?.card?.kind == .command)
        let patch = CodexLog.call(["call_id": "b", "name": "exec",
                                   "input": #"await tools.apply_patch("*** Begin Patch\n*** Update File: /x/Sources/Hero.swift\n@@\n-old\n+new\n+more\n*** End Patch");"#])
        #expect(patch?.step == "Editing Hero.swift")
        #expect(patch?.added == 2 && patch?.removed == 1)
        #expect(patch?.card?.detail == "+2 −1")
    }

    @Test func cliCallsAndQuestions() {
        let shell = CodexLog.call(["call_id": "c", "name": "shell", "arguments": #"{"command":["bash","-lc","ls -la"]}"#])
        #expect(shell?.done == "Run ls -la")
        #expect(CodexLog.call(["call_id": "d", "name": "request_user_input_async", "arguments": "{}"])?.asks == true)
        #expect(CodexLog.call(["call_id": "e", "name": "js", "namespace": "mcp__cua_repl", "arguments": #"{"title":"Open Settings"}"#])?.step == "Open Settings")
        #expect(CodexLog.call(["name": "shell"]) == nil)
    }

    @Test func aTurnGoesFromWorkingToDone() {
        var board = SessionBoard()
        board.applyCodex(record("session_meta", ["cwd": "/Users/me/ledge"]), session: "codex:1")
        board.applyCodex(record("event_msg", ["type": "task_started"]), session: "codex:1")
        board.applyCodex(record("response_item", ["type": "custom_tool_call", "call_id": "a", "name": "exec",
                                                  "input": #"tools.exec_command({cmd:"make"})"#]), session: "codex:1")
        var session = board.sessions["codex:1"]
        #expect(session?.agent == .codex && session?.folder == "ledge" && session?.state == .working)
        #expect(session?.steps.map(\.done) == [false])
        board.applyCodex(record("response_item", ["type": "custom_tool_call_output", "call_id": "a"]), session: "codex:1")
        board.applyCodex(record("event_msg", ["type": "task_complete"], at: "2026-11-24T10:01:00.000Z"), session: "codex:1")
        session = board.sessions["codex:1"]
        #expect(session?.state == .done && session?.steps.map(\.done) == [true] && session?.card?.finished != nil)
        #expect(session?.updated == CodexLog.date("2026-11-24T10:01:00.000Z"))
        // Records it doesn't use change nothing.
        let changed = board.applyCodex(record("event_msg", ["type": "token_count"]), session: "codex:1")
        #expect(!changed)
    }
}

@Test func theStatusLineIsAddedOnlyWhereThereIsNoneAndTakenOutOnlyIfOurs() throws {
    let connected = try ClaudeHooks.connect(nil, command: command)
    #expect(ClaudeHooks.relaysUsage(connected))
    #expect(try json(ClaudeHooks.disconnect(connected))["statusLine"] == nil)
    let theirs = #"{"statusLine":{"type":"command","command":"~/bin/line"}}"#
    let kept = try ClaudeHooks.connect(Data(theirs.utf8), command: command)
    #expect(!ClaudeHooks.relaysUsage(kept))
    #expect((try json(ClaudeHooks.disconnect(kept))["statusLine"] as? [String: Any])?["command"] as? String == "~/bin/line")
}

@Test func usageReadsBothAgentsAndAPassedResetCountsAsUnused() throws {
    let codex = try #require(AgentUsage.codex(["rate_limits": [
        "primary": ["used_percent": 95.0, "window_minutes": 10080, "resets_at": 1_795_760_379],
        "secondary": NSNull(), "plan_type": "plus"]]))
    #expect(codex.windows.count == 1 && codex.plan == "plus" && codex.windows[0].name == "Weekly")
    let claude = try #require(AgentUsage.claude(["rate_limits": [
        "five_hour": ["used_percentage": 40, "resets_at": 1_000],
        "seven_day": ["used_percentage": 70, "resets_at": 2_000]]]))
    #expect(claude.tightest(now: Date(timeIntervalSince1970: 500))?.usedPercent == 70)
    // The weekly one reset: the 5-hour one, also reset, is no closer.
    #expect(claude.tightest(now: Date(timeIntervalSince1970: 3_000))?.usedPercent == 0)
    #expect(AgentUsage.claude(["session_id": "a"]) == nil)
}

@Test func someoneElsesStatusLineIsTold() throws {
    #expect(ClaudeHooks.hasOtherStatusLine(Data(#"{"statusLine":{"type":"command","command":"x"}}"#.utf8)))
    #expect(!ClaudeHooks.hasOtherStatusLine(try ClaudeHooks.connect(nil, command: command)))
    #expect(!ClaudeHooks.hasOtherStatusLine(nil))
}

@Test func thePromptAndTheLatestMessageAreKeptOnOneLine() {
    var board = SessionBoard()
    board.apply(["session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "fix\n  the   notch"])
    #expect(board.sessions["s"]?.prompt == "fix the notch")
    board.apply(["session_id": "s", "hook_event_name": "Stop", "last_assistant_message": "Done.\nIt works."])
    #expect(board.sessions["s"]?.message == "Done. It works.")
    board.applyCodex(["type": "event_msg", "payload": ["type": "user_message", "message": "add tests"]], session: "codex:2")
    board.applyCodex(["type": "event_msg", "payload": ["type": "agent_message", "message": "Adding them now"]], session: "codex:2")
    #expect(board.sessions["codex:2"]?.prompt == "add tests" && board.sessions["codex:2"]?.message == "Adding them now")
    #expect(SessionBoard.line(String(repeating: "a", count: 10), limit: 5) == "aaaa…")
}

@Test func usageWarnsOncePerWindowAndTellsWhenALowLimitResets() {
    var alerts = UsageAlerts()
    let reset = Date(timeIntervalSince1970: 1_000)
    func usage(_ used: Double, _ resets: Date) -> AgentUsage { AgentUsage(windows: [.init(usedPercent: used, minutes: 10_080, resetsAt: resets)]) }
    #expect(alerts.update(agent: "codex", usage: usage(50, reset), threshold: 90).isEmpty)
    #expect(alerts.update(agent: "codex", usage: usage(95, reset), threshold: 90).count == 1)
    #expect(alerts.update(agent: "codex", usage: usage(96, reset), threshold: 90).isEmpty)
    #expect(alerts.resets(now: Date(timeIntervalSince1970: 500)).isEmpty)
    #expect(alerts.resets(now: Date(timeIntervalSince1970: 2_000)) == [.reset(agent: "codex", limit: "Weekly")])
    // Low again in a new window, then that window resets with fresh usage.
    #expect(alerts.update(agent: "codex", usage: usage(92, Date(timeIntervalSince1970: 9_000)), threshold: 90).count == 1)
    #expect(alerts.update(agent: "codex", usage: usage(3, Date(timeIntervalSince1970: 20_000)), threshold: 90) == [.reset(agent: "codex", limit: "Weekly")])
}

@Test func aPromptLosesClaudeCodesReminders() {
    var board = SessionBoard()
    board.apply(["session_id": "s", "hook_event_name": "UserPromptSubmit",
                 "prompt": "<system-reminder>\nLinked sessions now\n</system-reminder>\n\nmatch droppy's settings"])
    #expect(board.sessions["s"]?.prompt == "match droppy's settings")
}

@Test func aCursorTurnGoesFromItsQueryThroughToolsToDone() {
    var board = SessionBoard()
    let at = Date(timeIntervalSince1970: 100)
    func send(_ record: [String: Any]) { board.applyCursor(record, session: "cursor:1", folder: "droplet", at: at) }
    send(["role": "user", "message": ["content": [["type": "text", "text": "<timestamp>Sun</timestamp>\n<user_query>fix the wave</user_query>"]]]])
    send(["role": "assistant", "message": ["content": [["type": "text", "text": "Looking at it."],
                                                       ["type": "tool_use", "name": "Read", "input": ["path": "/a/Wave.swift"]]]]])
    var session = board.sessions["cursor:1"]
    #expect(session?.agent == .cursor && session?.prompt == "fix the wave" && session?.message == "Looking at it.")
    #expect(session?.state == .working && session?.steps.count == 1 && session?.steps[0].done == false)
    send(["type": "turn_ended", "status": "success"])
    session = board.sessions["cursor:1"]
    #expect(session?.state == .done && session?.steps[0].done == true)
    #expect(SessionBoard.cursorFolder("Users-sam-code-ledge") == "ledge")
}
