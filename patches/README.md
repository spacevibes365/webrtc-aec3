# Patches to the vendored sources

Applied in file-name order by `scripts/vendor.sh`, with `patch -p1`, inside
`Sources/CWebRTCAEC3`. Everything else in `webrtc/` and `abseil/` is
byte-identical to upstream.

* `0001-arm64-neon-from-compiler-macros.patch`: upstream's meson build passes
  `-DWEBRTC_ARCH_ARM64 -DWEBRTC_HAS_NEON` on the command line for arm64.
  SwiftPM cannot choose compiler flags per architecture and `unsafeFlags` are
  refused in remote packages, so `rtc_base/system/arch.h` derives both from
  the compiler's `__aarch64__`. `signal_processing_library.h` includes
  `arch.h` first, because several files that test these macros reach it only
  through that header (a file seeing a different value than its neighbours
  would be an ODR hazard: `aecm_core.h` has NEON-dependent members).
* `0002-guard-architecture-specific-files.patch`: SwiftPM compiles every
  source file in the target for every architecture. The three SSE2 files and
  the seven NEON files are wrapped in `#if` on the compiler's architecture
  macro so they compile to nothing on the other architecture.

Not compiled at all: the AVX2 files (they need `-mavx2`; `WEBRTC_ENABLE_AVX2`
stays undefined, so the SSE2 paths are used on Intel), MIPS, 32-bit ARM
assembly, Windows/Android/Linux-only files and every test.
