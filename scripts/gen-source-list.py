#!/usr/bin/env python3
"""Derive scripts/webrtc-sources.txt from upstream's meson.build files.

Run by hand when the upstream version changes; vendor.sh only reads the
committed list. Usage: gen-source-list.py <webrtc-audio-processing-dir>
"""
import os, re, sys

root = os.path.join(sys.argv[1], "webrtc")
meson_dirs = {
    "rtc_base": "rtc_base", "api": "api", "system_wrappers": "system_wrappers",
    "common_audio": "common_audio", "third_party/pffft": "third_party/pffft",
    "third_party/rnnoise": "third_party/rnnoise",
    "modules/audio_coding": "modules/audio_coding",
    "modules/third_party/fft": "modules/third_party/fft",
    "modules/audio_processing": "modules/audio_processing",
}
skip = re.compile(r"(_mips|_avx2|_arm\.S|_armv7\.S|warn_current_thread_is_deadlocked)")
out = []
for d in meson_dirs:
    text = open(os.path.join(root, d, "meson.build")).read()
    for m in re.finditer(r"'([^']+\.(?:cc|c|S))'", text):
        f = m.group(1)
        if skip.search(f) or f.endswith(".S"):
            continue
        path = os.path.join(d, f)
        assert os.path.exists(os.path.join(root, path)), path
        out.append(path)
print("\n".join(sorted(set(out))))
