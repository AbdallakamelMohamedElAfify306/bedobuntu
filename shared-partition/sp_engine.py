# SPDX-License-Identifier: GPL-3.0-or-later
# run-with python3
def __ne(a, b):
    return not (a == b)
# sp_engine.py  (embedded in shared-part-create.sh)
# Raw, minimal GPT edit for the Pixel 7 Pro LUN (4096-byte sectors, entry array in the 4 reserved sectors).
# usage: sp_engine.py DISK SS MODE [--gap-mib N] [--min-mib N] [--start LBA --end LBA] [--name NAME]
#   MODE: diag    read-only report (never writes)
#         plan    in-memory rehearsal of grow(+create); never writes
#         grow    write: NumberOfPartitionEntries 32 -> 33, entry 33 stays EMPTY (canary)
#         create  write: fill the first empty entry (needs >= 33 entries already) with the new partition
# Only these bytes ever change: NumberOfPartitionEntries, entry array CRC, header CRC (primary LBA 1 + backup
# header), the new/extended entry array tail, and the one new entry. Every other entry, first/last usable LBA,
# backup LBA, entry LBA, disk GUID stay byte-identical. Both copies (primary+backup) are written, backup first.
import sys, struct, zlib, uuid, os

HF = "<8sIIIIQQQQ16sQIII"
HS = struct.calcsize(HF)
TARGET_ENTRIES = 33
MIB = 1048576


def stop(msg):
    print("STOP: " + msg)
    sys.exit(1)


def parse_args(argv):
    if len(argv) < 3:
        stop("usage: sp_engine.py DISK SS MODE [options]")
    a = {"disk": argv[0], "ss": int(argv[1]), "mode": argv[2], "gap_mib": 16, "min_mib": 10240,
         "start": None, "end": None, "name": "shared"}
    i = 3
    while i < len(argv):
        k = argv[i]
        if k == "--gap-mib": a["gap_mib"] = int(argv[i + 1])
        elif k == "--min-mib": a["min_mib"] = int(argv[i + 1])
        elif k == "--start": a["start"] = int(argv[i + 1])
        elif k == "--end": a["end"] = int(argv[i + 1])
        elif k == "--name": a["name"] = argv[i + 1]
        else: stop("unknown option " + k)
        i += 2
    return a


A = parse_args(sys.argv[1:])
disk, ss, mode = A["disk"], A["ss"], A["mode"]
if mode not in ("diag", "plan", "grow", "create"): stop("bad mode " + mode)
if ss not in (512, 4096): stop("unexpected sector size %d" % ss)
doit = mode in ("grow", "create")
fd = os.open(disk, os.O_RDWR if doit else os.O_RDONLY)
total = os.lseek(fd, 0, os.SEEK_END) // ss


def rd(lba, n): return os.pread(fd, n, lba * ss)


def hdr(raw, where):
    f = struct.unpack(HF, raw[:HS])
    d = dict(zip("sig rev hs crc rsv my alt first last guid elba n esz acrc".split(), f))
    if __ne(d["sig"] , b"EFI PART"): stop("no GPT signature at " + where)
    if __ne(d["esz"] , 128) or __ne(d["hs"] , HS): stop("unexpected header/entry size %d/%d at %s" % (d["hs"], d["esz"], where))
    b = bytearray(raw[:HS]); b[16:20] = b"\0\0\0\0"
    if __ne(zlib.crc32(bytes(b)) , d["crc"]): stop("header CRC bad at " + where)
    return d


def pack(d, raw):
    b = bytearray(raw)
    struct.pack_into(HF, b, 0, d["sig"], d["rev"], d["hs"], 0, d["rsv"], d["my"], d["alt"], d["first"], d["last"],
                     d["guid"], d["elba"], d["n"], d["esz"], d["acrc"])
    struct.pack_into("<I", b, 16, zlib.crc32(bytes(b[:HS])))
    return bytes(b)


def ename(e): return bytes(e[56:128]).decode("utf-16le").split("\0")[0]


praw = rd(1, ss); p = hdr(praw, "primary LBA 1")
if __ne(p["my"] , 1): stop("primary header not at LBA 1")
araw = rd(p["alt"], ss); a = hdr(araw, "backup LBA %d" % p["alt"])
if __ne(p["alt"] , total) - 1: stop("backup header LBA %d is not the last sector %d" % (p["alt"], total - 1))
parr = rd(p["elba"], p["n"] * 128); aarr = rd(a["elba"], a["n"] * 128)
if __ne(zlib.crc32(parr) , p["acrc"]): stop("primary entry array CRC bad")
if __ne(zlib.crc32(aarr) , a["acrc"]): stop("backup entry array CRC bad")
for k in ("first", "last", "guid", "n", "esz", "acrc"):
    if __ne(p[k] , a[k]): stop("primary and backup headers differ in " + k)
if __ne(a["my"] , p["alt"]) or __ne(a["alt"] , 1): stop("backup header does not point at the primary")
if __ne(parr , aarr): stop("primary and backup entry arrays differ")
cap_p = (p["first"] - p["elba"]) * ss // 128   # entries that fit before the first usable LBA
cap_a = (a["my"] - a["elba"]) * ss // 128      # entries that fit before the backup header
n0 = p["n"]


def entries_of(arr):
    out = []
    for i in range(len(arr) // 128):
        e = arr[i * 128:(i + 1) * 128]
        if any(e):
            f, l = struct.unpack_from("<QQ", e, 32)
            out.append((i + 1, ename(e), f, l, bytes(e[:16])))
    return out


used0 = entries_of(parr)
names0 = [u[1] for u in used0]
align = MIB // ss
max_end = max(u[3] for u in used0)
# the entries must be contiguous (Android's boot HAL stops at the first nameless entry)
idxs = [u[0] for u in used0]
contiguous = idxs == list(range(1, len(idxs) + 1))
gap = A["gap_mib"] * MIB // ss
start = A["start"] if A["start"] is not None else ((max_end + 1 + align - 1) // align) * align + gap
start = ((start + align - 1) // align) * align
end = A["end"] if A["end"] is not None else ((p["last"] + 1) // align) * align - 1
ex = [u for u in used0 if u[1] == A["name"]]
if ex and A["start"] is None and A["end"] is None:      # already created: report its real range
    start, end = ex[0][2], ex[0][3]
size_mib = (end - start + 1) * ss // MIB

# reserved-area bytes after the current array must be zero in both copies (we will write there)
zp = not any(rd(p["elba"], (p["n"] + 1) * 128 + 0)[p["n"] * 128:(p["n"] + 1) * 128]) if cap_p > p["n"] else False
za = not any(rd(a["elba"], (a["n"] + 1) * 128 + 0)[a["n"] * 128:(a["n"] + 1) * 128]) if cap_a > a["n"] else False


def report():
    print("disk %s: %d sectors x %d B = %d MiB" % (disk, total, ss, total * ss // MIB))
    print("GPT: entries=%d  array room: primary=%d backup=%d  usable %d..%d  backup hdr LBA %d  array LBA primary %d backup %d  guid %s"
          % (n0, cap_p, cap_a, p["first"], p["last"], p["alt"], p["elba"], a["elba"], uuid.UUID(bytes_le=p["guid"])))
    print("entry %d bytes of array = %d sectors (one sector holds %d entries)" % (n0 * 128, (n0 * 128 + ss - 1) // ss, ss // 128))
    print("bytes right after the array are zero (needed to add an entry): primary=%s backup=%s" % (zp, za))
    print("entries contiguous from 1 (needed by Android boot HAL): %s" % contiguous)
    for (i, nm, f, l, t) in used0:
        print("  %2d %-22s %10d %10d %8d MiB" % (i, nm, f, l, (l - f + 1) * ss // MIB))
    print("last used sector (max end) = %d ; last usable = %d ; unused tail after max end = %d MiB"
          % (max_end, p["last"], (p["last"] - max_end) * ss // MIB))
    if A["name"] not in names0:
        print("proposed '%s': start %d end %d = %d MiB (1 MiB aligned, %d MiB gap after the last partition)"
              % (A["name"], start, end, size_mib, A["gap_mib"]))
    print("existing partitions named shared: %s" % ("YES" if A["name"] in names0 else "no"))


def validate_new(allused):
    if A["name"] in [u[1] for u in allused]: stop("a partition named %s already exists" % A["name"])
    if "ubuntu" not in names0 or "userdata" not in names0: stop("expected partitions ubuntu and userdata not found (is this the split layout?)")
    if not contiguous: stop("entries are not contiguous from 1")
    if start < p["first"] or end > p["last"] or end <= start: stop("range %d..%d outside usable %d..%d" % (start, end, p["first"], p["last"]))
    if start % align or (end + 1) % align: stop("range not 1 MiB aligned")
    for (i, nm, f, l, t) in allused:
        if not (end < f or start > l): stop("new range %d..%d overlaps %s %d..%d" % (start, end, nm, f, l))
    if size_mib < A["min_mib"]: stop("only %d MiB free (min %d). Use --min-mib to lower the limit" % (size_mib, A["min_mib"]))
    if len(A["name"].encode("utf-16le")) > 72: stop("name too long")


def build(n_target, add_entry):
    """return (newarr, newn) from the on-disk array, extended to n_target entries, optionally with the new entry."""
    if n_target > cap_p or n_target > cap_a:
        stop("table cannot hold %d entries (room: primary %d, backup %d) without moving things" % (n_target, cap_p, cap_a))
    arr = bytearray(parr) + bytearray(max(0, n_target - n0) * 128)
    if n_target > n0:
        if not (zp and za): stop("the bytes after the current entry array are not zero (primary=%s backup=%s); not writing there" % (zp, za))
    if add_entry:
        free = [i for i in range(n_target) if not any(arr[i * 128:(i + 1) * 128])]
        if not free: stop("no empty entry")
        slot = free[0]
        if any(any(arr[j * 128:(j + 1) * 128]) for j in range(slot, n_target)): stop("entries after the first empty one are not empty")
        ptype = None
        for (i, nm, f, l, t) in used0:
            if nm == "ubuntu": ptype = t
        if ptype is None: stop("no ubuntu entry to copy the type GUID from")
        new = bytearray(128); new[0:16] = ptype; new[16:32] = uuid.uuid4().bytes_le
        struct.pack_into("<QQQ", new, 32, start, end, 0)
        nb = A["name"].encode("utf-16le"); new[56:56 + len(nb)] = nb
        arr[slot * 128:(slot + 1) * 128] = new
    # invariants: every non-empty entry byte-identical; at most the one new entry differs
    changed = 0
    for i in range(n0):
        before, after = parr[i * 128:(i + 1) * 128], bytes(arr[i * 128:(i + 1) * 128])
        if __ne(before , after):
            if any(before): stop("entry %d would change" % (i + 1))
            changed += 1
    if changed > (1 if add_entry else 0): stop("more than the one new entry would change")
    if __ne(bytes(arr[:n0 * 128]) , parr) and not add_entry: stop("entries would change")
    return bytes(arr), n_target


def finish(arr, n_new, label, write):
    acrc = zlib.crc32(arr)
    praw2 = pack(dict(p, n=n_new, acrc=acrc), praw)
    araw2 = pack(dict(a, n=n_new, acrc=acrc), araw)
    # self-check of the rehearsal: re-parse our own bytes
    chk = hdr(praw2, "rehearsal primary"); hdr(araw2, "rehearsal backup")
    if __ne(chk["n"] , n_new) or __ne(chk["acrc"] , acrc): stop("internal rehearsal mismatch")
    print("raw GPT edit (%s): sector %d B, usable %d..%d (unchanged), entries %d -> %d (room %d/%d), disk GUID unchanged"
          % (label, ss, p["first"], p["last"], n0, n_new, cap_p, cap_a))
    if not write:
        print("  (dry run: nothing written)"); return
    def wr(lba, data):
        if __ne(os.pwrite(fd, data, lba * ss) , len(data)): stop("short write at LBA %d" % lba)
    nsec = (n_new * 128 + ss - 1) // ss * ss
    old_a = rd(a["elba"], nsec); wr(a["elba"], arr + old_a[len(arr):]); wr(a["my"], araw2); os.fsync(fd)   # backup first
    old_p = rd(p["elba"], nsec); wr(p["elba"], arr + old_p[len(arr):]); wr(1, praw2); os.fsync(fd)         # then primary
    p2 = hdr(rd(1, ss), "read-back primary"); a2 = hdr(rd(p["alt"], ss), "read-back backup")
    for h in (p2, a2):
        if __ne(h["n"] , n_new) or __ne(h["acrc"] , acrc): stop("read-back header mismatch")
    if __ne(p2["first"] , p["first"]) or __ne(p2["last"] , p["last"]) or __ne(p2["guid"] , p["guid"]): stop("read-back: usable range or GUID changed")
    if __ne(zlib.crc32(rd(p["elba"], n_new * 128)) , acrc) or __ne(zlib.crc32(rd(a["elba"], n_new * 128)) , acrc): stop("read-back array CRC mismatch")
    if __ne(rd(p["elba"], n_new * 128) , arr) or __ne(rd(a["elba"], n_new * 128) , arr): stop("read-back array differs")
    print("  written and verified by read-back (header CRCs, array CRCs, both copies)")


if mode == "diag":
    report()
    if n0 < TARGET_ENTRIES:
        print("CAN_GROW_TO_%d: %s" % (TARGET_ENTRIES, "yes" if (cap_p >= TARGET_ENTRIES and cap_a >= TARGET_ENTRIES and zp and za) else "NO"))
    else:
        print("ENTRIES_ALREADY_%d_OR_MORE: yes" % TARGET_ENTRIES)
    print("KV: n=%d first=%d last=%d total=%d ss=%d cap_p=%d cap_a=%d start=%d end=%d exists=%d"
          % (n0, p["first"], p["last"], total, ss, cap_p, cap_a, start, end, 1 if A["name"] in names0 else 0))
    sys.exit(0)

if mode == "plan":
    report()
    validate_new(used0)
    arr, n = (parr, n0)
    if n0 < TARGET_ENTRIES:
        arr, n = build(TARGET_ENTRIES, False); finish(arr, n, "grow (rehearsal)", False)
    # rehearse create on top of the (virtual) grown table
    save_parr, save_n0 = parr, n0
    parr = arr; n0 = n
    arr2, n2 = build(n0, True)
    parr, n0 = save_parr, save_n0
    finish(arr2, n2, "create (rehearsal)", False)
    print("rehearsal OK")
    sys.exit(0)

if mode == "grow":
    if n0 >= TARGET_ENTRIES: stop("table already holds %d entries; nothing to grow" % n0)
    if __ne(n0 , TARGET_ENTRIES) - 1: stop("expected exactly %d entries before growing, found %d" % (TARGET_ENTRIES - 1, n0))
    validate_new(used0)
    arr, n = build(TARGET_ENTRIES, False)
    finish(arr, n, "grow", True)
    print("GROW ONLY: entry count %d -> %d, the extra entry is EMPTY, no partition changed" % (n0, n))
    sys.exit(0)

if mode == "create":
    if n0 < TARGET_ENTRIES: stop("table holds only %d entries: run grow first, reboot both systems, then create" % n0)
    validate_new(used0)
    arr, n = build(n0, True)
    finish(arr, n, "create", True)
    print("CREATED %s: start %d end %d (%d MiB)" % (A["name"], start, end, size_mib))
    sys.exit(0)
