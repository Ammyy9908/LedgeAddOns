/// The parts of per-app volume that don't touch Core Audio, so they can be tested.
public enum Mixer {
    /// The loudest level: 200%, twice the app's own volume on the slider.
    public static let maximum = 2.0

    /// Whether a level is the app's own volume, which needs no tap.
    public static func isFull(_ level: Double) -> Bool { abs(level - 1) < 0.005 }

    /// How the slider maps to loudness.
    public enum Curve: String, Sendable {
        /// Squared, so half the slider sounds about half as loud.
        case natural
        /// The slider is the gain itself.
        case linear
    }

    /// The bundle id macOS's alert and interface sounds play from.
    public static let systemSoundsProcess = "systemsoundserverd"

    /// Level (0 to 2, 1 being the app's own volume) to gain.
    public static func gain(_ level: Double, curve: Curve = .natural) -> Float {
        let clamped = min(max(level, 0), maximum)
        return Float(curve == .natural ? clamped * clamped : clamped)
    }

    /// The app a sound process plays for: itself, or the running app whose bundle id it extends, like
    /// `com.google.Chrome.helper` for `com.google.Chrome`. Nil when no app owns it.
    public static func owner(of bundleID: String, among apps: [String]) -> String? {
        apps.filter { bundleID == $0 || bundleID.hasPrefix($0 + ".") }.max { $0.count < $1.count }
    }

    /// Copies interleaved samples from `input` into `output` at a gain moving from `from` to `to` across the buffer,
    /// so a change of level doesn't click. An output channel with no input channel of its own repeats one, so stereo
    /// fills every speaker; frames the input doesn't have are silence. A boost is held to full scale, so it gets
    /// louder without wrapping into noise.
    public static func copy(_ input: UnsafePointer<Float>, channels inChannels: Int, frames inFrames: Int,
                            into output: UnsafeMutablePointer<Float>, channels outChannels: Int, frames outFrames: Int,
                            from: Float, to: Float) {
        guard inChannels > 0, outChannels > 0, outFrames > 0 else { return }
        let step = (to - from) / Float(outFrames)
        for frame in 0..<outFrames {
            let gain = from + step * Float(frame + 1)
            for channel in 0..<outChannels {
                output[frame * outChannels + channel] = frame < inFrames
                    ? min(max(input[frame * inChannels + channel % inChannels] * gain, -1), 1)
                    : 0
            }
        }
    }
}

/// Which output to switch to when devices come and go.
public enum Preferred {
    /// When a device on the person's list connects, the best one that's connected, unless the Mac already plays to
    /// it. Nil otherwise, so a device chosen by hand isn't fought over while nothing connects.
    public static func switchTo(ranking: [String], connected: Set<String>, appeared: Set<String>, current: String?) -> String? {
        guard ranking.contains(where: appeared.contains),
              let best = ranking.first(where: connected.contains), best != current else { return nil }
        return best
    }
}
