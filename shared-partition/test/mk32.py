# SPDX-License-Identifier: GPL-3.0-or-later
# run-with python3
# synthetic Pixel-7-Pro-like GPT AFTER the split: 4096-B sectors, 31196160 sectors, first 6, last 31196154, 32 entries
import sys, struct, zlib, uuid, os
f = sys.argv[1]; nent = int(sys.argv[2]) if len(sys.argv) > 2 else 32
ss, total, first = 4096, 31196160, 6
last = total - first; alt = total - 1
guid = uuid.UUID("54494857-4345-4148-5045-4C204C554E31").bytes_le
ptype = uuid.UUID("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7").bytes_le
names = ["persist"] + ["part%d" % i for i in range(2, 31)] + ["userdata", "ubuntu"]
rng = {}
pos = first
for nm in names[:-2]:
    rng[nm] = (pos, pos + 65535); pos += 65536 + 256
rng["ubuntu"] = (2383334, 14704101); rng["userdata"] = (14704128, 25953023)
assert pos < 2383334
arr = bytearray(nent * 128)
for i, nm in enumerate(names):
    b = bytearray(128); b[0:16] = ptype; b[16:32] = uuid.UUID(int=0xCA4BCD37BAF24499B2AF3ED57C8C066B + i).bytes_le
    struct.pack_into("<QQQ", b, 32, rng[nm][0], rng[nm][1], 0); b[56:56 + 2 * len(nm)] = nm.encode("utf-16le"); arr[i * 128:(i + 1) * 128] = b
HF = "<8sIIIIQQQQ16sQIII"
def header(my, other, elba):
    b = bytearray(ss); struct.pack_into(HF, b, 0, b"EFI PART", 0x10000, 92, 0, 0, my, other, first, last, guid, elba, nent, 128, zlib.crc32(bytes(arr)))
    struct.pack_into("<I", b, 16, zlib.crc32(bytes(b[:92]))); return bytes(b)
fd = os.open(f, os.O_RDWR | os.O_CREAT | os.O_TRUNC); os.ftruncate(fd, total * ss)
mbr = bytearray(ss); mbr[446 + 4] = 0xEE; struct.pack_into("<II", mbr, 446 + 8, 1, 0xFFFFFFFF); mbr[510:512] = b"\x55\xaa"
os.pwrite(fd, bytes(mbr), 0)
os.pwrite(fd, header(1, alt, 2), ss); os.pwrite(fd, bytes(arr), 2 * ss)
os.pwrite(fd, bytes(arr), (last + 1) * ss); os.pwrite(fd, header(alt, 1, last + 1), alt * ss)
print("made", f, nent)
