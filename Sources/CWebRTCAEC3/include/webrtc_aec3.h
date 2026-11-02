// Plain C interface to the WebRTC AEC3 echo canceller (the echo-cancelling
// path of webrtc::AudioProcessing), so Swift can import it without C++ interop.
#ifndef WEBRTC_AEC3_H
#define WEBRTC_AEC3_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct webrtc_aec3 webrtc_aec3;

/// Creates a mono echo canceller for 16000, 32000 or 48000 Hz audio.
/// Returns NULL for any other rate or if the processor cannot be created.
webrtc_aec3 *webrtc_aec3_create(int sample_rate_hz);

/// Samples per channel in one 10 ms frame (rate / 100); 0 for a NULL handle.
int webrtc_aec3_frame_length(const webrtc_aec3 *aec);

/// Processes one 10 ms frame. `reference` is what the loudspeaker played (the
/// far end), `microphone` what the microphone captured. Both hold
/// webrtc_aec3_frame_length() float samples in [-1, 1]; `out` receives the
/// same number of samples: the microphone with the echo of `reference`
/// removed. `out` may alias `microphone`. Returns 0, or the
/// webrtc::AudioProcessing error code.
int webrtc_aec3_process(webrtc_aec3 *aec, const float *reference,
                        const float *microphone, float *out);

/// Frees the canceller. NULL is allowed.
void webrtc_aec3_destroy(webrtc_aec3 *aec);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // WEBRTC_AEC3_H
