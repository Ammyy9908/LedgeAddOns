import AppKit
import CoreGraphics
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import LedgeKit
import WideAwakeCore

// Wide Awake: keeps the Mac from sleeping. Core decides when; this program holds a power assertion, looks at the
// automatic triggers and sends what Core builds. macOS drops the assertion if this process ends, so a crash can't
// leave the Mac sleepless. Nothing leaves the Mac.

/// One IOPMAssertion, swapped when the mode changes and released when nothing needs it.
final class Assertion: @unchecked Sendable {
    private var id: IOPMAssertionID = 0
    private var held: Mode?

    /// False when macOS refused it.
    @discardableResult
    func hold(_ mode: Mode?) -> Bool {
        guard mode != held else { return true }
        if held != nil { IOPMAssertionRelease(id) }
        held = nil
        guard let mode else { return true }
        let type = mode == .display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        guard IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "Wide Awake is keeping the Mac awake" as CFString, &id) == kIOReturnSuccess else { return false }
        held = mode
        return true
    }
}

/// Reads what the automatic triggers ask about, only for the triggers that are on.
enum Probe {
    static let agents: Set<String> = ["claude", "codex", "aider", "gemini", "cursor-agent", "opencode", "goose", "amp", "copilot"]
    static let partial = ["download", "crdownload", "part", "partial"]

    static func conditions(for saved: Saved) -> Conditions {
        var c = Conditions()
        if saved.whilePluggedIn { c.pluggedIn = pluggedIn() }
        if saved.whileDisplay { c.externalDisplay = externalDisplay() }
        if saved.whileDownloading { c.downloading = downloading() }
        if saved.whilePrinting { c.printing = !run("/usr/bin/lpstat", ["-o"]).isEmpty }
        if saved.whileAgents {
            c.agentRunning = run("/bin/ps", ["-Axo", "comm="]).split(separator: "\n")
                .contains { agents.contains(String($0.split(separator: "/").last ?? $0).trimmingCharacters(in: .whitespaces)) }
        }
        if saved.whileApps {
            c.openApps = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() })
        }
        return c
    }

    private static func pluggedIn() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMACPowerKey
    }

    private static func externalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func downloading() -> Bool {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { partial.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    /// The command's output, or "" when it fails.
    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

actor WideAwake {
    private var model = WideAwakeModel()
    private var pageOpen = false
    private var ticker: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private let assertion = Assertion()

    func start() async {
        do {
            if let saved = try await LedgeHost.value(Saved.self, forKey: "wide-awake") { model = WideAwakeModel(saved: saved) }
        } catch { model.problem = "Settings unavailable" }
        AddOnSession.show(shortcuts: [AddOnShortcut("toggle", title: "Keep the Mac awake or let it sleep", key: "A")])
        AddOnSession.show(tools: WideAwakeModel.tools)
        AddOnSession.show(model.settingsPage())
        await update(since: model.saved)
    }

    func stop() {
        ticker?.cancel()
        watcher?.cancel()
        assertion.hold(nil)
    }

    func handle(_ event: SurfaceEvent) async {
        let before = model.saved
        model.handle(event, now: Date())
        await update(since: before)
    }

    func tool(_ call: ToolCall) async throws -> ToolResult {
        let before = model.saved
        let result = try model.tool(call, now: Date())
        await update(since: before)
        return result
    }

    func visibility(_ visible: SurfaceVisibility) async {
        let opened = visible.isVisible(Surface.notchPage) && !pageOpen
        pageOpen = visible.isVisible(Surface.notchPage)
        guard opened else { return schedule() }
        let before = model.saved
        model.opened(now: Date())
        await update(since: before)
    }

    private func refresh() async { await update(since: model.saved) }

    private func look() async {
        model.conditions = Probe.conditions(for: model.saved)
        await refresh()
    }

    /// Moves the clock on, holds or releases the assertion, then saves and sends whatever changed.
    private func update(since before: Saved) async {
        let now = Date()
        let ended = model.tick(now: now)
        if model.saved != before {
            AddOnSession.show(model.settingsPage())
            do { try await LedgeHost.set(model.saved, forKey: "wide-awake") } catch { model.problem = "Couldn't save" }
            // A trigger turned on is looked at now, rather than at the next check.
            if model.saved.watches != before.watches || model.saved.apps != before.apps { model.conditions = Probe.conditions(for: model.saved) }
        }
        if !assertion.hold(model.holding(at: now)) { model.problem = "macOS didn't allow it" }
        schedule()
        AddOnSession.show(widgets: [model.widget(now: now)])
        AddOnSession.show(notchPage: model.page(now: now))
        AddOnSession.show(activities: model.activities(now: now))
        AddOnSession.show(lockScreenRow: model.lockScreenRow(now: now))
        if ended {
            do { try await LedgeHost.notify(title: WideAwakeModel.notice.title, message: WideAwakeModel.notice.message, symbol: "moon.zzz.fill") }
            catch { AddOnSession.log("Notice unavailable", level: .info) }
        }
    }

    /// A one-second clock while a timer counts down, and a look at the triggers every 15 seconds while any is on.
    private func schedule() {
        // The open page shows when a timer would end, so it ticks too.
        let counting = model.saved.session?.until != nil || pageOpen
        if counting, ticker == nil {
            ticker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await self.refresh()
                }
            }
        } else if !counting {
            ticker?.cancel()
            ticker = nil
        }
        if model.saved.watches, watcher == nil {
            watcher = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    await self.look()
                }
            }
        } else if !model.saved.watches {
            watcher?.cancel()
            watcher = nil
            model.conditions = Conditions()
        }
    }
}

let wideAwake = WideAwake()
var handlers = AddOnHandlers()
handlers.activate = { await wideAwake.start() }
handlers.deactivate = { await wideAwake.stop() }
handlers.onEvent = { await wideAwake.handle($0) }
handlers.onTool = { try await wideAwake.tool($0) }
handlers.onVisibilityChange = { await wideAwake.visibility($0) }
exit(await AddOnSession.run(id: "wide-awake", handlers: handlers))
