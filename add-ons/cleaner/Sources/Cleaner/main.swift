import AppKit
import CleanerCore
import Foundation
import LedgeKit

// Cleaner: uninstall an app with the files it left in the person's Library, and clear caches, logs and developer data
// the Mac rebuilds. Everything is listed with its size and place first, nothing moves until the person presses Move to
// Trash, and everything goes to the Trash, so Put Back returns it. The scanning rules live in CleanerCore.

actor Cleaner {
    enum Screen: Equatable { case home, apps, review, storage }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var screen = Screen.home
    private var notice: String?
    private var busy: String?
    private var apps: [App] = []
    private var app: App?
    private var items: [Item] = []
    private var categories: [CleanerCore.Category] = []
    /// The last move to the Trash, for Put Back.
    private var lastMoved: [Trash.Moved] = []

    // Settings
    private var automatic = false
    private var every = "weekly"
    private var lastAutomatic: Date?
    private var timer: Task<Void, Never>?

    func start() async {
        automatic = (try? await LedgeHost.value(Bool.self, forKey: "automatic")) ?? false
        every = (try? await LedgeHost.value(String.self, forKey: "every")) ?? "weekly"
        lastAutomatic = (try? await LedgeHost.value(Double.self, forKey: "lastAutomatic")).map(Date.init(timeIntervalSince1970:))
        show()
        // Scheduled cleaning runs while nobody looks, by design: it checks once an hour whether it's due.
        timer = Task {
            while !Task.isCancelled {
                await self.cleanIfDue()
                try? await Task.sleep(for: .seconds(3600))  // ledgekit:allow unseen-polling
            }
        }
    }

    func stop() { timer?.cancel() }

    // MARK: Events

    func handle(_ event: SurfaceEvent) async {
        switch (event.surface, event.control, event.action) {
        case (Surface.settingsPage, "automatic", .toggled(let on)):
            automatic = on
            try? await LedgeHost.set(on, forKey: "automatic")
            await cleanIfDue()
        case (Surface.settingsPage, "every", .picked(let choice)):
            every = choice
            try? await LedgeHost.set(choice, forKey: "every")
        case (Surface.notchPage, PageScreen.backControl, .pressed):
            notice = nil
            screen = screen == .review && !apps.isEmpty ? .apps : .home
        case (Surface.notchPage, "home", .pressed):
            notice = nil
            if event.item == "uninstall" { await openApps() } else if event.item == "storage" { await openStorage() }
            return
        case (Surface.notchPage, "apps", .pressed):
            if let path = event.item, let picked = apps.first(where: { $0.url.path == path }) { await review(picked) }
            return
        case (Surface.notchPage, "items", .pressed):
            // The app itself always goes; its files can be left.
            if let index = event.item.flatMap(Int.init), items.indices.contains(index), index > 0 { items[index].checked.toggle() }
        case (Surface.notchPage, "categories", .pressed):
            if let index = categories.firstIndex(where: { $0.id == event.item }) { categories[index].checked.toggle() }
        case (Surface.notchPage, "trash", .pressed):
            await trash()
            return
        case (Surface.notchPage, "putback", .pressed):
            let back = Trash.putBack(lastMoved)
            lastMoved = []
            notice = "Put back \(back) \(back == 1 ? "item" : "items")"
        default:
            return
        }
        show()
    }

    /// An app dropped on Uninstall, or chosen from the shelf's menu.
    func share(_ shared: SharedFiles) async {
        guard let picked = shared.urls.lazy.compactMap(App.init(at:)).first else {
            notice = "Drop an app to uninstall it"
            show()
            return
        }
        // Sharing from the shelf doesn't let an add-on open its page, so the review waits on Cleaner's page.
        await review(picked)
    }

    // MARK: Uninstalling

    private func openApps() async {
        screen = .apps
        busy = "Looking for apps…"
        show()
        apps = await Task.detached { Self.installedApps() }.value
        busy = nil
        show()
    }

    /// Apps in /Applications and ~/Applications, and one folder down (such as a maker's folder), without macOS's own.
    nonisolated static func installedApps() -> [App] {
        let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [App] = []
        for root in roots {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] where !name.hasPrefix(".") {
                let url = root.appendingPathComponent(name)
                if let app = App(at: url) { found.append(app); continue }
                guard name != "Utilities" else { continue }
                for inner in (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] {
                    if let app = App(at: url.appendingPathComponent(inner)) { found.append(app) }
                }
            }
        }
        return found.filter { !$0.isProtected }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func review(_ picked: App) async {
        guard !picked.isProtected else {
            notice = "\(picked.name.prefix(24)) is part of macOS or Ledge"
            screen = .home
            show()
            return
        }
        app = picked
        screen = .review
        busy = "Looking for \(picked.name)’s files…"
        items = []
        show()
        let home = self.home
        let others = apps.isEmpty ? await Task.detached { Self.installedApps() }.value : apps
        let anotherCopy = others.contains { $0.bundleID == picked.bundleID && $0.url.standardizedFileURL != picked.url.standardizedFileURL }
        items = await Task.detached { Leftovers.find(for: picked, home: home, anotherCopy: anotherCopy) }.value
        busy = nil
        if anotherCopy { notice = "Another copy is on this Mac · files start unchecked" }
        show()
    }

    // MARK: Storage

    private func openStorage() async {
        screen = .storage
        busy = "Sizing caches, logs and developer data…"
        categories = []
        show()
        let home = self.home
        categories = await Task.detached { Storage.scan(home: home) }.value
        busy = nil
        if categories.isEmpty { notice = "Nothing to clean up" }
        show()
    }

    // MARK: Moving to the Trash

    private func trash() async {
        switch screen {
        case .review:
            guard let app else { return }
            // An open app can't be moved; ask it to quit and give it a moment.
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
            if !running.isEmpty {
                busy = "Quitting \(app.name)…"
                show()
                running.forEach { $0.terminate() }
                // ledgekit:allow unseen-polling — waits at most five seconds for the app the person asked to quit.
                for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) { try? await Task.sleep(for: .milliseconds(250)) }
                busy = nil
                if running.contains(where: { !$0.isTerminated }) {
                    notice = "\(app.name.prefix(24)) didn’t quit. Quit it, then retry"
                    show()
                    return
                }
            }
            let chosen = items.filter(\.checked)
            finish(Trash.move(chosen.map(\.url)), bytes: chosen.reduce(0) { $0 + ($1.size ?? 0) })
            self.app = nil
            items = []
        case .storage:
            let chosen = categories.filter(\.checked)
            guard !chosen.isEmpty else { notice = "Choose something to clean up"; show(); return }
            finish(Trash.move(chosen.flatMap(\.items)), bytes: chosen.reduce(0) { $0 + $1.size })
            categories = []
        default:
            return
        }
        screen = .home
        show()
    }

    private func finish(_ result: (moved: [Trash.Moved], failed: [URL]), bytes: Int64) {
        lastMoved = result.moved
        let size = Sizes.text(bytes)
        let count = result.moved.count
        notice = "Moved \(count) \(count == 1 ? "item" : "items") to the Trash · \(size)"
            + (result.failed.isEmpty ? "" : " · \(result.failed.count) stayed")
    }

    /// Scheduled cleaning: caches and logs untouched for three days, leaving the open apps'.
    private func cleanIfDue() async {
        guard automatic else { return }
        let interval: TimeInterval = every == "monthly" ? 30 * 86_400 : 7 * 86_400
        guard Date().timeIntervalSince(lastAutomatic ?? .distantPast) >= interval else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let home = self.home
        let stale = await Task.detached { Storage.stale(home: home, running: running) }.value
        let bytes = stale.reduce(0) { $0 + (Sizes.of($1) ?? 0) }
        let moved = Trash.move(stale).moved
        lastAutomatic = Date()
        try? await LedgeHost.set(lastAutomatic!.timeIntervalSince1970, forKey: "lastAutomatic")
        // ledgekit:allow logs-content — a count and a size, never names or paths.
        AddOnSession.log("Scheduled cleaning moved \(moved.count) items, \(Sizes.text(bytes)), to the Trash")
        show()
    }

    // MARK: Drawing

    private func show() {
        AddOnSession.show(notchPage: NotchPage(title: "Cleaner", symbol: "sparkles", size: .large, screen: page()))
        AddOnSession.show(shareTarget: ShareTarget(title: "Cleaner", symbol: "trash", destinations: [
            ShareDestination("uninstall", title: "Uninstall…", subtitle: "With the files it left", symbol: "trash")
        ]))
        AddOnSession.show(settingsPage())
    }

    private func page() -> PageScreen {
        if let busy, screen != .home {
            return PageScreen(screen == .apps ? "apps" : screen == .review ? "review" : "storage", depth: screen == .review ? 2 : 1,
                              title: "Cleaner", back: true, content: .empty(symbol: "magnifyingglass", title: busy, detail: nil))
        }
        switch screen {
        case .home:
            var actions: [PageAction] = []
            if !lastMoved.isEmpty { actions.append(PageAction("putback", symbol: "arrow.uturn.backward", label: "Put Back")) }
            return PageScreen("home", title: "Cleaner", caption: notice.map { String($0.prefix(60)) }, actions: actions, content: .list(id: "home", rows: [
                ListRow("uninstall", title: "Uninstall an app", subtitle: "Choose one, or drop an app here", symbol: "trash", acceptsFiles: true),
                ListRow("storage", title: "Clean up storage", subtitle: "App caches, logs and developer data", symbol: "internaldrive"),
            ]))
        case .apps:
            let shown = apps.prefix(Surface.maximumListRows)
            return PageScreen("apps", depth: 1, title: "Uninstall", caption: apps.count > shown.count ? "The first \(shown.count) apps · drop others on Uninstall" : notice.map { String($0.prefix(60)) },
                              back: true, content: shown.isEmpty ? .empty(symbol: "app.dashed", title: "No apps to uninstall", detail: nil)
                                : .list(id: "apps", rows: shown.map {
                                    ListRow($0.url.path, title: $0.name, subtitle: Self.place($0.url.deletingLastPathComponent()), symbol: "app")
                                }))
        case .review:
            let chosen = items.filter(\.checked)
            let caption = notice.map { String($0.prefix(60)) } ?? "\(chosen.count) of \(items.count) · \(Sizes.text(chosen.reduce(0) { $0 + ($1.size ?? 0) }))"
            return PageScreen("review", depth: 2, title: String((app?.name ?? "Uninstall").prefix(40)), caption: caption, back: true,
                              actions: [PageAction("trash", symbol: "trash", label: "Move to Trash", destructive: true)],
                              content: .list(id: "items", rows: items.prefix(Surface.maximumListRows).enumerated().map { index, item in
                                  ListRow(String(index), title: item.url.lastPathComponent, subtitle: Self.place(item.url.deletingLastPathComponent()),
                                          detail: Sizes.text(item.size), symbol: item.checked ? "checkmark.circle.fill" : "circle")
                              }))
        case .storage:
            let chosen = categories.filter(\.checked)
            return PageScreen("storage", depth: 1, title: "Clean up storage",
                              caption: notice.map { String($0.prefix(60)) } ?? "\(Sizes.text(chosen.reduce(0) { $0 + $1.size })) chosen", back: true,
                              actions: categories.isEmpty ? [] : [PageAction("trash", symbol: "trash", label: "Move to Trash", destructive: true)],
                              content: categories.isEmpty ? .empty(symbol: "checkmark.circle", title: "Nothing to clean up", detail: nil)
                                : .list(id: "categories", rows: categories.map {
                                    ListRow($0.id, title: $0.title, subtitle: "\($0.items.count) \($0.items.count == 1 ? "item" : "items")",
                                            detail: Sizes.text($0.size), symbol: $0.checked ? "checkmark.circle.fill" : "circle")
                                }))
        }
    }

    /// `~/Library/Caches` rather than the whole path.
    nonisolated static func place(_ url: URL) -> String {
        let path = url.path, home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func settingsPage() -> SettingsPage {
        let last = lastAutomatic.map { "Last cleaned " + $0.formatted(date: .abbreviated, time: .shortened) + "." } ?? ""
        return SettingsPage([
            SettingsSection("scheduled", title: "Scheduled cleaning",
                            footer: "Moves app caches and logs nobody used in three days to the Trash, leaving open apps’ alone. \(last)",
                            rows: [
                                .toggle("automatic", "Clean automatically", isOn: automatic),
                                .picker("every", "How often", options: [.init("weekly", "Weekly"), .init("monthly", "Monthly")], selected: every),
                            ]),
        ], keywords: ["cleaner", "uninstall", "caches", "storage", "space", "trash"])
    }
}

let addOn = Cleaner()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.deactivate = { await addOn.stop() }
handlers.onEvent = { event in await addOn.handle(event) }
handlers.onShare = { shared in await addOn.share(shared) }
exit(await AddOnSession.run(id: "cleaner", handlers: handlers))
