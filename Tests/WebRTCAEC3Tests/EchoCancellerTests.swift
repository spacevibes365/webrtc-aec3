import XCTest
@testable import WebRTCAEC3

final class EchoCancellerTests: XCTestCase {
    private let rate = Signals.rate
    private let seconds = 12.0
    private var count: Int { Int(seconds * Double(rate)) }
    /// The canceller needs time to find the delay and converge; levels are
    /// measured only after this.
    private var warmUp: Int { 4 * rate }

    private func reference() -> [Float] {
        Signals.speechLike(seconds: seconds, seed: 1, syllableHz: 4, formants: (700, 1800), level: 0.6)
    }

    private func nearEnd() -> [Float] {
        Signals.speechLike(seconds: seconds, seed: 2, syllableHz: 3, formants: (450, 2300), level: 0.12)
    }

    private func run(microphone: [Float], reference: [Float]) throws -> [Float] {
        let canceller = try EchoCanceller(sampleRate: rate)
        var out = try canceller.process(microphone: microphone, reference: reference)
        out += try canceller.finish()
        return out
    }

    private func report(_ name: String, _ value: Double, _ threshold: String) {
        print("MEASURED \(name) = \(String(format: "%.2f", value)) (threshold \(threshold))")
    }

    /// 1. Far-end echo only: after convergence the output is far below the
    /// microphone (echo return loss enhancement).
    func testEchoOnlyIsRemoved() throws {
        let ref = reference()
        let mic = Signals.echo(of: ref, seed: 3)
        let out = try run(microphone: mic, reference: ref)
        XCTAssertEqual(out.count, mic.count)
        let erle = Signals.db(Signals.rms(mic[warmUp...]) / Signals.rms(out[warmUp...]))
        report("echo-only ERLE dB", erle, ">= \(Self.erleThreshold)")
        XCTAssertGreaterThanOrEqual(erle, Self.erleThreshold)
    }

    /// 2. Near-end only, reference silent: the talker must pass unchanged.
    func testNearEndOnlyIsUntouched() throws {
        let near = nearEnd()
        let silent = [Float](repeating: 0, count: near.count)
        let out = try run(microphone: near, reference: silent)
        let change = Signals.db(Signals.rms(out[warmUp...]) / Signals.rms(near[warmUp...]))
        report("near-end-only level change dB", change, "|x| <= \(Self.nearEndThreshold)")
        XCTAssertLessThanOrEqual(abs(change), Self.nearEndThreshold)
    }

    /// 3. Both talk, and the far end is louder than the near-end talker, as on
    /// laptop speakers. The output must be much closer to the clean near-end
    /// signal than the raw microphone is, and must not have lost its level.
    /// The output is compared with the near-end signal shifted by the
    /// canceller's fixed latency (see `testOutputIsDelayedByTwoBlocks`).
    func testDoubleTalkKeepsNearEnd() throws {
        let ref = reference()
        let near = nearEnd()
        let echo = Signals.echo(of: ref, seed: 3)
        let mic = zip(near, echo).map { $0 + $1 }
        let out = try run(microphone: mic, reference: ref)
        let lag = Self.latency16k

        var micError = 0.0, outError = 0.0
        for n in warmUp..<(near.count - lag) {
            let m = Double(mic[n] - near[n])
            let o = Double(out[n + lag] - near[n])
            micError += m * m
            outError += o * o
        }
        let improvement = 10 * log10(micError / outError)
        let level = Signals.db(Signals.rms(out[(warmUp + lag)...]) / Signals.rms(near[warmUp...]))
        report("double-talk error improvement dB", improvement, ">= \(Self.doubleTalkImprovement)")
        report("double-talk output level vs near-end dB", level, "|x| <= \(Self.doubleTalkLevelLoss)")
        XCTAssertGreaterThanOrEqual(improvement, Self.doubleTalkImprovement)
        XCTAssertLessThanOrEqual(abs(level), Self.doubleTalkLevelLoss)
    }

    /// The canceller delays the microphone by a fixed two blocks of its
    /// internal processing; callers aligning the result with other tracks need
    /// to know it. An impulse shows it exactly.
    func testOutputIsDelayedByTwoBlocks() throws {
        var impulse = [Float](repeating: 0, count: rate)
        impulse[8000] = 0.5
        let out = try run(microphone: impulse, reference: [Float](repeating: 0, count: rate))
        let peak = out.enumerated().max { abs($0.element) < abs($1.element) }!.offset
        report("impulse latency (samples)", Double(peak - 8000), "== \(Self.latency16k)")
        XCTAssertEqual(peak - 8000, Self.latency16k)
    }

    /// 4. Any chunking gives the same samples as one call, and nothing is
    /// lost or invented.
    func testChunkingDoesNotChangeOutput() throws {
        let ref = Array(reference().prefix(5 * rate))
        let mic = Signals.echo(of: ref, seed: 3)
        let whole = try run(microphone: mic, reference: ref)

        let canceller = try EchoCanceller(sampleRate: rate)
        var rng = SeededGenerator(seed: 99)
        var out: [Float] = []
        var position = 0
        while position < mic.count {
            let size = min(Int.random(in: 1...2000, using: &rng), mic.count - position)
            out += try canceller.process(microphone: Array(mic[position..<position + size]),
                                         reference: Array(ref[position..<position + size]))
            position += size
        }
        out += try canceller.finish()
        XCTAssertEqual(out.count, mic.count)
        XCTAssertEqual(whole.count, mic.count)
        XCTAssertEqual(out, whole)
    }

    func testFinishWithoutRemainderReturnsNothing() throws {
        let canceller = try EchoCanceller(sampleRate: rate)
        let frame = [Float](repeating: 0, count: canceller.frameLength)
        _ = try canceller.process(microphone: frame, reference: frame)
        XCTAssertEqual(try canceller.finish(), [])
    }

    /// 5. Errors.
    func testUnsupportedRateThrows() {
        XCTAssertThrowsError(try EchoCanceller(sampleRate: 44_100)) {
            XCTAssertEqual($0 as? EchoCanceller.Failure, .unsupportedSampleRate(44_100))
        }
    }

    func testLengthMismatchThrows() throws {
        let canceller = try EchoCanceller(sampleRate: rate)
        XCTAssertThrowsError(try canceller.process(microphone: [0, 0, 0], reference: [0])) {
            XCTAssertEqual($0 as? EchoCanceller.Failure, .lengthMismatch(microphone: 3, reference: 1))
        }
    }

    func testSupportedRatesHaveTenMillisecondFrames() throws {
        for rate in [16_000, 32_000, 48_000] {
            XCTAssertEqual(try EchoCanceller(sampleRate: rate).frameLength, rate / 100)
        }
    }

    // Thresholds, set after measuring (see the report in the README).
    static let erleThreshold = 30.0
    static let nearEndThreshold = 1.0
    static let doubleTalkImprovement = 8.0
    static let doubleTalkLevelLoss = 3.0
    static let latency16k = 128
}
