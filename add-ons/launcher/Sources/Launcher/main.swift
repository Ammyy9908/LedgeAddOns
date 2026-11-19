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

/// Files in the home folder whose names hold `query`, from Spotlight's index, closest names first.
func files(matching query: String) async -> [LauncherResult] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 3 else { return [] }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    process.arguments = ["-onlyin", home, "-name", query]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    // A broad name can list thousands; a second is enough for the first ones.
    let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: stop)
    let output = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
    stop.cancel()
    let lowered = query.lowercased()
    let paths = String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        .filter { !$0.contains("/Library/") && !$0.contains("/.") && !$0.contains(".app/") && !$0.contains("/node_modules/") }
        .sorted { a, b in
            let (x, y) = ((a as NSString).lastPathComponent.lowercased(), (b as NSString).lastPathComponent.lowercased())
            if x.hasPrefix(lowered) != y.hasPrefix(lowered) { return x.hasPrefix(lowered) }
            return a.count < b.count
        }
    return paths.prefix(5).map { path in
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
        let parent = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        return LauncherResult(id: "file:\(path)", title: (path as NSString).lastPathComponent, subtitle: parent,
                              kind: isFolder.boolValue ? "Folder" : "File", iconPath: path,
                              open: URL(fileURLWithPath: path).absoluteString, copy: path)
    }
}

let index = Index()
var handlers = AddOnHandlers()
handlers.on("launcher") { (request: LauncherQuery) async throws -> [LauncherResult] in
    let (apps, settings) = await index.entries()
    async let found = files(matching: request.query)
    let known = Launcher.search(request.query, apps: apps, settings: settings)
    return known + (await found).filter { file in !known.contains { $0.open == file.open } }
        + [Launcher.webSearch(request.query)].compactMap { $0 }
}
exit(await AddOnSession.run(id: "launcher", handlers: handlers))
