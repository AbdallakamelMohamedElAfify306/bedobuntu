# SPDX-License-Identifier: GPL-3.0-or-later
import os, stat, struct, zlib
M, m = map(int, open("/sys/block/sda/dev").read().split(":")); ss = int(open("/sys/block/sda/queue/logical_block_size").read())
nd = "/run/spdiag.%d" % os.getpid(); os.mknod(nd, stat.S_IFBLK | 0o600, os.makedev(M, m))
try:
    fd = os.open(nd, os.O_RDONLY); tot = os.lseek(fd, 0, 2) // ss
    rd = lambda l, n: os.pread(fd, n, l * ss)
    h = struct.unpack("<8sIIIIQQQQ16sQIII", rd(1, ss)[:92]); sig, _, hs, crc, _, my, alt, first, last, _, elba, n, esz, acrc = h
    ah = struct.unpack("<8sIIIIQQQQ16sQIII", rd(alt, ss)[:92]); aelba = ah[10]
    arr = rd(elba, n * esz); ar2 = rd(aelba, n * esz)
    cap_p = (first - elba) * ss // 128; cap_a = (alt - aelba) * ss // 128
    zp = not any(rd(elba, (n + 1) * 128)[n * 128:(n + 1) * 128]); za = not any(rd(aelba, (n + 1) * 128)[n * 128:(n + 1) * 128])
    print("sector %d B, %d sectors, GPT sig %s, entries %d (esz %d), usable %d..%d, backup hdr %d" % (ss, tot, sig.decode(), n, esz, first, last, alt))
    print("array LBA primary %d backup %d ; room primary %d entries, backup %d entries (need >= 33)" % (elba, aelba, cap_p, cap_a))
    print("array CRC ok primary=%s backup=%s ; both copies equal=%s ; bytes after array zero: primary=%s backup=%s" % (zlib.crc32(arr) == acrc, zlib.crc32(ar2) == ah[13], arr == ar2, zp, za))
    mx = 0; names = []
    for i in range(n):
        e = arr[i * 128:(i + 1) * 128]
        if any(e):
            f, l = struct.unpack_from("<QQ", e, 32); nm = e[56:128].decode("utf-16le").split("\0")[0]; names.append(nm); mx = max(mx, l)
            if nm in ("userdata", "ubuntu", "shared") or i >= n - 3: print("  entry %2d %-10s %10d %10d %7d MiB" % (i + 1, nm, f, l, (l - f + 1) * ss // 1048576))
    al = 1048576 // ss; st = (mx + 1 + al - 1) // al * al + 16 * 1048576 // ss; en = (last + 1) // al * al - 1
    print("highest used sector %d ; free tail %d MiB ; room for 'shared': %d..%d = %d MiB" % (mx, (last - mx) * ss // 1048576, st, en, (en - st + 1) * ss // 1048576))
    ok = n <= 32 and cap_p >= 33 and cap_a >= 33 and zp and za and zlib.crc32(arr) == acrc and arr == ar2 and "shared" not in names
    print("VERDICT:", "READY: the table can take a 33rd entry and the tail is free" if ok else ("ALREADY has shared / >=33 entries" if (n >= 33 or "shared" in names) else "NOT READY: send me this output"))
finally:
    os.unlink(nd)
