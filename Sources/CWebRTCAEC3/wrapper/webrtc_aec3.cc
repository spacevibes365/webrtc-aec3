#include "webrtc_aec3.h"

#include <memory>
#include <new>
#include <vector>

#include "api/audio/audio_processing.h"
#include "api/scoped_refptr.h"

struct webrtc_aec3 {
  webrtc::scoped_refptr<webrtc::AudioProcessing> apm;
  webrtc::StreamConfig config;
  int frame_length = 0;
  // Scratch for the reference: ProcessReverseStream takes a destination too,
  // and the caller's reference must stay untouched.
  std::vector<float> reference_scratch;
};

namespace {
bool SupportedRate(int rate) {
  return rate == 16000 || rate == 32000 || rate == 48000;
}
}  // namespace

extern "C" {

webrtc_aec3 *webrtc_aec3_create(int sample_rate_hz) {
  if (!SupportedRate(sample_rate_hz)) return nullptr;

  // Only the echo canceller runs: the experiment this reproduces switched
  // everything else off so the near-end voice is left as it was.
  webrtc::AudioProcessing::Config config;
  config.echo_canceller.enabled = true;
  config.echo_canceller.mobile_mode = false;
  config.high_pass_filter.enabled = false;
  config.noise_suppression.enabled = false;
  config.gain_controller1.enabled = false;
  config.gain_controller2.enabled = false;
  config.pre_amplifier.enabled = false;
  config.capture_level_adjustment.enabled = false;

  webrtc::scoped_refptr<webrtc::AudioProcessing> apm =
      webrtc::AudioProcessingBuilder().SetConfig(config).Create();
  if (!apm) return nullptr;

  auto *aec = new (std::nothrow) webrtc_aec3();
  if (!aec) return nullptr;
  aec->apm = std::move(apm);
  aec->config = webrtc::StreamConfig(sample_rate_hz, 1);
  aec->frame_length = sample_rate_hz / 100;
  aec->reference_scratch.resize(static_cast<size_t>(aec->frame_length));
  return aec;
}

int webrtc_aec3_frame_length(const webrtc_aec3 *aec) {
  return aec ? aec->frame_length : 0;
}

int webrtc_aec3_process(webrtc_aec3 *aec, const float *reference,
                        const float *microphone, float *out) {
  if (!aec || !reference || !microphone || !out)
    return webrtc::AudioProcessing::kNullPointerError;

  // The far-end frame goes first so the canceller has seen what is about to
  // come back through the microphone. No stream delay is set: AEC3 estimates
  // the delay itself, and set_stream_delay_ms is optional in this version.
  const float *ref_in[1] = {reference};
  float *ref_out[1] = {aec->reference_scratch.data()};
  int err = aec->apm->ProcessReverseStream(ref_in, aec->config, aec->config,
                                           ref_out);
  if (err != webrtc::AudioProcessing::kNoError) return err;

  const float *mic_in[1] = {microphone};
  float *mic_out[1] = {out};
  return aec->apm->ProcessStream(mic_in, aec->config, aec->config, mic_out);
}

void webrtc_aec3_destroy(webrtc_aec3 *aec) { delete aec; }

}  // extern "C"
