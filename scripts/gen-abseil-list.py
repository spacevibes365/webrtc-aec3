#!/usr/bin/env python3
"""Derive scripts/abseil-files.txt: the abseil files the vendored code needs.

Run by hand when the upstream version changes. Usage:
  gen-abseil-list.py <abseil-dir> <vendored-webrtc-dir-or-wap-webrtc-dir> <wrapper-dir> <cc-list>
<cc-list> is a text file with the abseil .cc files the link needs (one per
line, relative to the abseil root); the headers are the include closure of
the webrtc/wrapper code and of those .cc files.
"""
import os, re, sys

absl_root, webrtc_dir, wrapper_dir, cc_list = sys.argv[1:5]
cc = [l.strip() for l in open(cc_list) if l.strip()]
inc = re.compile(r'^\s*#\s*include\s+"(absl/[^"]+)"', re.M)

seen, queue = set(), []
def add(path):
    if path not in seen:
        seen.add(path); queue.append(path)

for base in (webrtc_dir, wrapper_dir):
    for d, _, files in os.walk(base):
        for f in files:
            if f.endswith((".h", ".cc", ".c", ".inc")):
                for m in inc.finditer(open(os.path.join(d, f), errors="replace").read()):
                    add(m.group(1))
for f in cc:
    add(f)
while queue:
    f = queue.pop()
    full = os.path.join(absl_root, f)
    if not os.path.exists(full):
        sys.exit("missing: " + f)
    if f.endswith((".h", ".inc", ".cc")):
        for m in inc.finditer(open(full, errors="replace").read()):
            add(m.group(1))
        # a header's implementation file is not implied: only <cc-list> counts
print("\n".join(sorted(seen)))
