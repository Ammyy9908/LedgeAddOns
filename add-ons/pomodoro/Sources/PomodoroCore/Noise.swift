import Foundation

/// Ambient sound, one sample at a time, built from white noise so nothing has to be recorded or shipped. Brown is
/// white noise integrated with a slight leak so it never drifts off; pink is Paul Kellet's economy filter. The scenes
/// shape those: the ocean swells brown noise in slow waves, a stream flutters pink noise, rain adds drops over a hiss,
/// and a fireplace adds crackles over a low rumble. Clamped to -1...1.
public struct NoiseGenerator: Sendable {
    public var kind: Ambient
    private let sampleRate: Float
    private var brown: Float = 0
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0
    /// Seconds played, for the waves and the flutter.
    private var time: Float = 0
    /// The drop or crackle sounding now, fading out.
    private var burst: Float = 0
    private var seed: UInt64

    public init(_ kind: Ambient, sampleRate: Double = 48_000, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.kind = kind
        self.sampleRate = Float(sampleRate)
        self.seed = seed
    }

    public mutating func next() -> Float { max(-1, min(1, sample())) }

    private mutating func sample() -> Float {
        let white = whiteSample()
        brown = (brown + 0.02 * white) / 1.02
        b0 = 0.99765 * b0 + white * 0.0990460
        b1 = 0.96300 * b1 + white * 0.2965164
        b2 = 0.57000 * b2 + white * 1.0526913
        let pink = (b0 + b1 + b2 + white * 0.1848) * 0.2
        time += 1 / sampleRate
        switch kind {
        case .white: return white * 0.4
        case .brown: return brown * 3.5
        case .pink: return pink
        case .ocean:
            // A wave about every nine seconds, never quite silent between them.
            let swell = 0.25 + 0.75 * (0.5 - 0.5 * cos(2 * .pi * time / 9))
            return brown * 3.5 * swell
        case .stream:
            let flutter = 0.8 + 0.2 * sin(2 * .pi * time * 0.7) * sin(2 * .pi * time * 0.13)
            return (pink * 0.8 + white * 0.04) * flutter
        case .rain:
            // About forty drops a second, each a short fading tick of noise.
            if chance(40) { burst = 0.3 + 0.5 * abs(whiteSample()) }
            burst *= 0.994
            return pink * 0.55 + white * 0.08 + white * burst
        case .fireplace:
            // A few crackles a second over the fire's rumble.
            if chance(6) { burst = 0.4 + 0.5 * abs(whiteSample()) }
            burst *= 0.985
            return brown * 2.5 + white * burst
        }
    }

    /// True on average `perSecond` times a second.
    private mutating func chance(_ perSecond: Float) -> Bool { (whiteSample() + 1) / 2 < perSecond / sampleRate }

    /// xorshift: fast and allocation-free, fine for noise.
    private mutating func whiteSample() -> Float {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Float(seed >> 40) / Float(1 << 23) - 1
    }
}
