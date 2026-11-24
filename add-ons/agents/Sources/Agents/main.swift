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
    /// Shows Codex's sessions, read from its session logs.
    private var codex = true
    private let codexWatcher = CodexWatcher()
    /// Shows Cursor's agent sessions, read from its transcripts.
    private var cursor = true
    private let cursorWatcher = CursorWatcher()
    private var asking = false
    private var problem: String?
    private var ticker: Task<Void, Never>?
    private var codexTicker: Task<Void, Never>?
    /// The session the page shows, once the person picked one; otherwise the latest.
    private var focused: String?
    private var showingAll = false
    private var showingUsage = false
    /// The agent whose ring was pressed, for its limits in full.
    private var usageDetail: String?
    /// How much of each agent's plan is used, by "claude" and "codex", as they last said.
    private var usage: [String: AgentUsage] = [:]
    private var usageFile: URL?
    /// Whether Claude Code's status line is Ledge's, so it passes on the plan's usage.
    private var relaysUsage = false
    private var otherStatusLine = false
    /// Where the board is saved between runs.
    private var boardFile: URL?
    private var prefs = Prefs()
    /// Which usage alerts were dropped, saved with the usage.
    private var alerts = UsageAlerts()
    /// The usage alert in the notch now, and until when.
    private var alert: (text: String, until: Date)?
    /// When each session's turn started, for a pill that shows only for a moment.
    private var turnStarted: [String: Date] = [:]

    /// Claude Code's user settings, through a symlink if it's one, so a dotfiles link stays a link.
    private var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json").resolvingSymlinksInPath()
    }

    // MARK: Starting

    func start() async {
        Task { for await job in sessionJobs { Task { await job() } } }
        approvals = (try? await LedgeHost.value(Bool.self, forKey: "approvals")) ?? true
        codex = (try? await LedgeHost.value(Bool.self, forKey: "codex")) ?? true
        cursor = (try? await LedgeHost.value(Bool.self, forKey: "cursor")) ?? true
        prefs = await Prefs.load()
        alerts = (try? await LedgeHost.value(UsageAlerts.self, forKey: "usageAlerts")) ?? UsageAlerts()
        do {
            let path = try await LedgeHost.dataFolder().appendingPathComponent("hooks.sock").path
            server = try HookServer(path: path) { data in await addOn.receive(data) }
            socketPath = path
        } catch {
            problem = "Ledge couldn't open its socket for Claude Code"
            AddOnSession.log("No socket: \(error)", level: .error)
        }
        readSettings()
        usageFile = try? await LedgeHost.dataFolder().appendingPathComponent("usage.json")
        if let usageFile, let data = try? Data(contentsOf: usageFile) { usage = (try? JSONDecoder().decode([String: AgentUsage].self, from: data)) ?? [:] }
        if codex, let latest = codexWatcher.latestUsage() { setUsage("codex", latest) }
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
        codexTicker = Task {
            while !Task.isCancelled {
                self.readCodex()
                self.readCursor()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        ticker?.cancel()
        codexTicker?.cancel()
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
        readSettings()
        drop(alerts.resets())
        show()
    }

    private func readSettings() {
        let data = try? Data(contentsOf: claudeSettings)
        connected = ClaudeHooks.isConnected(data)
        relaysUsage = ClaudeHooks.relaysUsage(data)
        otherStatusLine = ClaudeHooks.hasOtherStatusLine(data)
    }

    private func setUsage(_ agent: String, _ new: AgentUsage) {
        guard usage[agent] != new else { return }
        usage[agent] = new
        if let usageFile, let data = try? JSONEncoder().encode(usage) { try? data.write(to: usageFile, options: .atomic) }
        let dropped = alerts.update(agent: agent, usage: new, threshold: Double(prefs.warnAt) ?? 90)
        drop(dropped)
        if showingUsage || !dropped.isEmpty { show() }
    }

    /// Shows a usage alert in the notch for a few seconds, if the settings ask for that kind, and saves what was said.
    private func drop(_ dropped: [UsageAlerts.Alert]) {
        guard !dropped.isEmpty else { return }
        let saved = alerts
        Task { try? await LedgeHost.set(saved, forKey: "usageAlerts") }
        let texts = dropped.filter { alert in
            switch alert {
            case .low: prefs.warnLow
            case .reset: prefs.tellReset
            }
        }.map(text)
        guard let text = texts.last else { return }
        raise(text)
    }

    /// Shows an alert for 6 seconds, then gives the notch back to the agent's pill.
    private func raise(_ text: String) {
        alert = (String(text.prefix(60)), Date().addingTimeInterval(6))
        Task {
            try? await Task.sleep(for: .seconds(6.1))
            self.show()
        }
    }

    private func text(_ alert: UsageAlerts.Alert) -> String {
        let names = ["claude": "Claude Code", "codex": "Codex"]
        switch alert {
        case let .low(agent, window):
            let used = Int(window.usedPercent.rounded())
            return prefs.showLeft ? "\(names[agent] ?? agent): \(100 - used)% of the \(window.name.lowercased()) limit left"
                : "\(names[agent] ?? agent): \(used)% of the \(window.name.lowercased()) limit used"
        case let .reset(agent, limit):
            return "\(names[agent] ?? agent): \(limit.lowercased()) limit is back to full"
        }
    }

    /// Plays the finish sound and notes turns starting, from the sessions before and after an update.
    private func noticeTurns(from before: [String: AgentSession]) {
        let now = Date()
        var finished = false
        for (id, session) in board.sessions {
            let was = before[id]?.state
            if session.state == .working, was != .working, was != .asking { turnStarted[id] = now }
            if session.state == .done, was != nil, was != .done { finished = true }
        }
        turnStarted = turnStarted.filter { board.sessions[$0.key] != nil }
        if finished { FinishSound.play(prefs.finishSound) }
    }

    // MARK: Codex

    /// What Codex's session logs gained since the last look.
    private func readCodex() {
        guard codex else { return }
        let batch = codexWatcher.poll()
        for id in batch.fresh { board.remove(id) }
        // A log read from its start replays old turns: no sound for those.
        let before = batch.fresh.isEmpty ? board.sessions : [:]
        var changed = !batch.fresh.isEmpty
        for (session, record) in batch.records {
            if let payload = record["payload"] as? [String: Any], payload["type"] as? String == "token_count",
               let new = AgentUsage.codex(payload) { setUsage("codex", new) }
            if board.applyCodex(record, session: session) { changed = true }
        }
        if changed, batch.fresh.isEmpty { noticeTurns(from: before) }
        if changed { show() }
    }

    /// What Cursor's agent transcripts gained since the last look.
    private func readCursor() {
        guard cursor else { return }
        let batch = cursorWatcher.poll()
        for id in batch.fresh { board.remove(id) }
        let before = batch.fresh.isEmpty ? board.sessions : [:]
        var changed = !batch.fresh.isEmpty
        for entry in batch.records where board.applyCursor(entry.record, session: entry.session, folder: entry.folder, at: entry.date) {
            changed = true
        }
        if changed, batch.fresh.isEmpty { noticeTurns(from: before) }
        if changed { show() }
    }

    // MARK: Hooks

    /// One event from a hook. Returns what the hook prints: a decision for a permission request, otherwise nothing.
    func receive(_ data: Data) async -> Data {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Data() }
        // The status line: no event name, and the plan's usage for subscribers. It prints nothing.
        if event["hook_event_name"] == nil {
            if let new = AgentUsage.claude(event) { setUsage("claude", new) }
            return Data()
        }
        let before = board.sessions
        guard let id = board.apply(event) else { return Data() }
        noticeTurns(from: before)
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
            readSettings()
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
        case (Surface.notchPage, "settings", .pressed):
            // The click that asked for it just arrived, so Ledge lets the add-on open its own settings.
            try? await LedgeHost.openSettings()
            return
        case (Surface.notchPage, "sessions", .pressed) where event.item == nil:
            // Sessions again, while it's showing, lists every session.
            showingAll = !showingUsage && board.sessions.count > 1
            showingUsage = false
            usageDetail = nil
        case (Surface.notchPage, "usage", .pressed):
            showingUsage = true
            showingAll = false
            usageDetail = nil
        case (Surface.notchPage, let ring, .pressed) where ring.hasPrefix("ring-"):
            usageDetail = String(ring.dropFirst(5))
        case (Surface.notchPage, PageScreen.backControl, .pressed):
            showingAll = false
            usageDetail = nil
        case (Surface.settingsPage, "previewLow", .pressed):
            let used = Double(prefs.warnAt) ?? 90
            raise(text(.low(agent: "codex", window: .init(usedPercent: used, minutes: 10_080, resetsAt: nil))))
        case (Surface.settingsPage, "previewReset", .pressed):
            raise(text(.reset(agent: "codex", limit: "Weekly")))
        case (Surface.notchPage, "sessions", .pressed):
            focused = event.item
            showingAll = false
        case (Surface.settingsPage, "codex", .toggled(let on)):
            codex = on
            try? await LedgeHost.set(on, forKey: "codex")
            if !on { for session in board.sorted where session.agent == .codex { board.remove(session.id) } }
        case (Surface.settingsPage, "cursor", .toggled(let on)):
            cursor = on
            try? await LedgeHost.set(on, forKey: "cursor")
            if !on { for session in board.sorted where session.agent == .cursor { board.remove(session.id) } }
        case (Surface.settingsPage, "approvals", .toggled(let on)):
            approvals = on
            try? await LedgeHost.set(on, forKey: "approvals")
        case (Surface.settingsPage, let key, .toggled(let on)) where Prefs.toggles.contains(key):
            prefs.set(key, on)
            try? await LedgeHost.set(on, forKey: key)
        case (Surface.settingsPage, let key, .picked(let choice)) where Prefs.pickers.contains(key):
            prefs.set(key, choice)
            try? await LedgeHost.set(choice, forKey: key)
            if key == "finishSound" { FinishSound.play(choice) }
        default:
            return
        }
        show()
    }

    // MARK: What Ledge draws

    private func show() {
        if let boardFile, let data = try? JSONEncoder().encode(board) { try? data.write(to: boardFile, options: .atomic) }
        // Usage is a row of rings: the small card fits it without space left under them.
        // The small card fits the rings, a session's card and a plan's limits without room left under them; the list of
        // every session takes the medium one.
        AddOnSession.show(notchPage: NotchPage(title: "Agents", symbol: "sparkle", size: showingAll && !showingUsage ? .medium : .small,
                                               screen: screen()))
        AddOnSession.show(settingsPage())
        AddOnSession.show(activities: activities())
    }

    /// The most recently active session in the notch while it works, asks, or has just finished: the logo and progress,
    /// with words only when it asks. A usage alert shows for a few seconds on its own.
    private func activities() -> [LiveActivity] {
        let now = Date()
        var list: [LiveActivity] = []
        if let alert, alert.until > now {
            // The alert has the notch to itself for its few seconds: an agent's pill would lead Home over it.
            return [LiveActivity("usage", symbol: "gauge.with.dots.needle.100percent", text: alert.text, importance: .high,
                                 lasts: alert.until.timeIntervalSince(now))]
        }
        // One that asks, else one still working, before one that just finished: another session's tick must not
        // cover work still under way, which nothing would bring back when the tick ends.
        guard let session = board.sorted.first(where: { $0.state == .asking })
                ?? board.sorted.first(where: { $0.state == .working })
                ?? board.sorted.first(where: { $0.state == .done && now.timeIntervalSince($0.updated) < 5 })
        else { return list }
        let text = String("\(session.folder) · \(session.step)".prefix(60))
        // "When music is also playing, show Agents": the agent leads Home and takes the notch from the song.
        let leads = prefs.musicShows == "agents"
        switch session.state {
        case .asking:
            list.append(LiveActivity("agent", symbol: "hand.raised", text: text, importance: .high, leadsHome: leads))
        case .done:
            // No text: closed, the notch shows the agent's picture and a green tick, then lets it go.
            list.append(LiveActivity("agent", symbol: "checkmark.circle", text: "", progress: .done,
                                     lasts: max(1, 5 - now.timeIntervalSince(session.updated)), accessibilityValue: text,
                                     image: Self.image(session)))
        default:
            // With "Keep agent status in the notch" off, the pill shows for a moment as a turn starts, then goes.
            if !prefs.keepStatus {
                let since = turnStarted[session.id] ?? now
                guard now.timeIntervalSince(since) < 5 else { return list }
                list.append(LiveActivity("agent", symbol: "sparkle", text: "", progress: .indeterminate,
                                         lasts: 5 - now.timeIntervalSince(since), accessibilityValue: text, image: Self.image(session)))
                return list
            }
            list.append(LiveActivity("agent", symbol: "sparkle", text: "", progress: .indeterminate, accessibilityValue: text,
                                     image: Self.image(session), leadsHome: leads))
        }
        return list
    }

    /// The gear opens the add-on's settings; Sessions and Usage switch the page between the two views.
    /// Always the same three, LedgeKit's most.
    private static let settingsAction = PageAction("settings", symbol: "gearshape", label: "Agents Settings", tint: .blue)

    private func actions(usage: Bool) -> [PageAction] {
        // Three at most fit the header. With more than one session, Sessions again lists them all.
        // Each in its own colour, the gear last, at the right edge.
        [PageAction("sessions", symbol: "checklist", label: board.sessions.count > 1 && !usage ? "All sessions" : "Sessions",
                    selected: !usage, tint: .orange),
         PageAction("usage", symbol: "gauge.with.dots.needle.50percent", label: "Usage", selected: usage, tint: .green),
         Self.settingsAction]
    }

    private func screen() -> PageScreen {
        if let problem {
            return PageScreen("main", actions: [Self.settingsAction],
                              content: .empty(symbol: "exclamationmark.triangle", title: problem, detail: nil))
        }
        if showingUsage { return usageScreen() }
        if showingAll {
            return PageScreen("all", depth: 1, title: "Sessions", back: true, content: .list(id: "sessions", rows:
                board.sorted.prefix(Surface.maximumListRows).map { session in
                    ListRow(String(session.id.prefix(64)), title: String(session.folder.prefix(60)),
                            subtitle: String("\(session.agent.name) · \(session.step)".prefix(80)),
                            detail: session.added + session.removed > 0 ? "+\(session.added) −\(session.removed)" : nil,
                            symbol: Self.symbol(session.state))
                }))
        }
        guard let session = focused.flatMap({ board.sessions[$0] }) ?? board.sorted.first else {
            // Idle, the agents on this Mac in a row, as Droppy shows them.
            let tiles = Self.installedAgents.map { agent in
                PageNode.vstack(spacing: 6, children: [.image(agent.icon, size: 44, motion: nil), .text(agent.name, style: .caption)])
            }
            guard !tiles.isEmpty else {
                return PageScreen("main", actions: actions(usage: false),
                                  content: .empty(symbol: "sparkle", title: "No sessions", detail: "Start Claude Code, Codex or Cursor and it shows here"))
            }
            return PageScreen("main", actions: actions(usage: false),
                              content: .vstack(spacing: 10, children: [
                                  .hstack(spacing: 22, children: [.spacer] + tiles + [.spacer]),
                                  .text(connected ? "Start an agent and it shows here." : "Start an agent and it shows here. Connect Claude Code with the gear.",
                                        style: .secondary),
                              ]))
        }
        // The agent, then what it's doing and what you asked, as Droppy's card has it.
        let picture: PageNode = session.agent == .claude
            ? .image(Mascot.png, size: 24, motion: session.state == .working ? .shake : nil)
            : Self.image(session).map { .image($0, size: 22, motion: nil) } ?? .symbol("chevron.left.forwardslash.chevron.right", size: 18)
        let header = PageNode.hstack(spacing: 8, children: [
            picture, .text(session.agent.name, style: .title),
            .label(PageLabel(Self.status(session.state), symbol: "circle.fill", tint: Self.tint(session.state), style: .caption)),
            .text(session.prompt ?? session.folder, style: .secondary), .spacer,
        ])
        let steps = PageNode.vstack(spacing: 6, children: session.steps.suffix(3).map { step in
            .label(PageLabel(step.text, symbol: step.done ? "checkmark" : "play.fill", tint: .orange, tintsText: false))
        })
        var columns: [PageNode] = [session.steps.isEmpty ? .text(session.step, style: .body) : steps, .spacer]
        // What it last said beside the steps; before it says anything, the file or command it's on.
        if let message = session.message {
            columns.append(.text(message, style: .secondary))
        } else if let card = session.card {
            columns.append(Self.card(card))
        }
        // No title or caption: beside the camera the header has room for only a word, and the folder reads better here.
        return PageScreen("main", actions: actions(usage: false),
                          content: .vstack(spacing: 12, children: [header, .hstack(spacing: 16, children: columns)]))
    }

    /// A ring for each agent: how much is left (or used) of the limit the settings pick, and when it resets.
    private typealias UsageAgent = (key: String, name: String, image: Data?, symbol: String?, unknown: String, why: String)

    /// The agents the Usage view has a ring for, with what their ring says while their usage isn't known, and why.
    private var usageAgents: [UsageAgent] {
        let claudeWhy = !connected ? "Connect Claude Code in Settings to see its usage."
            : relaysUsage ? "Claude Code reports usage after your next prompt."
            : otherStatusLine ? "Claude Code gives usage only to your own status line."
            : "Reconnect Claude Code in Settings to see its usage."
        var agents: [UsageAgent] = [
            ("claude", "Claude Code", AgentIcons.png("Claude") ?? Mascot.png, nil,
             !connected ? "Connect in Settings" : relaysUsage ? "After your next prompt"
                : otherStatusLine ? "Uses your status line" : "Reconnect in Settings", claudeWhy),
        ]
        if codex {
            agents.append(("codex", "Codex", Self.codexIcon, "chevron.left.forwardslash.chevron.right", "After Codex runs",
                           "Codex reports its limits as it runs. Start Codex."))
        }
        if cursor, let icon = AgentIcons.png("Cursor") {
            agents.append(("cursor", "Cursor", icon, nil, "Not reported",
                           "Cursor keeps its limits online, not on this Mac."))
        }
        return agents
    }

    private func usageScreen() -> PageScreen {
        if let key = usageDetail, let agent = usageAgents.first(where: { $0.key == key }) { return usageDetailScreen(agent) }
        var rings: [PageNode] = []
        var notes: [String] = []
        let agents = usageAgents
        for agent in agents {
            guard let window = usage[agent.key].flatMap(prefs.window) else {
                rings.append(.ring(PageRing(id: "ring-\(agent.key)", value: nil, image: agent.image, symbol: agent.symbol, title: agent.name,
                                            caption: agent.unknown, accessibilityLabel: "\(agent.name), usage not known")))
                continue
            }
            let used = max(0, min(100, window.usedPercent))
            let left = 100 - used
            let shown = prefs.showLeft ? left : used
            let words = prefs.showLeft ? "left" : "used"
            let tint = Self.tint(left: left)
            let reset = window.resetsAt.map { ", resets \($0.formatted(.relative(presentation: .named)))" } ?? ""
            rings.append(.ring(PageRing(id: "ring-\(agent.key)", value: shown / 100, image: agent.image, symbol: agent.symbol, title: agent.name,
                                        caption: "\(Int(shown.rounded()))% \(words)", tint: tint,
                                        accessibilityLabel: String("\(agent.name), \(window.name.lowercased()) limit, \(Int(shown.rounded()))% \(words)\(reset)".prefix(120)))))
        }
        if agents.first.map({ usage[$0.key] == nil }) == true, connected, otherStatusLine {
            notes.append("Claude Code gives usage only to your own status line.")
        }
        // Rings alone, as Droppy's: the reset time is in each ring's VoiceOver label.
        var children: [PageNode] = [.hstack(spacing: 36, children: [.spacer] + rings + [.spacer])]
        if !notes.isEmpty { children.append(.text(notes.joined(separator: "\n"), style: .secondary)) }
        return PageScreen("usage", actions: actions(usage: true), content: .vstack(spacing: 8, children: children))
    }

    private static func tint(left: Double) -> PageTint { left <= 10 ? .red : left <= 25 ? .orange : .green }

    /// One agent's limits in full, from pressing its ring: its plan, then each limit with when it resets and how much is
    /// left, as a bar.
    private func usageDetailScreen(_ agent: UsageAgent) -> PageScreen {
        let known = usage[agent.key]
        let header = PageNode.hstack(spacing: 10, children: [
            agent.image.map { .image($0, size: 28, motion: nil) } ?? .symbol(agent.symbol ?? "sparkle", size: 20),
            .vstack(spacing: 2, children: [.text(agent.name, style: .title)]
                + (known?.plan.map { [.text($0.capitalized, style: .secondary)] } ?? [])),
            .spacer,
        ])
        guard let known, !known.windows.isEmpty else {
            return PageScreen("usage-\(agent.key)", depth: 1, title: "Usage", back: true,
                              content: .vstack(spacing: 12, children: [header, .text(agent.why, style: .secondary)]))
        }
        let now = Date()
        let rows = known.windows.map { window -> PageNode in
            // A limit whose reset passed is full again, until the agent says otherwise.
            let passed = window.resetsAt.map { $0 <= now } ?? false
            let used = passed ? 0 : max(0, min(100, window.usedPercent))
            let shown = prefs.showLeft ? 100 - used : used
            let reset = passed ? "Reset" : window.resetsAt.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? ""
            return .vstack(spacing: 6, children: [
                .hstack(spacing: 8, children: [
                    .text(window.name, style: .body), .text(reset, style: .secondary), .spacer,
                    .label(PageLabel("\(Int(shown.rounded()))% \(prefs.showLeft ? "left" : "used")", tint: Self.tint(left: 100 - used),
                                     style: .caption)),
                ]),
                .progress(shown / 100, label: nil),
            ])
        }
        return PageScreen("usage-\(agent.key)", depth: 1, title: "Usage", back: true,
                          content: .vstack(spacing: 12, children: [header] + rows))
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
        return .panel(.vstack(spacing: 6, children: [
            .hstack(spacing: 6, children: [.symbol(card.kind == .command ? "terminal" : "doc.text", size: 12),
                                           .text(String(card.title.prefix(40)), style: .monospaced)]),
            .text(caption, style: .body),
            // Full when it's finished; while it runs Ledge can't know how far, so it fills over a minute.
            .progress(card.finished != nil ? 1 : min(0.9, Date().timeIntervalSince(card.started) / 60), label: nil),
        ]))
    }

    /// Codex's own app icon, else ChatGPT's, which comes with Codex's desktop app; nil when neither is installed.
    private static var codexIcon: Data? { AgentIcons.png("Codex") ?? AgentIcons.png("ChatGPT") }

    /// Claude's mascot stands for its sessions beside the notch; Codex's and Cursor's use their apps' icons, else the add-on's.
    private static func image(_ session: AgentSession) -> Data? {
        switch session.agent {
        case .claude: Mascot.png
        case .codex: codexIcon
        case .cursor: AgentIcons.png("Cursor")
        }
    }

    /// The coding agents installed on this Mac, with their apps' icons, in Droppy's order.
    private static var installedAgents: [(name: String, icon: Data)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let claude = AgentIcons.png("Claude") ?? (FileManager.default.fileExists(atPath: home + "/.claude") ? Mascot.png : nil)
        let candidates: [(String, Data?)] = [
            ("Claude", claude), ("Codex", codexIcon), ("Cursor", AgentIcons.png("Cursor")),
            ("Antigravity", AgentIcons.png("Antigravity IDE") ?? AgentIcons.png("Antigravity")), ("OpenCode", AgentIcons.png("OpenCode")),
        ]
        return candidates.compactMap { name, icon in icon.map { (name, $0) } }
    }

    private static func status(_ state: AgentSession.State) -> String {
        switch state {
        case .ready: "Ready"
        case .working: "Working"
        case .asking: "Waiting for approval"
        case .waiting: "Waiting for you"
        case .done: "Done"
        }
    }

    /// The status dot's colour: orange while it works or asks, green when it's done.
    private static func tint(_ state: AgentSession.State) -> PageTint? {
        switch state {
        case .working, .asking: .orange
        case .waiting: .blue
        case .done: .green
        case .ready: nil
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

    /// Laid out as Droppy's: how it behaves, then each agent, then usage.
    private func settingsPage() -> SettingsPage {
        let sounds = [SettingsRow.Option("none", "None")] + FinishSound.names.map { SettingsRow.Option($0, $0) }
        let plan = usage["codex"]?.plan.map { " · \($0.capitalized)" } ?? ""
        return SettingsPage([
            SettingsSection("settings", title: "Settings", rows: [
                .toggle("approvals", "Answer agents from the notch",
                        detail: "When Claude Code wants permission for a tool, Ledge asks in the notch. With no answer in \(Int(Self.askFor)) seconds, Claude Code asks as usual.",
                        isOn: approvals),
                .toggle("keepStatus", "Keep agent status in the notch", detail: "Keep the Agents pill up while an agent runs.",
                        isOn: prefs.keepStatus),
                .picker("musicShows", "When music is also playing, show",
                        detail: "Which the closed notch shows while an agent runs and music plays. Agents also opens the notch on the agent.",
                        options: [.init("agents", "Agents"), .init("music", "Music")], selected: prefs.musicShows),
                .picker("finishSound", "Sound when an agent finishes",
                        detail: "Plays when an agent's turn is done, so you can look away.", options: sounds, selected: prefs.finishSound),
            ]),
            SettingsSection("agents", title: "Agents",
                            footer: "Connecting Claude Code adds Ledge's hooks to ~/.claude/settings.json and keeps the rest of it. Where you have no status line, it adds one that shows nothing and passes your plan's usage to Ledge. The file as it was is saved beside it as settings.json.ledge-backup. Codex is read from its session logs in ~/.codex/sessions, and nothing in Codex changes. Nothing leaves this Mac.",
                            rows: [
                                connected ? .button("disconnect", "Disconnect", detail: "Claude Code · Connected", destructive: true)
                                    : .button("connect", "Connect", detail: "Claude Code · Not connected"),
                                .toggle("codex", "Codex\(codex ? plan : "")", detail: "Follows Codex in the terminal and the desktop app.", isOn: codex),
                                .toggle("cursor", "Cursor", detail: "Follows Agent mode in Cursor, from its transcripts in ~/.cursor/projects.", isOn: cursor),
                                .value("antigravity", "Antigravity", AgentIcons.png("Antigravity IDE") == nil ? "Not installed" : "Not followed yet"),
                                .value("opencode", "OpenCode", AgentIcons.png("OpenCode") == nil ? "Not installed" : "Not followed yet"),
                            ]),
            SettingsSection("usage", title: "Usage", rows: [
                .toggle("showLeft", "Show what is left", detail: "Rings and alerts show what is left instead of what is used.",
                        isOn: prefs.showLeft),
                .picker("ringWindow", "Rings show", detail: "An agent without that limit shows the one closest to running out.",
                        options: [.init("closest", "Closest to its limit"), .init("five", "5-hour limit"), .init("weekly", "Weekly limit")],
                        selected: prefs.ringWindow),
                .toggle("warnLow", "Warn when a limit runs low",
                        detail: "A notch alert once per window when an agent's limit crosses the level below.", isOn: prefs.warnLow),
                .picker("warnAt", "Warn at", options: ["75", "80", "90", "95"].map { .init($0, "\($0)% used") }, selected: prefs.warnAt),
                .toggle("tellReset", "Tell me when a limit resets",
                        detail: "A notch alert when a limit that was running low is back to full.", isOn: prefs.tellReset),
                .button("previewLow", "Running low", detail: "Preview alerts"),
                .button("previewReset", "Back to full", detail: "Preview alerts"),
            ]),
        ], keywords: ["claude", "claude code", "codex", "agents", "coding", "hooks", "permission", "usage", "limit", "ai"])
    }
}

/// The add-on's choices, as the settings page shows them.
struct Prefs {
    var keepStatus = true
    var musicShows = "agents"
    var finishSound = "none"
    var showLeft = true
    var ringWindow = "closest"
    var warnLow = true
    var warnAt = "90"
    var tellReset = true

    static let toggles: Set<String> = ["keepStatus", "showLeft", "warnLow", "tellReset"]
    static let pickers: Set<String> = ["musicShows", "finishSound", "ringWindow", "warnAt"]

    mutating func set(_ key: String, _ on: Bool) {
        switch key {
        case "keepStatus": keepStatus = on
        case "showLeft": showLeft = on
        case "warnLow": warnLow = on
        case "tellReset": tellReset = on
        default: break
        }
    }

    mutating func set(_ key: String, _ choice: String) {
        switch key {
        case "musicShows": musicShows = choice
        case "finishSound": finishSound = choice
        case "ringWindow": ringWindow = choice
        case "warnAt": warnAt = choice
        default: break
        }
    }

    static func load() async -> Prefs {
        var prefs = Prefs()
        for key in toggles { if let on = try? await LedgeHost.value(Bool.self, forKey: key) { prefs.set(key, on) } }
        for key in pickers { if let choice = try? await LedgeHost.value(String.self, forKey: key) { prefs.set(key, choice) } }
        return prefs
    }

    /// The limit a ring shows: the one picked, else the one closest to running out.
    func window(_ usage: AgentUsage) -> AgentUsage.Window? {
        let minutes = ringWindow == "five" ? 300 : ringWindow == "weekly" ? 10_080 : nil
        if let minutes, let picked = usage.windows.first(where: { $0.minutes == minutes }),
           picked.resetsAt.map({ $0 > Date() }) ?? true { return picked }
        return usage.tightest()
    }
}

let addOn = Agents()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.deactivate = { await addOn.stop() }
handlers.prepareForRemoval = { await addOn.remove() }
handlers.onEvent = { event in await addOn.handle(event) }
exit(await AddOnSession.run(id: "agents", handlers: handlers))
