import AgentsCore
import Foundation

/// Follows Codex's session logs as they grow. Each poll looks at today's and yesterday's folders under
/// `~/.codex/sessions`, takes the logs written in the last half hour, and returns the whole records added since the
/// last poll. A log seen for the first time is read from its start, so its session is rebuilt from scratch.
final class CodexWatcher {
    struct Batch {
        /// Sessions read from the start this time, which the board should forget first.
        var fresh: Set<String> = []
        var records: [(session: String, record: [String: Any])] = []
    }

    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    private let tail = LogTail()
    private static let recent: TimeInterval = 30 * 60

    func poll(now: Date = Date()) -> Batch {
        var batch = Batch()
        for folder in [now, now.addingTimeInterval(-86_400)].map(folder) {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            for file in files where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("rollout-") {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let modified = values?.contentModificationDate, now.timeIntervalSince(modified) < Self.recent else { continue }
                read(file, size: UInt64(values?.fileSize ?? 0), into: &batch)
            }
        }
        return batch
    }

    private func folder(_ day: Date) -> URL {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return root.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
    }

    /// The plan's usage as the newest log of the past week last reported it, read from its last 256 KB, for when
    /// Codex hasn't run since Ledge started.
    func latestUsage(now: Date = Date()) -> AgentUsage? {
        let files = (0..<7).flatMap { day in
            (try? FileManager.default.contentsOfDirectory(at: folder(now.addingTimeInterval(-86_400 * Double(day))),
                                                          includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        }.filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        func modified(_ file: URL) -> Date { (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        guard let newest = files.max(by: { modified($0) < modified($1) }), let handle = try? FileHandle(forReadingFrom: newest) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = record["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let usage = AgentUsage.codex(payload) else { continue }
            return usage
        }
        return nil
    }

    private func read(_ file: URL, size: UInt64, into batch: inout Batch) {
        let session = "codex:" + file.deletingPathExtension().lastPathComponent.dropFirst("rollout-".count)
        let lines = tail.read(file, size: size)
        if lines.fresh { batch.fresh.insert(session) }
        batch.records += lines.records.map { (session, $0) }
    }
}

/// Follows log files of whole JSON lines as they grow: the records each gained since the last look. A file seen for
/// the first time is read from its start, unless it's over 16 MB.
final class LogTail {
    private var offsets: [String: UInt64] = [:]
    private var partial: [String: Data] = [:]
    /// shortcut: a log over 16 MB is followed from its end, so a very long session shows only what it does next.
    private static let replayLimit: UInt64 = 16 * 1_048_576

    func read(_ file: URL, size: UInt64) -> (fresh: Bool, records: [[String: Any]]) {
        var fresh = false
        var offset = offsets[file.path] ?? {
            fresh = true
            return size > Self.replayLimit ? size : 0
        }()
        if size < offset { offset = 0; partial[file.path] = nil }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: file) else {
            offsets[file.path] = offset
            return (fresh, [])
        }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = (partial[file.path] ?? Data()) + ((try? handle.readToEnd()) ?? Data())
        offsets[file.path] = offset + UInt64(data.count - (partial[file.path]?.count ?? 0))
        // Only whole lines: the last one may still be being written.
        guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { partial[file.path] = data; return (fresh, []) }
        partial[file.path] = data[(end + 1)...].isEmpty ? nil : Data(data[(end + 1)...])
        let records = data[..<end].split(separator: UInt8(ascii: "\n")).compactMap {
            try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
        }
        return (fresh, records)
    }
}

/// Follows Cursor's agent transcripts written in the last half hour, under `~/.cursor/projects`.
final class CursorWatcher {
    struct Batch {
        var fresh: Set<String> = []
        var records: [(session: String, folder: String, date: Date, record: [String: Any])] = []
    }

    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/projects")
    private let tail = LogTail()

    func poll(now: Date = Date()) -> Batch {
        var batch = Batch()
        let manager = FileManager.default
        for project in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let transcripts = project.appendingPathComponent("agent-transcripts")
            for folder in (try? manager.contentsOfDirectory(at: transcripts, includingPropertiesForKeys: nil)) ?? [] {
                let file = folder.appendingPathComponent(folder.lastPathComponent + ".jsonl")
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let modified = values.contentModificationDate, now.timeIntervalSince(modified) < 30 * 60 else { continue }
                let session = "cursor:" + folder.lastPathComponent
                let lines = tail.read(file, size: UInt64(values.fileSize ?? 0))
                if lines.fresh { batch.fresh.insert(session) }
                let name = SessionBoard.cursorFolder(project.lastPathComponent)
                batch.records += lines.records.map { (session, name, modified, $0) }
            }
        }
        return batch
    }
}
