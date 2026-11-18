import Foundation

/// An app the person may uninstall.
public struct App: Sendable, Equatable {
    public let url: URL
    public let name: String
    public let bundleID: String

    public init(url: URL, name: String, bundleID: String) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
    }

    /// Reads an app bundle; nil for anything that isn't one.
    public init?(at url: URL) {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
        self.init(url: url, name: name, bundleID: id)
    }

    /// macOS's own apps and Ledge are never offered, nor anything in /System.
    public var isProtected: Bool {
        let id = bundleID.lowercased()
        return id.hasPrefix("com.apple.") || id.hasPrefix("app.ledge.") || url.path.hasPrefix("/System/")
    }
}

/// Something that would go to the Trash.
public struct Item: Sendable, Equatable {
    public let url: URL
    /// Bytes on disk; nil where looking would open another app's private data.
    public var size: Int64?
    /// Starts checked: named after the app's identifier. Matched only by name, it starts unchecked.
    public var checked: Bool

    public init(url: URL, size: Int64?, checked: Bool) {
        self.url = url
        self.size = size
        self.checked = checked
    }
}

public enum Leftovers {
    /// Folders in the person's Library where apps leave files, named after the app.
    static let places = ["Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
                         "Saved Application State", "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Cookies", "Application Scripts"]
    /// Other apps' sandboxes: macOS asks before anyone looks inside, so they're found by name and never opened.
    static let unopened: Set<String> = ["Containers", "Group Containers"]

    /// The app and what it left in `home`/Library. With another copy of the app on the Mac, which still uses those
    /// files, nothing starts checked.
    public static func find(for app: App, home: URL, anotherCopy: Bool = false) -> [Item] {
        var items = [Item(url: app.url, size: Sizes.of(app.url), checked: true)]
        let library = home.appendingPathComponent("Library", isDirectory: true)
        for place in places {
            let folder = library.appendingPathComponent(place, isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names.sorted() {
                guard let match = match(name, app: app, place: place) else { continue }
                let url = folder.appendingPathComponent(name)
                items.append(Item(url: url, size: unopened.contains(place) ? nil : Sizes.of(url), checked: match == .identifier && !anotherCopy))
            }
        }
        return items
    }

    public enum Match { case identifier, name }

    /// `com.maker.app`, `com.maker.app.plist`, `com.maker.app.helper.plist` match by identifier; a folder named like
    /// the app matches by name only. Group containers are shared with the maker's other apps, so they're name-like.
    public static func match(_ file: String, app: App, place: String) -> Match? {
        let id = app.bundleID.lowercased()
        let lower = file.lowercased()
        var stem = lower
        for suffix in [".plist", ".savedstate", ".binarycookies"] where stem.hasSuffix(suffix) { stem.removeLast(suffix.count) }
        if place == "Group Containers" {
            return stem.hasSuffix("." + id) || stem == "group." + id ? .name : nil
        }
        if stem == id || stem.hasPrefix(id + ".") { return .identifier }
        let name = app.name.lowercased()
        // Short names ("Go", "Mail") are too likely to be someone else's.
        if name.count >= 4, stem == name || stem == name.replacingOccurrences(of: " ", with: "") { return .name }
        return nil
    }
}

/// Space the Mac can get back: things apps and developer tools rebuild on their own.
public struct Category: Sendable, Equatable {
    public let id: String
    public let title: String
    /// What goes to the Trash: each folder's contents, not the folder.
    public var items: [URL]
    public var size: Int64
    public var checked: Bool
}

public enum Storage {
    static let appleCaches = ["com.apple.", "cloudkit", "geoservices", "familycircle", "app.ledge."]

    /// The folders each category clears out, under `home`.
    public static func folders(home: URL) -> [(id: String, title: String, folders: [URL])] {
        let library = home.appendingPathComponent("Library")
        let developer = library.appendingPathComponent("Developer")
        return [
            ("caches", "App caches", [library.appendingPathComponent("Caches")]),
            ("logs", "Logs", [library.appendingPathComponent("Logs")]),
            ("xcode", "Xcode build data", [developer.appendingPathComponent("Xcode/DerivedData")]),
            ("device-support", "Device support files", ["iOS", "watchOS", "tvOS", "visionOS"].map {
                developer.appendingPathComponent("Xcode/\($0) DeviceSupport")
            }),
            ("developer", "Developer caches", [developer.appendingPathComponent("CoreSimulator/Caches"),
                                                home.appendingPathComponent(".npm/_cacache"),
                                                home.appendingPathComponent(".gradle/caches"),
                                                home.appendingPathComponent(".cache")]),
        ]
    }

    /// What's in a folder that may go: never Apple's own caches or Ledge's.
    public static func contents(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().filter { name in
            let lower = name.lowercased()
            return !name.hasPrefix(".") && !appleCaches.contains { lower.hasPrefix($0) }
        }.map { folder.appendingPathComponent($0) }
    }

    public static func scan(home: URL) -> [Category] {
        folders(home: home).map { entry in
            let items = entry.folders.flatMap(contents(of:))
            return Category(id: entry.id, title: entry.title, items: items, size: items.reduce(0) { $0 + (Sizes.of($1) ?? 0) },
                            checked: ["caches", "logs", "xcode"].contains(entry.id))
        }.filter { !$0.items.isEmpty }
    }

    /// For scheduled cleaning: app caches and logs nobody touched in `days`, leaving out the open apps' (by id).
    public static func stale(home: URL, days: Double = 3, now: Date = Date(), running: Set<String>) -> [URL] {
        let cutoff = now.addingTimeInterval(-days * 86_400)
        let library = home.appendingPathComponent("Library")
        let open = running.map { $0.lowercased() }
        return [library.appendingPathComponent("Caches"), library.appendingPathComponent("Logs")].flatMap(contents(of:)).filter { url in
            let name = url.lastPathComponent.lowercased()
            guard !open.contains(where: { name == $0 || name.hasPrefix($0 + ".") }) else { return false }
            return Sizes.newest(in: url).map { $0 < cutoff } ?? false
        }
    }
}

public enum Sizes {
    /// Bytes a file or folder takes on disk.
    public static func of(_ url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let child = walker?.nextObject() as? URL {
            total += Int64((try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// When anything in it last changed.
    public static func newest(in url: URL) -> Date? {
        var newest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: [],
                                                    errorHandler: { _, _ in true })
        while let child = walker?.nextObject() as? URL {
            if let date = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, date > newest ?? .distantPast {
                newest = date
            }
        }
        return newest
    }

    public static func text(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
    }
}

/// Moves things to the Trash and remembers where each came from, so Put Back can return them.
public enum Trash {
    public struct Moved: Sendable, Equatable {
        public let original: URL
        public let inTrash: URL
    }

    public static func move(_ urls: [URL]) -> (moved: [Moved], failed: [URL]) {
        var moved: [Moved] = []
        var failed: [URL] = []
        for url in urls {
            var result: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                if let result { moved.append(Moved(original: url, inTrash: result as URL)) }
            } catch {
                failed.append(url)
            }
        }
        return (moved, failed)
    }

    /// Returns what's still in the Trash to where it was. Anything since put in its place stays.
    public static func putBack(_ moved: [Moved]) -> Int {
        moved.filter { item in
            guard !FileManager.default.fileExists(atPath: item.original.path) else { return false }
            return (try? FileManager.default.moveItem(at: item.inTrash, to: item.original)) != nil
        }.count
    }
}
