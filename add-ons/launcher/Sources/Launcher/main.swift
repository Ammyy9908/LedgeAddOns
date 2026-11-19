import Foundation
import LedgeKit
import LauncherCore

// Launcher: answers Ledge's `launcher` request as the person types in Ledge's launcher panel. Ledge owns the panel,
// its shortcut and what happens on Return; this add-on finds the rows: answers, apps, System Settings pages, files
// and a web search.

/// Apps and settings pages, found once and again every few minutes, so typing never waits on the disk.
actor Index {
    private var apps: [Entry] = []
    private var settings: [Entry] = []
    private var found = Date.distantPast

    func entries() -> (apps: [Entry], settings: [Entry]) {
        if Date().timeIntervalSince(found) > 300 {
            apps = Self.findApps()
            settings = Self.findSettings()
            found = Date()
        }
        return (apps, settings)
    }

    private static func findApps() -> [Entry] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       "\(home)/Applications"]
        var seen = Set<String>()
        var entries: [Entry] = []
        for folder in folders {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                entries.append(app("\(folder)/\(name)"))
            }
        }
        entries.append(app("/System/Library/CoreServices/Finder.app"))
        // The same app in two folders shows once.
        return entries.filter { seen.insert($0.result.title).inserted }
    }

    private static func app(_ path: String) -> Entry {
        let title = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        return Entry(LauncherResult(id: "app:\(path)", title: title, kind: "Application", iconPath: path,
                                    open: URL(fileURLWithPath: path).absoluteString))
    }

    /// Every page of System Settings this macOS has, named as System Settings names them.
    private static func findSettings() -> [Entry] {
        let folder = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        // Pages whose bundles carry no readable name.
        let names = ["com.apple.BluetoothSettings": "Bluetooth", "com.apple.Battery-Settings.extension": "Battery",
                     "com.apple.systempreferences.AppleIDSettings": "Apple Account", "com.apple.settings.Storage": "Storage",
                     "com.apple.Touch-ID-Settings.extension": "Touch ID & Password", "com.apple.Wallpaper-Settings.extension": "Wallpaper",
                     "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension": "VPN", "com.apple.HeadphoneSettings": "Headphones"]
        let bundles = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return bundles.compactMap { url -> Entry? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  let attributes = bundle.infoDictionary?["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
                  (attributes["SettingsExtensionAttributes"] as? [String: Any])?["allowsXAppleSystemPreferencesURLScheme"] as? Bool != false,
                  let title = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? names[id],
                  title != "FollowUps" else { return nil }
            let symbol = ((bundle.infoDictionary?["CFBundleIcons"] as? [String: Any])?["ISGraphicIconConfiguration"] as? [String: Any])?["ISSymbolName"] as? String
            let plain = title.filter { $0.isLetter || $0.isNumber || $0 == " " }
            return Entry(LauncherResult(id: "settings:\(id)", title: title, subtitle: "System Settings", kind: "Settings",
                                        symbol: symbol.flatMap { $0.hasPrefix("IS") ? nil : $0 } ?? "gearshape",
                                        open: "x-apple.systempreferences:\(id)"),
                         keywords: [plain, "settings " + plain.lowercased()])
        }
    }
}

/// Paths in the home folder that Spotlight's index finds with `arguments`, each with when it was last opened. A broad
/// search can list thousands; a second is enough for the first ones.
func spotlight(_ arguments: [String]) async -> [(path: String, used: Date?)] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    process.arguments = ["-onlyin", home, "-attr", "kMDItemLastUsedDate"] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: stop)
    let output = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
    stop.cancel()
    let dates = DateFormatter()
    dates.locale = Locale(identifier: "en_US_POSIX")
    dates.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line in
        let parts = line.components(separatedBy: "   kMDItemLastUsedDate = ")
        let path = parts[0]
        guard !path.contains("/Library/"), !path.contains("/."), !path.contains(".app/"), !path.contains("/node_modules/") else { return nil }
        return (path, parts.count > 1 ? dates.date(from: parts[1]) : nil)
    }
}

func fileRow(_ path: String, kind: String? = nil) -> LauncherResult {
    var isFolder: ObjCBool = false
    FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
    let parent = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
    return LauncherResult(id: "file:\(path)", title: (path as NSString).lastPathComponent, subtitle: parent,
                          kind: kind ?? (isFolder.boolValue ? "Folder" : "File"), iconPath: path,
                          open: URL(fileURLWithPath: path).absoluteString, copy: path)
}

/// Files in the home folder whose names hold `query`, closest names first: 5 among everything else, or 30 when the
/// person picked Files, then with when each was last opened on the right.
func files(matching query: String, limit: Int = 5, showingWhen: Bool = false) async -> [LauncherResult] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= (showingWhen ? 2 : 3) else { return [] }
    let lowered = query.lowercased()
    let found = await spotlight(["-name", query]).sorted { a, b in
        let (x, y) = ((a.path as NSString).lastPathComponent.lowercased(), (b.path as NSString).lastPathComponent.lowercased())
        if x.hasPrefix(lowered) != y.hasPrefix(lowered) { return x.hasPrefix(lowered) }
        if showingWhen, a.used != b.used { return (a.used ?? .distantPast) > (b.used ?? .distantPast) }
        return a.path.count < b.path.count
    }
    return found.prefix(limit).map { file in
        fileRow(file.path, kind: showingWhen ? file.used.map { Launcher.ago($0) } : nil)
    }
}

/// The files opened in the last two weeks, newest first, for Files before the person types.
func recentFiles() async -> [LauncherResult] {
    await spotlight(["kMDItemLastUsedDate >= $time.today(-14) && kMDItemContentType != public.folder"])
        .filter { $0.used != nil }
        .sorted { $0.used! > $1.used! }
        .prefix(30).map { fileRow($0.path, kind: Launcher.ago($0.used!)) }
}

/// Ask AI: which service answers, with the person's own key. The choice and models are plain settings; the keys
/// are in the Keychain.
struct AISettings: Codable, Sendable {
    var assistant = "off"
    var models: [String: String] = [:]
    var customURL = ""
}

actor AI {
    private var settings = AISettings()
    private static let settingsKey = "ai"

    func start() async {
        settings = (try? await LedgeHost.value(AISettings.self, forKey: Self.settingsKey)) ?? AISettings()
        show()
    }

    private var assistant: Assistant? {
        if settings.assistant == "custom" { return settings.customURL.isEmpty ? nil : .compatible(baseURL: settings.customURL) }
        return Assistant.builtIn.first { $0.id == settings.assistant }
    }

    /// Who answers, when one is chosen and has what it needs.
    var ready: Assistant? {
        guard let assistant, !assistant.needsKey || Keychain.has(assistant.id) else { return nil }
        return assistant
    }

    func ask(_ question: String) async throws -> LauncherAnswer {
        guard let assistant = ready else { throw AddOnError("Choose an AI and add your key in the Launcher's settings.") }
        do {
            var request = try assistant.request(question, key: Keychain.key(assistant.id) ?? "", model: settings.models[assistant.id] ?? "")
            request.timeoutInterval = 60
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw assistant.failure(status: status) }
            return LauncherAnswer(text: String(try assistant.answer(from: data).prefix(20_000)), from: assistant.name)
        } catch let error as AssistantError {
            throw AddOnError(error.message)
        } catch {
            // Not the error itself: it can carry the request.
            throw AddOnError("Couldn't reach \(assistant.name). Check your connection and try again.")
        }
    }

    func handle(_ event: SurfaceEvent) async {
        guard event.surface == Surface.settingsPage else { return }
        switch (event.control, event.action) {
        case ("assistant", .picked(let id)): settings.assistant = id
        case ("url", .edited(let text)): settings.customURL = text.trimmingCharacters(in: .whitespaces)
        case ("model", .edited(let text)):
            guard let id = assistant?.id else { return }
            settings.models[id] = text.trimmingCharacters(in: .whitespaces)
        case ("key", .edited(let text)):
            let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = assistant?.id, !key.isEmpty else { return }
            if !Keychain.save(key, for: id) { AddOnSession.log("Couldn't save the key in the Keychain.", level: .error) }
        case ("forget", .pressed):
            guard let id = assistant?.id else { return }
            Keychain.remove(id)
        default: return
        }
        do { try await LedgeHost.set(settings, forKey: Self.settingsKey) } catch {
            AddOnSession.log("Couldn't save the settings.", level: .error)
        }
        show()
    }

    /// The settings page. The key field is always sent back empty, so a saved key is never shown or sent to Ledge.
    private func show() {
        var rows: [SettingsRow] = [
            .picker("assistant", "Answer with", options: [.init("off", "Off")] + Assistant.builtIn.map { .init($0.id, $0.name) }
                    + [.init("custom", "OpenAI-compatible server")], selected: settings.assistant),
        ]
        if settings.assistant == "custom" {
            rows.append(.textField("url", "Server address", detail: "Up to /v1, like https://openrouter.ai/api/v1 or http://localhost:11434/v1",
                                   text: settings.customURL, placeholder: "https://…/v1"))
        }
        if let assistant {
            let saved = Keychain.has(assistant.id)
            rows.append(.textField("key", "API key", text: "",
                                   placeholder: saved ? "Saved in Keychain · paste to replace" : (assistant.needsKey ? "Paste your key" : "Optional")))
            rows.append(.textField("model", "Model", text: settings.models[assistant.id] ?? "",
                                   placeholder: assistant.defaultModel.isEmpty ? "Model name" : assistant.defaultModel))
            if saved {
                rows.append(.button("forget", "Remove Key", destructive: true,
                                    confirm: .init("Remove the \(assistant.name) key?", message: "It's deleted from this Mac's Keychain.", confirmTitle: "Remove")))
            }
        }
        AddOnSession.show(SettingsPage([
            SettingsSection("ai", title: "Ask AI",
                            footer: "Ask questions from the launcher with your own key. The key stays in this Mac's Keychain and is sent only to the service you choose, and a question is sent only when you choose its Ask row.",
                            rows: rows),
        ], keywords: ["ai", "claude", "chatgpt", "openai", "gemini", "api key", "ask"]))
    }
}

let index = Index()
let ai = AI()
var handlers = AddOnHandlers()
handlers.activate = { await ai.start() }
handlers.onEvent = { event in await ai.handle(event) }
handlers.on("launcher") { (request: LauncherQuery) async throws -> [LauncherResult] in
    let (apps, settings) = await index.entries()
    switch request.scope {
    case "apps": return Launcher.search(request.query, in: apps)
    case "settings": return Launcher.search(request.query, in: settings)
    case "files":
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? await recentFiles() : await files(matching: query, limit: 30, showingWhen: true)
    default: break
    }
    async let found = files(matching: request.query)
    let known = Launcher.search(request.query, apps: apps, settings: settings)
    let asking = await ai.ready.flatMap { Launcher.askRow(request.query, assistant: $0.name) }
    return known + (await found).filter { file in !known.contains { $0.open == file.open } }
        + [asking, Launcher.webSearch(request.query)].compactMap { $0 }
}
handlers.on("launcher.ask") { (request: LauncherQuery) async throws -> LauncherAnswer in
    try await ai.ask(request.query)
}
exit(await AddOnSession.run(id: "launcher", handlers: handlers))
