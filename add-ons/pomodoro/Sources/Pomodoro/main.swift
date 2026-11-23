import AppKit
import AVFoundation
import Foundation
import LedgeKit
import PomodoroCore

// Pomodoro: a focus and break timer in the notch. Core builds every surface; this program keeps the clock, plays
// the end sound, the ambient sound and the reminders, and sends what Core builds. Nothing leaves the Mac.

/// Generated noise on the Mac's output while a session counts down.
final class Ambience: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var playing: Ambient?

    func play(_ kind: Ambient?, volume: Double) {
        engine?.mainMixerNode.outputVolume = Float(volume)
        guard kind != playing else { return }
        engine?.stop()
        engine = nil
        playing = kind
        guard let kind else { return }
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        var noise = NoiseGenerator(kind, sampleRate: format.sampleRate, seed: UInt64.random(in: 1...UInt64.max))
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
        engine.mainMixerNode.outputVolume = Float(volume)
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
    /// Settings' Play is sounding the ambient sound until then.
    private var previewUntil: Date?
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
        ambience.play(nil, volume: 0)
    }

    func handle(_ event: SurfaceEvent) async {
        if event.control == "preview-end-sound" { return playEndSound() }
        if event.control == "preview-ambient" { return await previewAmbient() }
        let before = model.saved
        model.handle(event, now: Date())
        await update(since: before)
    }

    /// A few seconds of the chosen ambient sound, then back to whatever should be playing.
    private func previewAmbient() async {
        let until = Date().addingTimeInterval(4)
        previewUntil = until
        await update(since: model.saved)
        try? await Task.sleep(for: .seconds(4))
        guard previewUntil == until else { return }
        previewUntil = nil
        await update(since: model.saved)
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
    private func update(since before: Saved) async {
        let now = Date()
        let (ended, reminders) = model.tick(now: now)
        if model.saved != before {
            AddOnSession.show(model.settingsPage())
            do { try await LedgeHost.set(model.saved, forKey: "pomodoro") } catch { model.problem = "Couldn't save" }
        }
        // Overtime and the stopwatch keep counting, so the clock runs while anything is unpaused.
        let running = model.saved.run.map { !$0.isPaused } ?? false
        let previewing = previewUntil.map { $0 > now } ?? false
        ambience.play(model.ambientPlaying(at: now) || previewing ? model.saved.ambient : nil, volume: model.saved.volume)
        if running, ticker == nil {
            ticker = Task {
                while !Task.isCancelled {
                    // Wake as the shown second changes, rather than drift on a fixed beat.
                    let elapsed = self.secondsElapsed()
                    try? await Task.sleep(for: .seconds(max(0.05, 1 - elapsed.truncatingRemainder(dividingBy: 1))))
                    await self.tick()
                }
            }
        } else if !running {
            ticker?.cancel()
            ticker = nil
        }
        AddOnSession.show(widgets: [model.widget(now: now)])
        AddOnSession.show(notchPage: model.page(now: now))
        AddOnSession.show(activities: model.activities(now: now))
        AddOnSession.show(lockScreenRow: model.lockScreenRow(now: now))
        if let ended { await announce(ended) }
        for reminder in reminders { await notify(reminder.title, reminder.message, symbol: reminder.symbol) }
    }

    private func secondsElapsed() -> TimeInterval { model.saved.run?.elapsed(at: Date()) ?? 0 }

    private func playEndSound() {
        if model.saved.endSound != "None" { NSSound(named: model.saved.endSound)?.play() }
    }

    private func announce(_ ended: Mode) async {
        playEndSound()
        let notice = PomodoroModel.notice(for: ended, minutes: model.minutes(ended))
        await notify(notice.title, notice.message, symbol: ended.symbol)
    }

    private func notify(_ title: String, _ message: String, symbol: String) async {
        do { try await LedgeHost.notify(title: title, message: message, symbol: symbol) }
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
