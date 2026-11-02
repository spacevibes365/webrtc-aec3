import CWebRTCAEC3

/// Removes the far-end echo from a microphone stream, using the signal that
/// was played out as the reference.
///
/// The canceller works on whole 10 ms frames. Callers hand it any number of
/// samples; the remainder that does not fill a frame is kept until the next
/// call, so a stream cut into arbitrary chunks gives the same result as one
/// long call.
public final class EchoCanceller {
    public enum Failure: Error, Equatable {
        case unsupportedSampleRate(Int)
        case lengthMismatch(microphone: Int, reference: Int)
        case processing(code: Int32)
    }

    public let sampleRate: Int
    /// Samples in one 10 ms frame.
    public let frameLength: Int

    private let handle: OpaquePointer
    // Samples received but not yet part of a whole frame. Kept per stream so
    // microphone and reference stay aligned.
    private var pendingMicrophone: [Float] = []
    private var pendingReference: [Float] = []

    /// 16000, 32000 or 48000 Hz, mono.
    public init(sampleRate: Int) throws {
        guard let created = webrtc_aec3_create(Int32(truncatingIfNeeded: sampleRate)) else {
            throw Failure.unsupportedSampleRate(sampleRate)
        }
        handle = created
        self.sampleRate = sampleRate
        frameLength = Int(webrtc_aec3_frame_length(created))
        pendingMicrophone.reserveCapacity(frameLength)
        pendingReference.reserveCapacity(frameLength)
    }

    deinit {
        webrtc_aec3_destroy(handle)
    }

    /// Any number of samples, the same count in both. Returns the cleaned
    /// microphone samples of every whole 10 ms frame now available; the
    /// remainder waits for the next call or `finish()`.
    public func process(microphone: [Float], reference: [Float]) throws -> [Float] {
        guard microphone.count == reference.count else {
            throw Failure.lengthMismatch(microphone: microphone.count, reference: reference.count)
        }
        pendingMicrophone.append(contentsOf: microphone)
        pendingReference.append(contentsOf: reference)

        let frames = pendingMicrophone.count / frameLength
        guard frames > 0 else { return [] }

        var output = [Float](repeating: 0, count: frames * frameLength)
        try runFrames(count: frames, into: &output)
        pendingMicrophone.removeFirst(frames * frameLength)
        pendingReference.removeFirst(frames * frameLength)
        return output
    }

    /// Pads the remainder with silence, processes it and returns exactly the
    /// remaining samples, so over a stream the total returned equals the total
    /// fed.
    public func finish() throws -> [Float] {
        let remaining = pendingMicrophone.count
        guard remaining > 0 else { return [] }
        let padding = frameLength - remaining
        pendingMicrophone.append(contentsOf: repeatElement(0, count: padding))
        pendingReference.append(contentsOf: repeatElement(0, count: padding))

        var output = [Float](repeating: 0, count: frameLength)
        try runFrames(count: 1, into: &output)
        pendingMicrophone.removeAll(keepingCapacity: true)
        pendingReference.removeAll(keepingCapacity: true)
        return Array(output.prefix(remaining))
    }

    private func runFrames(count: Int, into output: inout [Float]) throws {
        let length = frameLength
        try pendingMicrophone.withUnsafeBufferPointer { mic in
            try pendingReference.withUnsafeBufferPointer { ref in
                try output.withUnsafeMutableBufferPointer { out in
                    for frame in 0..<count {
                        let offset = frame * length
                        let code = webrtc_aec3_process(
                            handle,
                            ref.baseAddress! + offset,
                            mic.baseAddress! + offset,
                            out.baseAddress! + offset)
                        if code != 0 { throw Failure.processing(code: code) }
                    }
                }
            }
        }
    }
}
