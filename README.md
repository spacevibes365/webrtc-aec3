# WebRTCAEC3

WebRTC's acoustic echo canceller (AEC3) as a Swift package. Give it what the
loudspeaker played (the far end) and what the microphone captured; it returns
the microphone with the far-end echo removed and the near-end voice left as it
was. Mono, 16, 32 or 48 kHz, no unsafe build flags, so it works as a remote
SwiftPM dependency.

```swift
.package(url: "<this repository>", from: "0.1.0")
// target dependency: .product(name: "WebRTCAEC3", package: "WebRTCAEC3")

let aec = try EchoCanceller(sampleRate: 16_000)
var cleaned = try aec.process(microphone: micSamples, reference: speakerSamples)
cleaned += try aec.finish()
```

`process` takes any number of samples (equal count in both arrays) and
returns the cleaned samples of every whole 10 ms frame available; the rest
waits for the next call. `finish()` pads the remainder with silence and
returns exactly the remaining samples, so over a stream the number of samples
returned equals the number fed. Chunking never changes the result.

## What it does and does not do

* It runs the same pipeline as `webrtc::AudioProcessing` with only the echo
  canceller on (full AEC3, `mobile_mode` off). High-pass filter, noise
  suppression and both gain controllers are off, so the near-end voice is not
  otherwise touched. The stream delay is never set: AEC3 estimates the delay
  itself (`set_stream_delay_ms` is optional in this version).
* **The output is late by a fixed 128 samples at 16 kHz (8 ms)**, two internal
  blocks of AEC3. The total length is unchanged; the first 128 output samples
  are the start-up of the pipeline. Shift the result if you align it sample by
  sample with other tracks.
* The reference must come from the same clock as the microphone (or be close
  to it): AEC3 follows small drifts, not a reference from an unrelated device.
* Convergence takes a few seconds of far-end speech. The first seconds of a
  recording are cleaned less.
* `EchoCanceller` is not thread-safe and not `Sendable`; use one per stream
  inside one task.

## Layout

| Path | What |
| --- | --- |
| `Sources/WebRTCAEC3` | Swift API |
| `Sources/CWebRTCAEC3/include/webrtc_aec3.h` | plain C interface (Swift imports it without C++ interop) |
| `Sources/CWebRTCAEC3/wrapper` | C++ over `webrtc::AudioProcessing` |
| `Sources/CWebRTCAEC3/webrtc` | vendored WebRTC audio processing (see below) |
| `Sources/CWebRTCAEC3/abseil` | vendored abseil subset |
| `patches/` | the only changes to upstream, see `patches/README.md` |
| `scripts/vendor.sh` | rebuilds `webrtc/` and `abseil/` from the two upstream trees |

## Upstream versions

* **webrtc-audio-processing** (freedesktop.org packaging of WebRTC's audio
  processing), tag `v2.1`, commit `846fe90a289f58b7c9303a635142aa2c7caa93e5`.
  BSD-3-Clause, with the WebRTC patent grant: `Sources/CWebRTCAEC3/webrtc/LICENSE`,
  `PATENTS`, `COPYING` and the licences of the bundled third-party parts
  (pffft, ooura FFT, rnnoise weights, isac VAD, spl_sqrt_floor) next to them.
* **abseil-cpp** LTS `20240722.0`, release tarball sha256
  `f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3`.
  Apache-2.0: `Sources/CWebRTCAEC3/abseil/LICENSE`.

Upstream files are byte-identical except for the patches in `patches/`.

## Reproducing the vendored tree

```sh
scripts/vendor.sh <webrtc-audio-processing-dir> <abseil-cpp-dir>
```

The lists of compiled files are `scripts/webrtc-sources.txt` (from upstream's
`meson.build` files, `scripts/gen-source-list.py`) and
`scripts/abseil-files.txt` (header closure plus the nine `.cc` files in
`scripts/abseil-sources.txt` that the link needs, `scripts/gen-abseil-list.py`).
Running it twice gives the same tree.

## Build notes

* swift-tools-version 6.0 (needed to build the package in Swift 6 language
  mode); macOS 13+.
* AVX2 is not compiled (it needs `-mavx2`, an unsafe flag); Intel Macs use the
  SSE2 paths. NEON is used on Apple silicon.
* Tests use synthetic signals only: `swift test`.
