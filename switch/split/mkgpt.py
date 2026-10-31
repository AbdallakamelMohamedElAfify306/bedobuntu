# SPDX-License-Identifier: GPL-3.0-or-later
# run-with python3
def __ne(a, b):
    return not (a == b)
"""mkgpt.py FILE SS TOTAL_SECTORS FIRST NENT USERDATA_START USERDATA_END [NPART]
Synthetic Pixel-like GPT: NENT entries declared, entry array in a reserved area (FIRST-2 sectors at front,
FIRST-1 sectors... mirrored at the end), NPART partitions (default NENT), the last being userdata."""
import sys, struct, zlib, uuid, os
f, ss, total, first, nent, us, ue = sys.argv[1], *map(int, sys.argv[2:8]); npart = int(sys.argv[8]) if len(sys.argv) > 8 else nent
guid = bytes.fromhex("5748495445434841 5045 4c204c554e31".replace(" ", ""))  # placeholder, replaced below
guid = uuid.UUID("54494857-4345-4148-5045-4C204C554E31").bytes_le
last = total - first            # last usable, as on the real disk (first=6: 31196160-6)
alt = total - 1
types = uuid.UUID("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7").bytes_le
arr = bytearray(nent * 128); pos = first
names = ["persist"] + ["part%d" % i for i in range(2, npart - 1)] + ["super"]
ents = []
for i, nm in enumerate(names):
    ents.append((pos, pos + 16383 if __ne(nm , "super") else us - 1, nm)); pos = ents[-1][1] + 1
ents.append((us, ue, "userdata"))
for i, (s, e, nm) in enumerate(ents[:nent]):
    b = bytearray(128); b[0:16] = types; b[16:32] = uuid.UUID(int=0xCA4BCD37BAF24499B2AF3ED57C8C066B + i).bytes_le
    struct.pack_into("<QQQ", b, 32, s, e, 0); b[56:56 + 2 * len(nm)] = nm.encode("utf-16le"); arr[i * 128:(i + 1) * 128] = b
HF = "<8sIIIIQQQQ16sQIII"
def header(my, other, elba):
    b = bytearray(ss); struct.pack_into(HF, b, 0, b"EFI PART", 0x10000, 92, 0, 0, my, other, first, last, guid, elba, nent, 128, zlib.crc32(bytes(arr)))
    struct.pack_into("<I", b, 16, zlib.crc32(bytes(b[:92]))); return bytes(b)
fd = os.open(f, os.O_RDWR | os.O_CREAT); os.ftruncate(fd, total * ss)
mbr = bytearray(ss); mbr[446 + 4] = 0xEE; struct.pack_into("<II", mbr, 446 + 8, 1, min(total - 1, 0xFFFFFFFF)); mbr[510:512] = b"\x55\xaa"
os.pwrite(fd, bytes(mbr), 0)
os.pwrite(fd, header(1, alt, 2), ss); os.pwrite(fd, bytes(arr), 2 * ss)
os.pwrite(fd, bytes(arr), (last + 1) * ss); os.pwrite(fd, header(alt, 1, last + 1), alt * ss)
print("made", f, "entries", nent, "used", len(ents[:nent]), "first", first, "last", last)
