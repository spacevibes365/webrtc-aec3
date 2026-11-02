#!/usr/bin/env bash
# Recreates Sources/CWebRTCAEC3/{webrtc,abseil} from the two upstream trees.
#   vendor.sh <webrtc-audio-processing-dir> <abseil-cpp-dir>
# Inputs are only read. Output is deterministic: a second run gives an
# identical tree. Needs bash, patch, rsync-free coreutils (cp, find, sort).
set -euo pipefail
export LC_ALL=C

wap=${1:?usage: vendor.sh <webrtc-audio-processing-dir> <abseil-cpp-dir>}
abseil=${2:?usage: vendor.sh <webrtc-audio-processing-dir> <abseil-cpp-dir>}
here=$(cd "$(dirname "$0")/.." && pwd)
dest="$here/Sources/CWebRTCAEC3"

rm -rf "$dest/webrtc" "$dest/abseil"
mkdir -p "$dest/webrtc" "$dest/abseil"

# --- WebRTC: the .c/.cc files meson compiles for macOS (scripts/webrtc-sources.txt)
# plus every header and .inc of the tree (headers are inert until included).
while IFS= read -r f; do
  mkdir -p "$dest/webrtc/$(dirname "$f")"
  cp "$wap/webrtc/$f" "$dest/webrtc/$f"
done < "$here/scripts/webrtc-sources.txt"

(cd "$wap/webrtc" && find . \( -name '*.h' -o -name '*.inc' -o -name LICENSE -o -name COPYING -o -name PATENTS \) -type f | sort) |
while IFS= read -r f; do
  mkdir -p "$dest/webrtc/$(dirname "$f")"
  cp "$wap/webrtc/$f" "$dest/webrtc/$f"
done
# Keep the freedesktop packaging licence notices next to the code.
cp "$wap/COPYING" "$dest/webrtc/COPYING"

# --- abseil: only the files in scripts/abseil-files.txt (headers of the used
# modules plus the .cc files the link needs).
while IFS= read -r f; do
  mkdir -p "$dest/abseil/$(dirname "$f")"
  cp "$abseil/$f" "$dest/abseil/$f"
done < "$here/scripts/abseil-files.txt"
cp "$abseil/LICENSE" "$dest/abseil/LICENSE"

# --- patches (see patches/README.md), applied to the vendored copy
for p in "$here"/patches/*.patch; do
  [ -e "$p" ] || continue
  (cd "$dest" && patch -p1 --no-backup-if-mismatch -s < "$p")
done
echo "vendored: $(find "$dest/webrtc" -type f | wc -l | tr -d ' ') webrtc files, $(find "$dest/abseil" -type f | wc -l | tr -d ' ') abseil files"
