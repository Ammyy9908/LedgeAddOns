import AudioControlCore
import CoreAudio
import Foundation
import LedgeKit

// Audio Control: a volume slider for each app playing sound, on a page in the notch and a widget; each app's own
// output; switching to preferred devices as they connect; and one switch that mutes every microphone.
//
// An app at 100% on the Mac's output plays as usual. One turned down, boosted or sent elsewhere gets an AppTap:
// macOS hands its sound to this add-on, which plays it on the chosen output at the level set. Nothing is recorded.

actor AudioControl {
    /// Rows the notch page has room for; the large widget has room for five.
    static let maximumRows = 7
    static let widgetRows = 5

    /// Each app's level, 0 to 2, by bundle id; apps not in it play at their own volume (1).
    private var levels: [String: Double] = [:]
    private var remember = true
    /// Apps with sound open but silent right now keep their row.
    private var showPaused = true
    private var systemSounds = true
    private var curve = Mixer.Curve.natural
    /// Sliders go to 200%; off, to 100%, and boosted apps play at their own volume.
    private var boost = true
    /// The output each app plays to, by bundle id, as a device UID; apps not in it follow the Mac's output.
    private var routes: [String: String] = [:]
    /// Output UIDs to switch to as they connect, best first.
    private var preferred: [String] = []
    /// Names of outputs seen, by UID, so a disconnected one still has its name in the pickers.
    private var known: [String: String] = [:]
    private var micsMuted = false
    /// Outputs and microphones as last seen; nil until the first look, so launching doesn't count as connecting.
    private var devices: [AudioDevice]?
    private var apps: [String: AudioApp] = [:]
    private var taps: [String: AppTap] = [:]
    private var icons: [String: Data] = [:]
    /// The rows the widget shows, so it's sent again only when they change: sending it while a slider moves would
    /// rebuild the slider under the pointer.
    private var shown: [String]?
    private var problem: String?
    private var ticker: Task<Void, Never>?

    func start() async {
        remember = (try? await LedgeHost.value(Bool.self, forKey: "remember")) ?? true
        showPaused = (try? await LedgeHost.value(Bool.self, forKey: "showPaused")) ?? true
        systemSounds = (try? await LedgeHost.value(Bool.self, forKey: "systemSounds")) ?? true
        curve = (try? await LedgeHost.value(String.self, forKey: "curve")).flatMap(Mixer.Curve.init) ?? .natural
        boost = (try? await LedgeHost.value(Bool.self, forKey: "boost")) ?? true
        if remember { levels = (try? await LedgeHost.value([String: Double].self, forKey: "levels")) ?? [:] }
        routes = (try? await LedgeHost.value([String: String].self, forKey: "routes")) ?? [:]
        preferred = (try? await LedgeHost.value([String].self, forKey: "preferred")) ?? []
        known = (try? await LedgeHost.value([String: String].self, forKey: "known")) ?? [:]
        micsMuted = (try? await LedgeHost.value(Bool.self, forKey: "micsMuted")) ?? false
        AddOnSession.show(shortcuts: [AddOnShortcut("mics", title: "Mute or unmute microphones", key: "M")])
        refresh()
        // shortcut: looks for apps starting and stopping sound every 2 seconds rather than listening to Core Audio's
        // notifications; a new app's slider can take that long to show.
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self.refresh()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        // Microphones aren't left muted with nothing in Ledge showing it; starting again mutes them again.
        if micsMuted { for device in devices ?? [] where device.input { Devices.setMuted(false, device.object) } }
        for tap in taps.values { tap.stop() }
        taps = [:]
    }

    // MARK: Events

    func handle(_ event: SurfaceEvent) async {
        switch (event.surface, event.control, event.action) {
        case (Surface.widget, let id, .changed(let value)), (Surface.notchPage, let id, .changed(let value)):
            levels[id] = Mixer.isFull(value) ? nil : min(max(value, 0), maximum)
            apply(id)
            if remember { try? await LedgeHost.set(levels, forKey: "levels") }
        case (Surface.settingsPage, "remember", .toggled(let on)):
            remember = on
            if on { try? await LedgeHost.set(levels, forKey: "levels") } else { try? await LedgeHost.removeValue(forKey: "levels") }
            AddOnSession.show(settingsPage())
        case (Surface.settingsPage, "showPaused", .toggled(let on)):
            showPaused = on
            try? await LedgeHost.set(on, forKey: "showPaused")
            changedSettings()
        case (Surface.settingsPage, "systemSounds", .toggled(let on)):
            systemSounds = on
            try? await LedgeHost.set(on, forKey: "systemSounds")
            changedSettings()
        case (Surface.settingsPage, "curve", .picked(let id)):
            curve = Mixer.Curve(rawValue: id) ?? .natural
            try? await LedgeHost.set(curve.rawValue, forKey: "curve")
            changedSettings()
        case (Surface.settingsPage, "boost", .toggled(let on)):
            boost = on
            try? await LedgeHost.set(on, forKey: "boost")
            changedSettings()
        case (Surface.settingsPage, let id, .picked(let uid)) where id.hasPrefix("route:"):
            routes[String(id.dropFirst("route:".count))] = uid.isEmpty ? nil : uid
            try? await LedgeHost.set(routes, forKey: "routes")
            changedSettings()
        case (Surface.settingsPage, let id, .picked(let uid)) where id.hasPrefix("preferred:"):
            guard let rank = Int(id.dropFirst("preferred:".count)) else { return }
            var list = preferred + Array(repeating: "", count: max(0, 3 - preferred.count))
            list[rank] = uid
            preferred = list.enumerated().filter { $0.element.isEmpty == false && !list[..<$0.offset].contains($0.element) }.map(\.element)
            try? await LedgeHost.set(preferred, forKey: "preferred")
            changedSettings()
        case (Surface.settingsPage, "mics", .toggled(let on)), (Surface.notchPage, "mics", .toggled(let on)):
            await muteMics(on)
        case (Surface.notchPage, "mics", .pressed), (Surface.shortcut, "mics", .pressed):
            await muteMics(!micsMuted)
            // Beside the notch for a moment, so a shortcut pressed with the notch closed still says what it did.
            AddOnSession.show(activities: [LiveActivity("mics", symbol: micsMuted ? "mic.slash.fill" : "mic.fill",
                                                        text: micsMuted ? "Microphones muted" : "Microphones on",
                                                        importance: .high, lasts: 2)])
        case (Surface.settingsPage, "reset", .pressed):
            levels = [:]
            try? await LedgeHost.removeValue(forKey: "levels")
            for id in Array(taps.keys) { apply(id) }
            shown = nil
            refresh()
        default:
            return
        }
    }

    /// The top of every slider: 200% with boost on, else 100%.
    private var maximum: Double { boost ? Mixer.maximum : 1 }

    /// A level as it plays now: a boost counts only while boost is on.
    private func level(_ id: String) -> Double { min(levels[id] ?? 1, maximum) }

    private func muteMics(_ on: Bool) async {
        micsMuted = on
        try? await LedgeHost.set(on, forKey: "micsMuted")
        for device in devices ?? [] where device.input { Devices.setMuted(on, device.object) }
        changedSettings()
    }

    private func changedSettings() {
        AddOnSession.show(settingsPage())
        shown = nil
        refresh()
    }

    // MARK: Taps

    private func refresh() {
        let now = Devices.all()
        let before = devices
        devices = now
        if before.map({ $0.map(\.uid) }) != now.map(\.uid) { deviceChanges(from: before, to: now) }
        apps = AudioApps.current(includingSystemSounds: systemSounds)
        for id in Set(taps.keys).union(levels.keys).union(routes.keys) { apply(id) }
        // Playing apps, then system sounds, then paused ones, so paused apps never crowd out the rows that matter.
        func rank(_ app: AudioApp) -> Int { app.playing ? 0 : app.id == AudioApps.systemSounds ? 1 : 2 }
        let rows = apps.values.filter { $0.playing || showPaused || taps[$0.id] != nil || $0.id == AudioApps.systemSounds }
            .sorted { (rank($0), $0.name.lowercased()) < (rank($1), $1.name.lowercased()) }
            .prefix(Self.maximumRows).map(\.id)
        let playing = rows.filter { apps[$0]?.playing == true }
        // The widget lists only playing apps, so an app starting or stopping redraws it too; the levels are in the
        // key so a change made on one surface (the notch, the iPhone) reaches the others.
        let key = rows + ["|"] + playing + ["|"] + rows.map { String(level($0)) }
        guard key != shown else { return }
        shown = key
        AddOnSession.show(settingsPage())
        let sliders = self.sliders(rows)
        let mics = PageAction("mics", symbol: micsMuted ? "mic.slash.fill" : "mic.fill",
                              label: micsMuted ? "Unmute microphones" : "Mute microphones")
        AddOnSession.show(notchPage: NotchPage(title: "Audio Control", symbol: "speaker.wave.2.fill", size: .large,
                                               screen: PageScreen("main", actions: [mics], content: page(sliders))))
        // Paused apps stay on the page, where there's room; the widget is for what's playing now.
        AddOnSession.show(widgets: [widget(self.sliders(Array(playing.prefix(Self.widgetRows))))])
    }

    /// Outputs and microphones came or went: learn new outputs' names, switch to a preferred one that connected,
    /// mute a microphone that connected while they're muted, and draw the pickers again.
    private func deviceChanges(from before: [AudioDevice]?, to now: [AudioDevice]) {
        for device in now where device.output { known[device.uid] = device.name }
        Task { try? await LedgeHost.set(known, forKey: "known") }
        if let before {
            let appeared = Set(now.map(\.uid)).subtracting(before.map(\.uid))
            let current = Devices.defaultOutput().flatMap { id in now.first { $0.object == id }?.uid }
            if let uid = Preferred.switchTo(ranking: preferred, connected: Set(now.filter(\.output).map(\.uid)),
                                            appeared: appeared, current: current),
               let device = now.first(where: { $0.uid == uid }) {
                Devices.setDefaultOutput(device.object)
                AddOnSession.log("Switched output to \(device.name)")
            }
        }
        if micsMuted { for device in now where device.input { Devices.setMuted(true, device.object) } }
        shown = nil
    }

    /// Where an app plays: its own output when that's connected, else the Mac's.
    private func output(for id: String) -> String? {
        if let uid = routes[id], devices?.contains(where: { $0.uid == uid && $0.output }) == true { return uid }
        return AudioApps.defaultOutput()
    }

    /// Starts, retunes or stops the app's tap to match its slider, its output, and the processes it plays from.
    private func apply(_ id: String) {
        let level = level(id)
        let output = output(for: id)
        let elsewhere = output != AudioApps.defaultOutput()
        guard !Mixer.isFull(level) || elsewhere, let app = apps[id], let output else {
            taps.removeValue(forKey: id)?.stop()
            return
        }
        if let tap = taps[id], tap.processes == app.processes, tap.output == output {
            tap.gain = Mixer.gain(level, curve: curve)
            return
        }
        taps.removeValue(forKey: id)?.stop()
        do {
            taps[id] = try AppTap(processes: app.processes, output: output, gain: Mixer.gain(level, curve: curve))
            if problem != nil { problem = nil; shown = nil }
        } catch let failure as AppTap.Failure {
            AddOnSession.log("No tap for \(id) at \(failure.step): \(failure.status)", level: .error)
            if problem == nil {
                // Without the system audio permission macOS refuses the tap.
                problem = "macOS didn't let Ledge change this app's volume. Allow Ledge in System Settings, Privacy & Security, Screen & System Audio Recording."
                shown = nil
            }
        } catch {}
    }

    // MARK: What Ledge draws

    /// A row per app that fills to its level, with its icon, name and percent.
    private func sliders(_ rows: [String]) -> [WidgetNode] {
        rows.compactMap { id in
            guard let app = apps[id] else { return nil }
            if icons[id] == nil { icons[id] = app.icon?.widgetPNG }
            // An app sent to its own output says where, like "Spotify → AirPods".
            let route = output(for: id) == AudioApps.defaultOutput() ? nil : routes[id].flatMap { known[$0] }
            let label = route.map { "\(app.name.prefix(24)) → \($0.prefix(24))" } ?? String(app.name.prefix(40))
            return .slider(id: id, value: level(id), maximum: boost ? Mixer.maximum : nil, label: label, image: icons[id])
        }
    }

    /// The page in the notch: "Audio" and how many apps play, then the rows.
    private func page(_ sliders: [WidgetNode]) -> PageNode {
        let header = PageNode.hstack(spacing: 6, children: [
            .symbol("speaker.wave.2.fill", size: 12), .text("Audio", style: .body), .spacer,
            .text("\(sliders.count)", style: .secondary),
        ])
        var children: [PageNode] = [header] + sliders.compactMap { node in
            guard case let .slider(id, value, maximum, label, image) = node else { return nil }
            return .slider(id: id, value: value, maximum: maximum, label: label, image: image)
        }
        if sliders.isEmpty { children.append(.text("No app is playing sound", style: .secondary)) }
        if let problem { children.append(.text(problem, style: .caption)) }
        return .vstack(spacing: 6, children: children)
    }

    private func widget(_ sliders: [WidgetNode]) -> Widget {
        var children = sliders
        if children.isEmpty { children = [.text("No app is playing sound", style: .secondary)] }
        if let problem { children.append(.text(problem, style: .caption)) }
        return Widget("mixer", title: "Audio Control", symbol: "speaker.wave.2", size: children.count > 3 ? .large : .medium,
                      content: .vstack(spacing: 6, children: children))
    }

    private func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("behavior", title: "Behavior", rows: [
                .toggle("remember", "Remember volumes", detail: "An app keeps its level the next time it plays", isOn: remember),
                .toggle("showPaused", "Show paused apps", detail: "Apps with sound open but silent right now keep their row", isOn: showPaused),
                .toggle("systemSounds", "Include system sounds", detail: "A row for macOS's alerts and interface sounds", isOn: systemSounds),
            ]),
            SettingsSection("volume", title: "Volume",
                            footer: "An app set above or below 100% plays through Ledge at that level; at 100% it plays as usual. Nothing is recorded or leaves this Mac.",
                            rows: [
                .picker("curve", "Volume curve", detail: "Natural sounds even across the slider; Linear moves the level evenly",
                        options: [.init("natural", "Natural"), .init("linear", "Linear")], selected: curve.rawValue),
                .toggle("boost", "Allow boost above 100%", detail: "Sliders go to 200%; loud peaks are held at full scale", isOn: boost),
                .button("reset", "Reset all volumes", destructive: true),
            ]),
            SettingsSection("outputs", title: "Output per app",
                            footer: "Send each app to its own speakers or headphones. An app whose output isn't connected plays on the Mac's.",
                            rows: outputRows()),
            SettingsSection("preferred", title: "Preferred devices",
                            footer: "When one of these connects, the Mac switches to the best one connected. Choosing an output yourself stays until another of them connects.",
                            rows: (0..<3).map { rank in
                .picker("preferred:\(rank)", ["First choice", "Second choice", "Third choice"][rank],
                        options: [.init("", "None")] + outputOptions(), selected: rank < preferred.count ? preferred[rank] : "")
            }),
            SettingsSection("microphones", title: "Microphones",
                            footer: "Mutes every microphone, including ones that connect while it's on. The microphone button on Audio Control's page in the notch and its shortcut (set it under Shortcuts) do the same. Turning Audio Control off unmutes them.",
                            rows: [.toggle("mics", "Mute all microphones", isOn: micsMuted)]),
        ], keywords: ["volume", "audio", "mixer", "sound", "app volume", "boost", "system sounds", "output", "speakers",
                      "headphones", "airpods", "microphone", "mute"])
    }

    /// Every output seen, connected ones first, as picker options keyed by UID.
    private func outputOptions() -> [SettingsRow.Option] {
        let connected = Set((devices ?? []).filter(\.output).map(\.uid))
        return known.sorted { (connected.contains($0.key) ? 0 : 1, $0.value) < (connected.contains($1.key) ? 0 : 1, $1.value) }
            .map { .init($0.key, connected.contains($0.key) ? $0.value : "\($0.value) (not connected)") }
    }

    /// A picker for each app with a row, and for any app sent elsewhere that isn't playing now.
    private func outputRows() -> [SettingsRow] {
        let ids = (shown ?? []) + routes.keys.filter { !(shown ?? []).contains($0) }.sorted()
        guard !ids.isEmpty else { return [.note("none", "Apps show here when they play sound")] }
        return ids.prefix(12).map { id in
            .picker("route:\(id)", apps[id]?.name ?? id, options: [.init("", "Mac's output")] + outputOptions(),
                    selected: routes[id] ?? "")
        }
    }
}

let addOn = AudioControl()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.deactivate = { await addOn.stop() }
handlers.onEvent = { event in await addOn.handle(event) }
exit(await AddOnSession.run(id: "audio-control", handlers: handlers))
