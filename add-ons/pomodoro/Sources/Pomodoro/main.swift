import AppKit
import AVFoundation
import Foundation
import LedgeKit
import PomodoroCore

// Pomodoro: a focus and break timer in the notch. Core builds every surface; this program keeps the clock, plays
// the chime and the ambient noise, and sends what Core builds. Nothing leaves the Mac.

/// Brown or pink noise on the Mac's output while a timer runs.
final class Ambience: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var playing = Ambient.off

    func play(_ kind: Ambient) {
        guard kind != playing else { return }
        engine?.stop()
        engine = nil
        playing = kind
        guard kind != .off else { return }
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        var noise = NoiseGenerator(kind, seed: UInt64.random(in: 1...UInt64.max))
        let source = AVAudioSourceNode { _, _, frames, buffers -> OSStatus in
            for frame in 0..<Int(frames) {
                let sample = noise.next()
                for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1))
        engine.mainMixerNode.outputVolume = 0.35
        do {
            try engine.start()
            self.engine = engine
        } catch {
            AddOnSession.log("Ambient sound couldn't start", level: .error)
        }
    }
}

actor Pomodoro {
    private var model = PomodoroModel()
    private var pageOpen = false
    private var ticker: Task<Void, Never>?
    private var redraw: Task<Void, Never>?
    private let ambience = Ambience()

    func start() async {
        do {
            if let saved = try await LedgeHost.value(Saved.self, forKey: "pomodoro") { model = PomodoroModel(saved: saved) }
        } catch { model.problem = "Settings unavailable" }
        AddOnSession.show(shortcuts: [AddOnShortcut("toggle", title: "Start or pause the timer", key: "P")])
        AddOnSession.show(model.settingsPage())
        await update(since: model.saved)
    }

    func stop() {
        ticker?.cancel()
        ambience.play(.off)
    }

    func handle(_ event: SurfaceEvent) async {
        let before = model.saved
        model.handle(event, now: Date())
        // Ledge rebuilds the page each time it's sent, which would drop the length slider mid-drag; redraw once it rests.
        let dragging = event.control == "length"
        await update(since: before, page: !dragging)
        guard dragging else { return }
        redraw?.cancel()
        redraw = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { AddOnSession.show(notchPage: self.model.page(now: Date())) }
        }
    }

    func visibility(_ visible: SurfaceVisibility) async {
        let opened = visible.isVisible(Surface.notchPage) && !pageOpen
        pageOpen = visible.isVisible(Surface.notchPage)
        guard opened else { return }
        let before = model.saved
        model.opened(now: Date())
        await update(since: before)
    }

    private func tick() async { await update(since: model.saved) }

    /// Moves the clock on, then saves, sounds and sends whatever changed.
    private func update(since before: Saved, page: Bool = true) async {
        let now = Date()
        let ended = model.tick(now: now)
        if model.saved != before {
            AddOnSession.show(model.settingsPage())
            do { try await LedgeHost.set(model.saved, forKey: "pomodoro") } catch { model.problem = "Couldn't save" }
        }
        let running = model.saved.run.map { !$0.isPaused } ?? false
        ambience.play(running ? model.saved.ambient : .off)
        if running, ticker == nil {
            ticker = Task {
                while !Task.isCancelled {
                    // Wake as the shown second changes, rather than drift on a fixed beat.
                    let left = self.secondsLeft()
                    try? await Task.sleep(for: .seconds(max(0.05, left - (left.rounded(.up) - 1))))
                    await self.tick()
                }
            }
        } else if !running {
            ticker?.cancel()
            ticker = nil
        }
        AddOnSession.show(widgets: [model.widget(now: now)])
        if page { AddOnSession.show(notchPage: model.page(now: now)) }
        AddOnSession.show(activities: model.activities(now: now))
        AddOnSession.show(lockScreenRow: model.lockScreenRow(now: now))
        if let ended { await announce(ended) }
    }

    private func secondsLeft() -> TimeInterval { model.saved.run?.remaining(at: Date()) ?? 1 }

    private func announce(_ ended: Mode) async {
        if model.saved.chime { NSSound(named: "Glass")?.play() }
        guard model.saved.notice else { return }
        let next = ended.next
        let message = model.saved.autoContinue
            ? "\(next.name) started: \(model.minutes(next)) min."
            : "Start \(next == .rest ? "a break" : "focusing") from the notch when you're ready."
        do { try await LedgeHost.notify(title: ended == .focus ? "Focus done" : "Break over", message: message, symbol: next.symbol) }
        catch { AddOnSession.log("Notice unavailable", level: .info) }
    }
}

let pomodoro = Pomodoro()
var handlers = AddOnHandlers()
handlers.activate = { await pomodoro.start() }
handlers.deactivate = { await pomodoro.stop() }
handlers.onEvent = { await pomodoro.handle($0) }
handlers.onVisibilityChange = { await pomodoro.visibility($0) }
exit(await AddOnSession.run(id: "pomodoro", handlers: handlers))
