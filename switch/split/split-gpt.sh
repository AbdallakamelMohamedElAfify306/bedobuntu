# SPDX-License-Identifier: GPL-3.0-or-later
# run-with bash
# split-gpt: carve Ubuntu's running root out of the front of `userdata` (same start sector, no copy) and give
# Android a NEW `userdata` behind it, leaving FREE_MIB unallocated at the end of the disk.
# The GPT is edited RAW (python, stdlib only), NOT with sgdisk: gptfdisk's table resize rewrites first/last usable LBA and
# moves the backup table, which this Pixel GPT (31 entries in a 4-sector reserved area) must not see. Only these bytes change:
# entry N (start/end LBA), the new entry N+1, NumberOfPartitionEntries (if it must grow, e.g. 31 -> 32) and the CRCs,
# in BOTH the primary and the backup copy. sgdisk is used only to read and to verify afterwards.
#   split-gpt.sh plan                       read-only: print the plan and rehearse the raw GPT edit (dry run, writes nothing)
#   split-gpt.sh backup [DIR]               read-only: GPT backup (sgdisk + raw LBAs + restore.sh) into DIR
#   split-gpt.sh grow   [DIR] [--yes]       CANARY: only raise the entry count 31 -> 32 (extra entry empty); no partition changes
#   split-gpt.sh apply  [DIR] [--yes]       WRITES the GPT (needs the backup; asks you to type SPLIT)
#   split-gpt.sh wipe-android               zero the first 4 MiB of the NEW userdata (after apply, before reboot)
# Options: --ubuntu-mib N (default 48128)  --free-mib N (default 20480)  --min-android-mib N (default 20000)
# Only the partition table is written; no partition's data is touched except the 4 MiB zeroed by wipe-android,
# which lies beyond the end of the running ext4 (checked).
set -euo pipefail
DISK=${DISK:-/dev/sda}; SGDISK=${SGDISK:-sgdisk}
UBU_MIB=48128; FREE_MIB=20480; MIN_AND_MIB=20000
cmd=${1:-plan}; shift || true
DIR=""; YES=0
while [ $# -gt 0 ]; do case $1 in
  --ubuntu-mib) UBU_MIB=$2; shift 2;; --free-mib) FREE_MIB=$2; shift 2;; --min-android-mib) MIN_AND_MIB=$2; shift 2;;
  --yes) YES=1; shift;; *) DIR=$1; shift;; esac; done
die() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || [ -n "${SPLIT_TEST:-}" ] || die "run as root"
command -v "$SGDISK" >/dev/null || die "sgdisk not installed (apt-get install gdisk, or see the plan)"
command -v python3 >/dev/null || die "python3 not installed"
if { [ -e "$DISK"  ]; [ $? -ne 0 ]; } && [ "$DISK" = /dev/sda ]; then
  mknod /dev/sda b $(tr : ' ' < /sys/block/sda/dev) && echo "(re-created the /dev/sda node)"
fi
[ -e "$DISK" ] || die "$DISK not found"
if [ -b "$DISK" ] && { case "$(blockdev --getro "$DISK")" in 0) false;; *) true;; esac; }; then die "$DISK is read-only (blockdev --getro=1)"; fi

P=$($SGDISK -p "$DISK" 2>&1) || die "sgdisk -p failed: $P"
SS=$(echo "$P" | sed -n 's/^Sector size (logical[^:]*): *\([0-9]*\).*/\1/p' | head -1)
NENT=$(echo "$P" | sed -n 's/^Partition table holds up to \([0-9]*\) entries.*/\1/p')
FIRST=$(echo "$P" | sed -n 's/^First usable sector is \([0-9]*\), last usable sector is \([0-9]*\).*/\1/p')
LAST=$(echo "$P" | sed -n 's/^First usable sector is \([0-9]*\), last usable sector is \([0-9]*\).*/\2/p')
TOTAL=$(echo "$P" | sed -n 's/^Disk [^:]*: \([0-9]*\) sectors.*/\1/p')
[ -n "$SS" ] && [ -n "$NENT" ] && [ -n "$FIRST" ] && [ -n "$LAST" ] && [ -n "$TOTAL" ] || die "cannot parse sgdisk -p"
echo "$P" | grep -qi 'problem\|corrupt\|invalid\|overlap' && die "sgdisk reports a problem with the current GPT:\n$P"
ROWS=$(echo "$P" | awk '$1 ~ /^[0-9]+$/ && NF>=7')
if [ "$cmd" = backup ]; then
  DIR=${DIR:-/root/gpt-backup-$(date +%Y%m%d-%H%M%S)}; mkdir -p "$DIR"
  $SGDISK --backup="$DIR/gpt.sgdisk" "$DISK" >/dev/null
  dd if="$DISK" of="$DIR/primary.raw" bs="$SS" count="$FIRST" status=none
  NB=$((TOTAL - 1 - LAST)); dd if="$DISK" of="$DIR/backup.raw" bs="$SS" skip=$((LAST + 1)) count="$NB" status=none
  echo "$P" > "$DIR/gpt-print.txt"
  cat > "$DIR/restore.sh" <<RST
# run-with sh
# Restores the ORIGINAL partition table with plain dd (works in the initramfs). usage: sh restore.sh [DISK]
D=\${1:-/dev/sda}; cd "\$(dirname "\$0")" || exit 1
sha256sum -c SHA256SUMS || exit 1
dd if=primary.raw of=\$D bs=$SS count=$FIRST conv=notrunc && dd if=backup.raw of=\$D bs=$SS seek=$((LAST + 1)) count=$NB conv=notrunc && sync && echo "partition table restored; reboot"
RST
  (cd "$DIR" && sha256sum gpt.sgdisk primary.raw backup.raw > SHA256SUMS && cat SHA256SUMS)
  echo "primary.raw=$((FIRST*SS)) bytes, backup.raw=$((NB*SS)) bytes; backup in $DIR"
  exit 0

fi
if [ "$cmd" = wipe-android ]; then
  # after apply: userdata is the NEW (Android) partition; ubuntu the one holding this root
  UN=$(echo "$ROWS" | awk '$7=="userdata"{print $1}'); UB=$(echo "$ROWS" | awk '$7=="ubuntu"{print $1}')
  [ -n "$UB" ] && [ -n "$UN" ] || die "no ubuntu+userdata pair: run apply first"
  UBS=$($SGDISK -i "$UB" "$DISK" | sed -n 's/^First sector: *\([0-9]*\).*/\1/p'); UDS=$($SGDISK -i "$UN" "$DISK" | sed -n 's/^First sector: *\([0-9]*\).*/\1/p')
  if [ -z "${SPLIT_TEST:-}" ]; then
    ROOT_SRC=$(findmnt -no SOURCE /); DI=$(dumpe2fs -h "$ROOT_SRC" 2>/dev/null) || die "dumpe2fs $ROOT_SRC failed"
    [ "$(echo "$DI" | sed -n 's/^Filesystem volume name: *//p')" = omamobile-root ] || die "/ is not the omamobile-root ext4"
    FS_BYTES=$(( $(echo "$DI" | sed -n 's/^Block count: *//p') * $(echo "$DI" | sed -n 's/^Block size: *//p') )); else FS_BYTES=$SPLIT_FS_BYTES; fi
  [ $((UDS * SS)) -ge $((UBS * SS + FS_BYTES + 64*1048576)) ] || die "new userdata starts too close to the ext4 end; not writing"
  [ $((UDS * SS % 1048576)) = 0 ] || die "userdata start not 1 MiB aligned"
  OFF=$((UDS * SS / 1048576))
  dd if=/dev/zero of="$DISK" bs=1M seek="$OFF" count=4 conv=notrunc,fsync status=none
  dd if="$DISK" bs=1M skip="$OFF" count=4 status=none | cmp - <(head -c 4194304 /dev/zero) && echo "first 4 MiB of Android userdata (sector $UDS) are zero"
  exit 0
fi
N=$(echo "$ROWS" | awk '$7=="userdata"{print $1}'); [ "$(echo "$N" | grep -c .)" = 1 ] || die "need exactly one partition named userdata"
echo "$ROWS" | awk '$7=="ubuntu"' | grep -q . && die "a partition named ubuntu already exists (already split?)"
M=$((N+1)); echo "$ROWS" | awk -v m=$M '$1==m' | grep -q . && die "partition number $M is already used"
I=$($SGDISK -i "$N" "$DISK")
TYPE=$(echo "$I" | sed -n 's/^Partition GUID code: *\([0-9A-Fa-f-]*\).*/\1/p')
UGUID=$(echo "$I" | sed -n 's/^Partition unique GUID: *\([0-9A-Fa-f-]*\).*/\1/p')
OSTART=$(echo "$I" | sed -n 's/^First sector: *\([0-9]*\).*/\1/p'); OEND=$(echo "$I" | sed -n 's/^Last sector: *\([0-9]*\).*/\1/p')
ATTR=$(echo "$I" | sed -n 's/^Attribute flags: *\([0-9A-Fa-f]*\).*/\1/p')
[ -n "$TYPE" ] && [ -n "$UGUID" ] && [ -n "$OSTART" ] && [ -n "$OEND" ] || die "cannot parse sgdisk -i $N"
MAXEND=$(echo "$ROWS" | awk '{if($3+0>m)m=$3+0}END{print m}')
[ "$OEND" = "$MAXEND" ] || die "userdata (ends $OEND) is not the last partition (last ends $MAXEND)"
ALIGN=$((1048576 / SS)); [ $((1048576 % SS)) = 0 ] || die "odd sector size $SS"

# --- the running root must be the ext4 in userdata, and must fit in the new `ubuntu` ---
if [ -n "${SPLIT_TEST:-}" ]; then FS_BYTES=$SPLIT_FS_BYTES; ROOT_SRC=test
else
  ROOT_SRC=$(findmnt -no SOURCE /)
  [ "$ROOT_SRC" = "${DISK}$N" ] || [ "$cmd" = wipe-android ] || die "/ is on $ROOT_SRC, expected ${DISK}$N (userdata)"
  DI=$(dumpe2fs -h "$ROOT_SRC" 2>/dev/null) || die "dumpe2fs $ROOT_SRC failed"
  [ "$(echo "$DI" | sed -n 's/^Filesystem volume name: *//p')" = omamobile-root ] || die "$ROOT_SRC is not labelled omamobile-root"
  FS_BYTES=$(( $(echo "$DI" | sed -n 's/^Block count: *//p') * $(echo "$DI" | sed -n 's/^Block size: *//p') ))
fi
U_SECT=$((UBU_MIB * 1048576 / SS)); U_START=$OSTART; U_END=$((U_START + U_SECT - 1))
A_START=$(( (U_END + 1 + ALIGN - 1) / ALIGN * ALIGN ))
A_END=$(( (OEND + 1 - FREE_MIB * 1048576 / SS) / ALIGN * ALIGN - 1 ))
A_MIB=$(( (A_END - A_START + 1) * SS / 1048576 )); FREE_REAL=$(( (OEND - A_END) * SS / 1048576 ))
[ "$FS_BYTES" -le $(( U_SECT * SS - 128*1048576 )) ] || die "ext4 is $((FS_BYTES>>20)) MiB; ubuntu ($UBU_MIB MiB) must be at least 128 MiB larger"
[ "$A_END" -gt "$A_START" ] && [ "$A_MIB" -ge "$MIN_AND_MIB" ] || die "Android userdata would be only $A_MIB MiB (min $MIN_AND_MIB)"
[ "$A_END" -le "$OEND" ] && [ "$U_END" -lt "$A_START" ] || die "bad layout"
REAL_FS_END=$(( U_START * SS + FS_BYTES ))

show_plan() { cat <<PLAN
disk $DISK: $TOTAL sectors of $SS bytes, GPT holds $NENT entries, usable $FIRST..$LAST
userdata is partition $N: sectors $OSTART..$OEND ($(( (OEND-OSTART+1)*SS/1048576 )) MiB), type $TYPE, attrs $ATTR
root ext4 on $ROOT_SRC: $((FS_BYTES>>20)) MiB
layout (sectors)         start        end       MiB
  $N  userdata (Android, NEW)  $A_START  $A_END  $A_MIB  keeps type/unique GUID/attrs of the old userdata
  $M  ubuntu  (this ext4)      $U_START  $U_END  $UBU_MIB  start unchanged, same data, no copy
  --  unallocated tail         $((A_END+1))..$OEND  ~$FREE_REAL MiB
PLAN
}
gptedit() { # gptedit dry|apply  (raw GPT edit; see the header comment)
python3 - "$DISK" "$SS" "$N" "$M" "$OSTART" "$OEND" "$A_START" "$A_END" "$U_START" "$U_END" "$1" <<'PYEOF'
def __ne(a, b):
    return not (a == b)
import sys, struct, zlib, uuid, os
disk, ss, N, M, o_s, o_e, a_s, a_e, u_s, u_e = sys.argv[1], *map(int, sys.argv[2:11]); mode = sys.argv[11]; growonly = mode.startswith("grow"); doit = mode in ("apply", "grow")
HF = "<8sIIIIQQQQ16sQIII"; HS = struct.calcsize(HF)
def stop(m): print("STOP: " + m); sys.exit(1)
fd = os.open(disk, os.O_RDWR if doit else os.O_RDONLY)
def rd(lba, n): return os.pread(fd, n, lba * ss)
def hdr(raw):
    f = struct.unpack(HF, raw[:HS]); d = dict(zip("sig rev hs crc rsv my alt first last guid elba n esz acrc".split(), f))
    if __ne(d["sig"] , b"EFI PART"): stop("no GPT signature")
    if __ne(d["esz"] , 128) or __ne(d["hs"] , HS): stop("unexpected header/entry size %d/%d" % (d["hs"], d["esz"]))
    b = bytearray(raw[:HS]); b[16:20] = b"\0\0\0\0"
    if __ne(zlib.crc32(bytes(b)) , d["crc"]): stop("header CRC bad at LBA %d" % d["my"])
    return d
def pack(d, raw):
    b = bytearray(raw); struct.pack_into(HF, b, 0, d["sig"], d["rev"], d["hs"], 0, d["rsv"], d["my"], d["alt"], d["first"], d["last"], d["guid"], d["elba"], d["n"], d["esz"], d["acrc"])
    struct.pack_into("<I", b, 16, zlib.crc32(bytes(b[:HS]))); return bytes(b)
praw = rd(1, ss); p = hdr(praw)
if __ne(p["my"] , 1): stop("primary header not at LBA 1")
araw = rd(p["alt"], ss); a = hdr(araw)
parr = rd(p["elba"], p["n"] * 128); aarr = rd(a["elba"], a["n"] * 128)
if __ne(zlib.crc32(parr) , p["acrc"]): stop("primary entry array CRC bad")
if __ne(zlib.crc32(aarr) , a["acrc"]): stop("backup entry array CRC bad")
for k in ("first", "last", "guid", "n", "esz", "acrc"):
    if __ne(p[k] , a[k]): stop("primary and backup headers differ in " + k)
if __ne(a["my"] , p["alt"]) or __ne(a["alt"] , 1): stop("backup header does not point at the primary")
if __ne(parr , aarr): stop("primary and backup entry arrays differ")
cap_p = (p["first"] - p["elba"]) * ss // 128           # entries that fit before the first usable LBA
cap_a = (a["my"] - a["elba"]) * ss // 128              # entries that fit before the backup header
newn = max(p["n"], M)
if newn > cap_p or newn > cap_a: stop("table cannot grow to %d entries without moving things (room: primary %d, backup %d)" % (newn, cap_p, cap_a))
arr = bytearray(parr) + bytearray((newn - p["n"]) * 128)
if not growonly:
  eN = arr[(N - 1) * 128:N * 128]; eM = arr[(M - 1) * 128:M * 128]
  name = bytes(eN[56:128]).decode("utf-16le").split("\0")[0]
  f, l = struct.unpack_from("<QQ", eN, 32)
  if __ne(name , "userdata") or __ne(f , o_s) or __ne(l , o_e): stop("entry %d is %r %d..%d, expected userdata %d..%d" % (N, name, f, l, o_s, o_e))
  if any(eM): stop("entry %d is not empty" % M)
  ptype = None
  for i in range(p["n"]):
      e = arr[i * 128:(i + 1) * 128]
      if bytes(e[56:128]).decode("utf-16le").split("\0")[0] == "persist": ptype = bytes(e[:16])
  if ptype is None: ptype = uuid.UUID("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7").bytes_le
orig = bytes(arr)
if not growonly:
    struct.pack_into("<QQ", arr, (N - 1) * 128 + 32, a_s, a_e)
    new = bytearray(128); new[0:16] = ptype; new[16:32] = uuid.uuid4().bytes_le; struct.pack_into("<QQQ", new, 32, u_s, u_e, 0)
    new[56:56 + 12] = "ubuntu".encode("utf-16le"); arr[(M - 1) * 128:M * 128] = new
# invariants: every other entry byte-identical
for i in range(newn):
    if (growonly or i not in (N - 1, M - 1)) and i < p["n"] and __ne(orig[i * 128:(i + 1) * 128] , bytes(arr[i * 128:(i + 1) * 128])): stop("entry %d would change" % (i + 1))
# overlap / range check over all used entries
used = [(struct.unpack_from("<QQ", arr, i * 128 + 32), bytes(arr[i * 128 + 56:i * 128 + 128]).decode("utf-16le").split("\0")[0]) for i in range(newn) if any(arr[i * 128:i * 128 + 16])]
used.sort()
for (s1, e1), n1 in used:
    if s1 < p["first"] or e1 > p["last"] or e1 < s1: stop("%s %d..%d outside usable range" % (n1, s1, e1))
for ((s1, e1), n1), ((s2, e2), n2) in zip(used, used[1:]):
    if s2 <= e1: stop("%s overlaps %s" % (n1, n2))
arr = bytes(arr); acrc = zlib.crc32(arr)
pn = dict(p, n=newn, acrc=acrc); an = dict(a, n=newn, acrc=acrc)
praw2 = pack(pn, praw); araw2 = pack(an, araw)
print("raw GPT edit (%s): sector %d B, usable %d..%d, entries %d -> %d (room: %d/%d), disk GUID unchanged" % (mode, ss, p["first"], p["last"], p["n"], newn, cap_p, cap_a))
if growonly:
    print("  GROW ONLY: header numEntries+arrayCRC+headerCRC (primary LBA 1, backup LBA %d); the extra entry stays EMPTY; no partition changes" % a["my"])
else:
    print("  changes: header numEntries+arrayCRC+headerCRC (primary LBA 1, backup LBA %d), entry %d, new entry %d; all other %d entries and all other header fields identical" % (a["my"], N, M, newn - 2))
    print("  entry %d userdata  %d..%d  ->  %d..%d" % (N, o_s, o_e, a_s, a_e))
    print("  entry %d ubuntu    new       %d..%d  (type %s, same as persist)" % (M, u_s, u_e, str(uuid.UUID(bytes_le=ptype)).upper()))
if not doit: print("  (dry run: nothing written)"); sys.exit(0)
def wr(lba, data):
    if __ne(os.pwrite(fd, data, lba * ss) , len(data)): stop("short write at LBA %d" % lba)
# backup copy first, then the primary (as gptfdisk does)
old_tail = rd(a["elba"], (newn * 128 + ss - 1) // ss * ss)
wr(a["elba"], arr + old_tail[len(arr):]); wr(a["my"], araw2); os.fsync(fd)
old_tail = rd(p["elba"], (newn * 128 + ss - 1) // ss * ss)
wr(p["elba"], arr + old_tail[len(arr):]); wr(1, praw2); os.fsync(fd)
# read back and verify
p2 = hdr(rd(1, ss)); a2 = hdr(rd(p["alt"], ss))
for h in (p2, a2):
    if __ne(h["n"] , newn) or __ne(h["acrc"] , acrc): stop("read-back header mismatch")
if __ne(zlib.crc32(rd(p["elba"], newn * 128)) , acrc) or __ne(zlib.crc32(rd(a["elba"], newn * 128)) , acrc): stop("read-back array CRC mismatch")
print("  written and verified by read-back (header CRCs, array CRCs, both copies)")
PYEOF
}
rehearse() {
  V0=${V0:-$($SGDISK -v "$DISK" 2>&1 || true)}
  gptedit dry || die "raw GPT rehearsal failed. Not applying."
  echo "rehearsal OK: ubuntu starts at the SAME sector $U_START"
}
case $cmd in
plan) show_plan; echo; rehearse; echo "(nothing was written)";;
grow)
  DIR=${DIR:-$(ls -d /root/gpt-backup-* 2>/dev/null | tail -1)}; [ -n "$DIR" ] && [ -s "$DIR/SHA256SUMS" ] || die "run '$0 backup' first"
  (cd "$DIR" && sha256sum -c --quiet SHA256SUMS) || die "backup in $DIR does not match its checksums"
  dd if="$DISK" bs="$SS" count="$FIRST" status=none | cmp - "$DIR/primary.raw" || die "disk changed since the backup; take a new one"
  [ "$NENT" -ge "$M" ] && die "table already holds $NENT entries; nothing to grow"
  V0=$($SGDISK -v "$DISK" 2>&1 || true)
  gptedit grow-dry || die "rehearsal failed"
  if { case "$YES" in 1) false;; *) true;; esac; }; then printf 'This raises the entry count of the GPT on %s from %s to %s. Backup: %s\nType GROW to continue: ' "$DISK" "$NENT" "$M" "$DIR"; read -r a; [ "$a" = GROW ] || die cancelled; fi
  gptedit grow || die "raw edit failed; if anything was written restore with: sh $DIR/restore.sh"
  sync
  P2=$($SGDISK -p "$DISK"); echo "$P2" | sed -n '/holds up to/p;/First usable/p'
  [ "$(echo "$P2" | sed -n 's/^Partition table holds up to \([0-9]*\) entries.*/\1/p')" = "$M" ] || die "entry count did not change; restore with: sh $DIR/restore.sh"
  for pat in 's/^First usable sector is \([0-9]*\), last usable sector is \([0-9]*\).*/\1 \2/p'; do
    [ "$(echo "$P2" | sed -n "$pat")" = "$(echo "$P" | sed -n "$pat")" ] || die "usable range changed. restore with: sh $DIR/restore.sh"; done
  [ "$(echo "$P2" | awk '$1 ~ /^[0-9]+$/ && NF>=7' | md5sum)" = "$(echo "$ROWS" | md5sum)" ] || die "partition rows changed. restore with: sh $DIR/restore.sh"
  echo "GROWN: 31 -> 32 entries, partitions untouched. Now reboot (plain reboot, then reboot-to bootloader + fastboot getvar all) before running apply.";;
apply)
  DIR=${DIR:-$(ls -d /root/gpt-backup-* 2>/dev/null | tail -1)}; [ -n "$DIR" ] && [ -s "$DIR/SHA256SUMS" ] || die "run '$0 backup' first"
  (cd "$DIR" && sha256sum -c --quiet SHA256SUMS) || die "backup in $DIR does not match its checksums"
  # the backup must describe the CURRENT table
  dd if="$DISK" bs="$SS" count="$FIRST" status=none | cmp - "$DIR/primary.raw" || die "disk changed since the backup; take a new one"
  show_plan; echo; rehearse
  if { case "$YES" in 1) false;; *) true;; esac; }; then printf 'This WRITES the partition table of %s. Backup: %s\nType SPLIT to continue: ' "$DISK" "$DIR"; read -r a; [ "$a" = SPLIT ] || die cancelled; fi
  gptedit apply || die "raw edit failed; if anything was written restore with: sh $DIR/restore.sh"
  sync
  V=$($SGDISK -v "$DISK" 2>&1 || true); echo "$V" | tail -3
  if echo "$V0" | grep -q 'No problems found'; then echo "$V" | grep -q 'No problems found' || die "sgdisk -v now reports problems; restore with: sh $DIR/restore.sh"
  else echo "NOTE: sgdisk -v was not clean before the edit either:"; echo "$V0" | tail -3; fi
  P2=$($SGDISK -p "$DISK"); echo "$P2" | tail -4
  for pat in 's/^First usable sector is \([0-9]*\), last usable sector is \([0-9]*\).*/\1 \2/p' 's/^Sector size (logical[^:]*): *\([0-9]*\).*/\1/p'; do
    [ "$(echo "$P2" | sed -n "$pat")" = "$(echo "$P" | sed -n "$pat")" ] || die "usable range or sector size changed. restore with: sh $DIR/restore.sh"; done
  [ "$($SGDISK -i "$M" "$DISK" | sed -n 's/^First sector: *\([0-9]*\).*/\1/p')" = "$U_START" ] || die "ubuntu does not start at $U_START. restore with: sh $DIR/restore.sh"
  [ "$($SGDISK -i "$N" "$DISK" | sed -n 's/^First sector: *\([0-9]*\).*/\1/p')" = "$A_START" ] || die "userdata does not start at $A_START. restore with: sh $DIR/restore.sh"
  echo "GPT written. The kernel keeps the OLD table while / is mounted: run 'wipe-android' next, then reboot.";;
*) sed -n '2,12p' "$0"; exit 2;;
esac
