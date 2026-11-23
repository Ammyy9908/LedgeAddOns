import Foundation

/// Brown, pink or white noise, one sample at a time, from white noise: what plays when this Mac doesn't have the
/// Background Sounds file asked for. Brown is white noise integrated with a slight leak so it never drifts off; pink is
/// Paul Kellet's economy filter. Clamped to -1...1.
public struct NoiseGenerator: Sendable {
    public enum Kind: Sendable, CaseIterable { case brown, pink, white }
    public var kind: Kind
    private var brown: Float = 0
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0
    private var seed: UInt64

    public init(_ kind: Kind, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.kind = kind
        self.seed = seed
    }

    public mutating func next() -> Float { max(-1, min(1, sample())) }

    private mutating func sample() -> Float {
        let white = whiteSample()
        switch kind {
        case .white: return white * 0.4
        case .brown:
            brown = (brown + 0.02 * white) / 1.02
            return brown * 3.5
        case .pink:
            b0 = 0.99765 * b0 + white * 0.0990460
            b1 = 0.96300 * b1 + white * 0.2965164
            b2 = 0.57000 * b2 + white * 1.0526913
            return (b0 + b1 + b2 + white * 0.1848) * 0.2
        }
    }

    /// xorshift: fast and allocation-free, fine for noise.
    private mutating func whiteSample() -> Float {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Float(seed >> 40) / Float(1 << 23) - 1
    }
}
