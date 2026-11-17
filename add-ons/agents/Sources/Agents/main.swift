import AgentsCore
import Foundation
import LedgeKit

// Agents: what your Claude Code sessions are doing, beside the notch and on a page in it, and their permission
// prompts answered from the notch.
//
// Connecting adds hooks to ~/.claude/settings.json (ClaudeHooks). Claude Code then runs them on each prompt, tool
// call and stop, and they hand the event to this add-on's socket (HookServer). Nothing leaves the Mac.

/// Runs work that starts outside the session, on a socket thread, inside it: LedgeKit finds its session through a
/// task-local value, which only tasks started from the session's own tasks inherit.
private let (sessionJobs, sessionQueue) = AsyncStream<@Sendable () async -> Void>.makeStream()
func inSession(_ work: @escaping @Sendable () async -> Void) { sessionQueue.yield(work) }

actor Agents {
    /// How long Ledge waits for an answer to a permission prompt before leaving it to Claude Code.
    static let askFor: TimeInterval = 45

    private var board = SessionBoard()
    private var server: HookServer?
    private var socketPath: String?
    private var connected = false
    private var approvals = true
    private var asking = false
    private var problem: String?
    private var ticker: Task<Void, Never>?
    /// The session the page shows, once the person picked one; otherwise the latest.
    private var focused: String?
    private var showingAll = false
    /// Where the board is saved between runs.
    private var boardFile: URL?

    /// Claude Code's user settings, through a symlink if it's one, so a dotfiles link stays a link.
    private var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json").resolvingSymlinksInPath()
    }

    // MARK: Starting

    func start() async {
        Task { for await job in sessionJobs { Task { await job() } } }
        approvals = (try? await LedgeHost.value(Bool.self, forKey: "approvals")) ?? true
        do {
            let path = try await LedgeHost.dataFolder().appendingPathComponent("hooks.sock").path
            server = try HookServer(path: path) { data in await addOn.receive(data) }
            socketPath = path
        } catch {
            problem = "Ledge couldn't open its socket for Claude Code"
            AddOnSession.log("No socket: \(error)", level: .error)
        }
        connected = ClaudeHooks.isConnected(try? Data(contentsOf: claudeSettings))
        boardFile = try? await LedgeHost.dataFolder().appendingPathComponent("sessions.json")
        if let boardFile, let data = try? Data(contentsOf: boardFile), let saved = try? JSONDecoder().decode(SessionBoard.self, from: data) {
            board = saved
        }
        show()
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self.tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        server?.stop()
        server = nil
    }

    /// Taking the add-on away takes its hooks out of Claude Code's settings too.
    func remove() -> Bool {
        if connected { setConnected(false) }
        return true
    }

    private func tick() {
        board.forget(quietSince: Date().addingTimeInterval(-30 * 60))
        if let focused, board.sessions[focused] == nil { self.focused = nil }
        // The person may have edited the file themselves.
        connected = ClaudeHooks.isConnected(try? Data(contentsOf: claudeSettings))
        show()
    }

    // MARK: Hooks

    /// One event from a hook. Returns what the hook prints: a decision for a permission request, otherwise nothing.
    func receive(_ data: Data) async -> Data {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = board.apply(event) else { return Data() }
        show()
        guard event["hook_event_name"] as? String == "PermissionRequest" else { return Data() }
        return await approve(event, session: id)
    }

    private func approve(_ event: [String: Any], session id: String) async -> Data {
        let tool = event["tool_name"] as? String ?? ""
        // These two need Claude Code's own screens to answer, and only one question shows in the notch at a time.
        guard approvals, !asking, !["AskUserQuestion", "ExitPlanMode"].contains(tool) else { return Data() }
        asking = true
        defer { asking = false }
        let folder = board.sessions[id]?.folder ?? "Claude Code"
        let question = Describe.permission(tool: tool, input: event["tool_input"] as? [String: Any] ?? [:], folder: folder)
        let started = Date()
        guard let allow = try? await LedgeHost.ask(HostQuestion(title: question.title, message: question.message,
                                                                accept: "Allow", decline: "Deny", timeout: Self.askFor))
        else { return Data() }
        // No answer comes back as no; then Claude Code asks as usual rather than taking it as a denial.
        if !allow, Date().timeIntervalSince(started) >= Self.askFor - 1 { return Data() }
        board.answered(id, allowed: allow)
        show()
        return ClaudeHooks.decision(allow: allow)
    }

    // MARK: Connecting

    private func setConnected(_ on: Bool) {
        let url = claudeSettings
        do {
            let old = try? Data(contentsOf: url)
            let new: Data
            if on {
                guard let socketPath else { return }
                new = try ClaudeHooks.connect(old, command: ClaudeHooks.command(socket: socketPath))
            } else {
                new = try ClaudeHooks.disconnect(old)
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let old { try old.write(to: url.appendingPathExtension("ledge-backup"), options: .atomic) }
            try new.write(to: url, options: .atomic)
            connected = on
            problem = nil
        } catch {
            problem = error is ClaudeHooks.Unreadable ? "Ledge can't read ~/.claude/settings.json" : "Ledge couldn't change ~/.claude/settings.json"
            AddOnSession.log("Couldn't \(on ? "connect" : "disconnect"): \(error)", level: .error)
        }
    }

    // MARK: Events

    func handle(_ event: SurfaceEvent) async {
        switch (event.surface, event.control, event.action) {
        case (Surface.settingsPage, "connect", .pressed):
            setConnected(true)
        case (Surface.settingsPage, "disconnect", .pressed):
            setConnected(false)
        case (Surface.notchPage, "all", .pressed):
            showingAll = true
        case (Surface.notchPage, PageScreen.backControl, .pressed):
            showingAll = false
        case (Surface.notchPage, "sessions", .pressed):
            focused = event.item
            showingAll = false
        case (Surface.settingsPage, "approvals", .toggled(let on)):
            approvals = on
            try? await LedgeHost.set(on, forKey: "approvals")
        default:
            return
        }
        show()
    }

    // MARK: What Ledge draws

    private func show() {
        if let boardFile, let data = try? JSONEncoder().encode(board) { try? data.write(to: boardFile, options: .atomic) }
        AddOnSession.show(notchPage: NotchPage(title: "Agents", symbol: "sparkle", screen: screen()))
        AddOnSession.show(settingsPage())
        AddOnSession.show(activities: activities())
    }

    /// The most recently active session in the notch while it works, asks, or has just finished: the logo and progress,
    /// with words only when it asks.
    private func activities() -> [LiveActivity] {
        let now = Date()
        // One that asks, else one still working, before one that just finished: another session's tick must not
        // cover work still under way, which nothing would bring back when the tick ends.
        guard let session = board.sorted.first(where: { $0.state == .asking })
                ?? board.sorted.first(where: { $0.state == .working })
                ?? board.sorted.first(where: { $0.state == .done && now.timeIntervalSince($0.updated) < 5 })
        else { return [] }
        let text = String("\(session.folder) · \(session.step)".prefix(60))
        switch session.state {
        case .asking:
            return [LiveActivity("agent", symbol: "hand.raised", text: text, importance: .high)]
        case .done:
            // No text: closed, the notch shows the add-on's logo and a green tick, then lets it go.
            return [LiveActivity("agent", symbol: "checkmark.circle", text: "", progress: .done,
                                 lasts: max(1, 5 - now.timeIntervalSince(session.updated)), accessibilityValue: text, image: Mascot.png)]
        default:
            return [LiveActivity("agent", symbol: "sparkle", text: "", progress: .indeterminate, accessibilityValue: text, image: Mascot.png)]
        }
    }

    private func screen() -> PageScreen {
        if let problem {
            return PageScreen("main", content: .empty(symbol: "exclamationmark.triangle", title: problem, detail: nil))
        }
        if showingAll {
            return PageScreen("sessions", depth: 1, title: "Sessions", back: true, content: .list(id: "sessions", rows:
                board.sorted.prefix(Surface.maximumListRows).map { session in
                    ListRow(String(session.id.prefix(64)), title: String(session.folder.prefix(60)),
                            subtitle: String(session.step.prefix(80)),
                            detail: session.added + session.removed > 0 ? "+\(session.added) −\(session.removed)" : nil,
                            symbol: Self.symbol(session.state))
                }))
        }
        guard let session = focused.flatMap({ board.sessions[$0] }) ?? board.sorted.first else {
            return PageScreen("main", content: connected
                ? .empty(symbol: "sparkle", title: "No Claude Code sessions", detail: "Start one and it shows here")
                : .empty(symbol: "link", title: "Connect Claude Code", detail: "In Ledge's Settings, Add-ons, Agents"))
        }
        let actions = board.sessions.count > 1 ? [PageAction("all", symbol: "list.bullet", label: "All sessions")] : []
        let header = PageNode.hstack(spacing: 8, children: [
            .image(Mascot.png, size: 24, motion: session.state == .working ? .shake : nil), .text("Claude", style: .title), .text("\(session.folder) · \(Self.status(session.state))", style: .body), .spacer,
        ])
        let steps = PageNode.vstack(spacing: 6, children: session.steps.suffix(4).map { step in
            .hstack(spacing: 8, children: [.symbol(step.done ? "checkmark" : "play.fill", size: 11), .text(step.text, style: .body)])
        })
        var columns: [PageNode] = [session.steps.isEmpty ? .text(session.step, style: .body) : steps, .spacer]
        if let card = session.card { columns.append(Self.card(card)) }
        // No title or caption: beside the camera the header has room for only a word, and the folder reads better here.
        return PageScreen("main", actions: actions,
                          content: .vstack(spacing: 12, children: [header, .hstack(spacing: 16, children: columns)]))
    }

    /// The file or command it's on: what, then how far, like "Lines 184" or "Took 0.25 seconds".
    private static func card(_ card: Card) -> PageNode {
        let caption: String
        if let finished = card.finished {
            let seconds = finished.timeIntervalSince(card.started)
            caption = card.kind == .command
                ? "Took \(seconds < 10 ? String(format: "%.2f", seconds) : String(Int(seconds))) seconds"
                : card.detail ?? "Done"
        } else {
            caption = card.kind == .command ? "Running" : "Working"
        }
        return .vstack(spacing: 6, children: [
            .hstack(spacing: 6, children: [.symbol(card.kind == .command ? "terminal" : "doc.text", size: 12),
                                           .text(String(card.title.prefix(40)), style: .monospaced)]),
            .text(caption, style: .body),
            // Full when it's finished; while it runs Ledge can't know how far, so it fills over a minute.
            .progress(card.finished != nil ? 1 : min(0.9, Date().timeIntervalSince(card.started) / 60), label: nil),
        ])
    }

    private static func status(_ state: AgentSession.State) -> String {
        switch state {
        case .ready: "Ready"
        case .working: "Working on your task"
        case .asking: "Waiting for approval"
        case .waiting: "Waiting for you"
        case .done: "Done"
        }
    }

    private static func symbol(_ state: AgentSession.State) -> String {
        switch state {
        case .ready: "circle"
        case .working: "sparkle"
        case .asking: "hand.raised"
        case .waiting: "text.bubble"
        case .done: "checkmark.circle"
        }
    }

    private func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("claude", title: "Claude Code",
                            footer: "Connecting adds Ledge's hooks to ~/.claude/settings.json and keeps the rest of it; the file as it was is saved beside it as settings.json.ledge-backup. Sessions you start after connecting show in the notch. Nothing leaves this Mac.",
                            rows: [.value("status", "Status", connected ? "Connected" : "Not connected"),
                                   connected ? .button("disconnect", "Disconnect", destructive: true) : .button("connect", "Connect")]),
            SettingsSection("approvals", title: "Approvals",
                            footer: "When Claude Code wants permission for a tool, Ledge asks in the notch. With no answer in \(Int(Self.askFor)) seconds, Claude Code asks as usual.",
                            rows: [.toggle("approvals", "Answer permission prompts in the notch", isOn: approvals)]),
        ], keywords: ["claude", "claude code", "agents", "coding", "hooks", "permission", "ai"])
    }
}

let addOn = Agents()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.deactivate = { await addOn.stop() }
handlers.prepareForRemoval = { await addOn.remove() }
handlers.onEvent = { event in await addOn.handle(event) }
exit(await AddOnSession.run(id: "agents", handlers: handlers))
