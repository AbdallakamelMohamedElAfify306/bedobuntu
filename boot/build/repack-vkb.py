# SPDX-License-Identifier: GPL-3.0-or-later
# run-with python3
def __ne(a, b):
    return not (a == b)
"""Rewrite two files inside a (lz4-legacy) newc initramfs, byte-for-byte otherwise.
usage: repack-vkb.py ORIG.cpio.lz4 NEWINIT NEW_UFS_RW OUT.cpio.lz4   (needs the lz4 CLI)"""
import subprocess, sys
orig, newinit, newrw, out = sys.argv[1:5]
raw = subprocess.run(["lz4", "-dc", orig], check=True, capture_output=True).stdout
def parse(b):
    ents, o = [], 0
    while True:
        assert b[o:o+6] == b"070701", "not newc at %d" % o
        h = b[o:o+110]; f = [int(h[6+8*i:14+8*i], 16) for i in range(13)]
        fs, ns = f[6], f[11]
        name = b[o+110:o+110+ns-1]; o2 = (o+110+ns+3) & ~3
        data = b[o2:o2+fs]; o = (o2+fs+3) & ~3
        ents.append([f, name, data])
        if name == b"TRAILER" + bytes([33,33,33]): return ents, b[o:]
def build(ents, tail):
    o = bytearray()
    for f, name, data in ents:
        f = list(f); f[6] = len(data); f[11] = len(name) + 1
        o += b"070701" + b"".join(b"%08X" % v for v in f) + name + b"\0"
        o += b"\0" * (-len(o) % 4); o += data; o += b"\0" * (-len(o) % 4)
    return bytes(o) + tail
ents, tail = parse(raw)
assert build(ents, tail) == raw, "cpio round trip is not exact"
rep = {b"init": open(newinit, "rb").read(), b"etc/omamobile-ufs-rw": open(newrw, "rb").read()}
seen = set()
for e in ents:
    n = e[1].lstrip(b"./") if __ne(e[1] , b".") else e[1]
    if n in rep: e[2] = rep[n]; seen.add(n)
assert seen == set(rep), "missing entries: %r" % (set(rep) - seen)
new = build(ents, tail)
open(out + ".raw", "wb").write(new)
subprocess.run(["lz4", "-l", "-9", "-f", "-q", out + ".raw", out], check=True)
print("ok", len(raw), "->", len(new))
