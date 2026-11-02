import Foundation

/// Deterministic generator (SplitMix64) so every run sees the same signals.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Signals {
    static let rate = 16_000

    /// Zero-mean unit-variance-ish white noise.
    static func whiteNoise(count: Int, seed: UInt64) -> [Float] {
        var rng = SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            // Sum of uniforms is close enough to Gaussian for a test signal.
            let sum = (0..<4).reduce(Float(0)) { acc, _ in acc + Float.random(in: -1...1, using: &rng) }
            return sum * 0.5
        }
    }

    /// Speech-like: noise coloured by two resonances, shaped by a syllable-rate
    /// envelope that is gated off for pauses. `syllableHz` and `seed` make
    /// the far-end talker differ from the near-end one.
    static func speechLike(seconds: Double, seed: UInt64, syllableHz: Double, formants: (Double, Double), level: Float) -> [Float] {
        let count = Int(seconds * Double(rate))
        let noise = whiteNoise(count: count, seed: seed)
        var out = [Float](repeating: 0, count: count)
        let r1 = resonator(centre: formants.0, bandwidth: 120)
        let r2 = resonator(centre: formants.1, bandwidth: 200)
        var y1 = (Float(0), Float(0)), y2 = (Float(0), Float(0))
        var rng = SeededGenerator(seed: seed ^ 0xABCD)
        // Words of 0.4 to 1.2 s, separated by pauses of 0.2 to 0.8 s.
        var gate = [Float](repeating: 0, count: count)
        var i = 0
        var talking = true
        while i < count {
            let length = Int(Double.random(in: talking ? 0.4...1.2 : 0.2...0.8, using: &rng) * Double(rate))
            if talking { for j in i..<min(count, i + length) { gate[j] = 1 } }
            i += length
            talking.toggle()
        }
        for n in 0..<count {
            let t = Double(n) / Double(rate)
            let envelope = Float(0.5 + 0.5 * sin(2 * .pi * syllableHz * t))
            let a = r1.b0 * noise[n] - r1.a1 * y1.0 - r1.a2 * y1.1
            y1 = (a, y1.0)
            let b = r2.b0 * noise[n] - r2.a1 * y2.0 - r2.a2 * y2.1
            y2 = (b, y2.0)
            out[n] = (a + 0.7 * b) * envelope * gate[n] * level
        }
        return out
    }

    private static func resonator(centre: Double, bandwidth: Double) -> (b0: Float, a1: Float, a2: Float) {
        let r = exp(-.pi * bandwidth / Double(rate))
        let theta = 2 * .pi * centre / Double(rate)
        return (Float(1 - r), Float(-2 * r * cos(theta)), Float(r * r))
    }

    /// What a microphone hears of the loudspeaker: gain 0.5 after 24 ms plus a
    /// short decaying tail (a small room), and a -60 dB noise floor.
    static func echo(of reference: [Float], seed: UInt64) -> [Float] {
        let delay = 24 * rate / 1000
        var taps = [Float](repeating: 0, count: 240)
        taps[0] = 1
        var rng = SeededGenerator(seed: seed)
        for k in 1..<taps.count {
            taps[k] = Float.random(in: -1...1, using: &rng) * 0.35 * exp(-Float(k) / 60)
        }
        var out = [Float](repeating: 0, count: reference.count)
        for n in 0..<reference.count {
            var acc: Float = 0
            for k in 0..<taps.count where n - delay - k >= 0 { acc += taps[k] * reference[n - delay - k] }
            out[n] = 0.5 * acc
        }
        let floor = whiteNoise(count: reference.count, seed: seed ^ 0x5151)
        for n in 0..<out.count { out[n] += floor[n] * 0.001 }
        return out
    }

    static func rms(_ x: ArraySlice<Float>) -> Double {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    static func db(_ ratio: Double) -> Double { 20 * log10(max(ratio, 1e-12)) }
}
