import AudioControlCore
import CoreAudio
import Foundation

/// One app's sound, taken from it with a Core Audio process tap and played on the output at `gain`. While the tap
/// runs macOS keeps the app's own sound off the speakers; stopping it gives the app its sound back.
final class AppTap {
    let processes: [AudioObjectID]
    let output: String
    /// Read on the audio thread once per buffer; a torn Float isn't possible on arm64 or x86_64.
    var gain: Float
    private var playing: Float
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?

    struct Failure: Error { let step: String; let status: OSStatus }

    init(processes: [AudioObjectID], output: String, gain: Float) throws {
        self.processes = processes
        self.output = output
        self.gain = gain
        playing = gain
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "Ledge Audio Control"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != 0 else { throw Failure(step: "tap", status: status) }
        do {
            let dictionary: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Ledge Audio Control",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: output,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                   kAudioSubTapDriftCompensationKey: true]],
            ]
            status = AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &aggregate)
            guard status == noErr, aggregate != 0 else { throw Failure(step: "device", status: status) }
            status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { [unowned self] _, input, _, output, _ in
                self.render(input, output)
            }
            guard status == noErr, proc != nil else { throw Failure(step: "proc", status: status) }
            status = AudioDeviceStart(aggregate, proc)
            guard status == noErr else { throw Failure(step: "start", status: status) }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregate != 0, let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        proc = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        aggregate = 0
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        tap = 0
    }

    /// The audio thread: the tap's stereo in, the output device's buffers out.
    private func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        let target = gain
        defer { playing = target }
        guard let source = ins.first, let samples = source.mData, source.mNumberChannels > 0 else { return }
        let inChannels = Int(source.mNumberChannels)
        let inFrames = Int(source.mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
        // shortcut: only the device's first output stream gets the sound, which is every speaker on most Macs and
        // headphones; an interface with several streams plays it on the first.
        guard let destination = outs.first, let out = destination.mData, destination.mNumberChannels > 0 else { return }
        let outChannels = Int(destination.mNumberChannels)
        Mixer.copy(samples.assumingMemoryBound(to: Float.self), channels: inChannels, frames: inFrames,
                   into: out.assumingMemoryBound(to: Float.self), channels: outChannels,
                   frames: Int(destination.mDataByteSize) / (MemoryLayout<Float>.size * outChannels),
                   from: playing, to: target)
    }
}
