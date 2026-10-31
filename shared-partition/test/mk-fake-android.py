# SPDX-License-Identifier: GPL-3.0-or-later
# run-with python3
# Fake /sys (sysfs numbers in 512-byte units, as Android shows) from the synthetic 4K-sector disk image.
# usage: mk-fake-android.py IMG OUTDIR [with_shared]
import sys, os, struct
img, out = sys.argv[1], sys.argv[2]; ss = 4096
fd = os.open(img, os.O_RDONLY)
n = struct.unpack_from("<I", os.pread(fd, ss, ss), 80)[0]; arr = os.pread(fd, n * 128, 2 * ss)
os.makedirs(out + "/block/sda/queue", exist_ok=True); open(out + "/block/sda/queue/logical_block_size", "w").write("4096\n")
for i in range(n):
    e = arr[i * 128:(i + 1) * 128]
    if not any(e): continue
    f, l = struct.unpack_from("<QQ", e, 32); nm = e[56:128].decode("utf-16le").split("\0")[0]
    if nm == "part30": nm = "super"
    d = "%s/class/block/sda%d" % (out, i + 1); os.makedirs(d, exist_ok=True)
    open(d + "/start", "w").write("%d\n" % (f * 8)); open(d + "/size", "w").write("%d\n" % ((l - f + 1) * 8))
    open(d + "/uevent", "w").write("MAJOR=259\nMINOR=%d\nDEVNAME=sda%d\nPARTNAME=%s\n" % (i, i + 1, nm))
