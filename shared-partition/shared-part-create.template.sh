# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash shared-part-create.template.sh
# shared-part-create.sh  -  runs ON UBUNTU (phone), as root.
# Creates ONE new GPT partition named "shared" in the free tail of the UFS disk and formats it ext4, so that
# Android (Magisk root) and Ubuntu can both use it. It never touches sda31 (userdata) or sda32 (ubuntu) data:
# only the GPT (entry count + one new entry + CRCs) is written, then the new partition is formatted.
#
#   check                      read-only: layout, array room, proposed range, rehearsal of the raw GPT edit
#   backup [LABEL]             read-only: GPT backup (raw LBAs + sgdisk + restore.sh + SHA256SUMS) in /root/shared-part-state/
#   grow   [--yes] [--backup DIR]   STEP 1 (canary): entry count 32 -> 33, new entry stays EMPTY. Then reboot both OSes.
#   create [--yes] [--backup DIR]   STEP 2: fill entry 33 with partition "shared" (needs 33 entries already)
#   format [--yes] [--uid N]...     STEP 3: mkfs.ext4 label SHARED + permissions/ACL for Android (media_rw 1023) and Ubuntu uid N
# Options: --gap-mib N (16)  --min-mib N (10240)  --name NAME (shared)  --wipe (allow wipefs of stray signatures)
# Environment for testing only: SP_DISK=<file or device>, SP_SS=<sector size>, SP_NOSYS=1 (skip udev/partx/sysfs)
set -euo pipefail
export LC_ALL=C
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
STATE=${SP_STATE:-/root/shared-part-state}
NAME=shared; LABEL=SHARED; GAP=16; MINMIB=10240; YES=0; WIPE=0; BK=""; UIDS=""
cmd=${1:-check}; shift || true
while [ $# -gt 0 ]; do case $1 in
  --yes) YES=1; shift;; --wipe) WIPE=1; shift;;
  --backup) BK=$2; shift 2;; --gap-mib) GAP=$2; shift 2;; --min-mib) MINMIB=$2; shift 2;;
  --name) NAME=$2; shift 2;; --uid) UIDS="$UIDS $2"; shift 2;;
  *) LABELARG=$1; shift;; esac; done
die() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || [ -n "${SP_DISK:-}" ] || die "run as root (ssh root@172.16.42.1)"
command -v python3 >/dev/null || die "python3 not installed"
mkdir -p "$STATE"

# ---- the disk node: the initramfs guard removed /dev/sda on purpose, so use a private temporary node ----
NODE=""; TMPNODE=""
cleanup() { [ -z "$TMPNODE" ] || rm -f "$TMPNODE"; if [ -n "${UDEV_STOPPED:-}" ]; then systemctl start systemd-udevd-control.socket systemd-udevd-kernel.socket systemd-udevd.service 2>/dev/null || true; UDEV_STOPPED=""; fi; }
trap cleanup EXIT
if [ -n "${SP_DISK:-}" ]; then NODE=$SP_DISK; SS=${SP_SS:-4096}
else
  [ -r /sys/block/sda/dev ] || die "/sys/block/sda not found (are you on the phone, in Ubuntu?)"
  SS=$(cat /sys/block/sda/queue/logical_block_size)
  TMPNODE=/run/shared-part-sda.$$
  mknod "$TMPNODE" b $(cut -d: -f1 /sys/block/sda/dev) $(cut -d: -f2 /sys/block/sda/dev)
  NODE=$TMPNODE
  [ "$(blockdev --getro "$NODE")" = 0 ] || die "the disk sda is read-only (blockdev --getro = 1)"
  [ "$(cat /sys/block/sda/size)" -gt 30000000 ] || die "sda is not the big UFS LUN"
fi
ENGINE=/run/sp_engine.$$.py
write_engine() { cat > "$ENGINE" <<'PYEOF'
@@ENGINE@@
PYEOF
}
write_engine; trap 'rm -f "$ENGINE"; cleanup' EXIT
eng() { python3 "$ENGINE" "$NODE" "$SS" "$@" --gap-mib "$GAP" --min-mib "$MINMIB" --name "$NAME"; }
kv() { local d; d=$(eng diag) || { echo "$d" >&2; return 1; }; echo "$d" | sed -n 's/^KV: //p'; }
getkv() { echo "$KV" | tr ' ' '\n' | sed -n "s/^$1=//p"; }
command -v sgdisk >/dev/null || die "sgdisk not installed (apt-get install gdisk)"
SGD=sgdisk
rows() { $SGD -p "$NODE" 2>&1 | awk '$1 ~ /^[0-9]+$/ && NF>=7'; }
udev_stop() { [ -n "${SP_NOSYS:-}" ] && return 0; UDEV_STOPPED=1; systemctl stop systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket 2>/dev/null || true; }
udev_start() { [ -n "${SP_NOSYS:-}" ] && return 0; systemctl start systemd-udevd-control.socket systemd-udevd-kernel.socket systemd-udevd.service 2>/dev/null || true; UDEV_STOPPED=""; }

KV=$(kv) || die "cannot read the GPT (message above)"
[ -n "$KV" ] || die "cannot parse the GPT"
FIRST=$(getkv first); LAST=$(getkv last); TOTAL=$(getkv total); NENT=$(getkv n)

do_backup() { # do_backup LABEL -> sets BKDIR
  BKDIR="$STATE/backup-${1:-manual}-$(date +%Y%m%d-%H%M%S)-$$"; mkdir -p "$BKDIR"
  [ -z "$SGD" ] || $SGD --backup="$BKDIR/gpt.sgdisk" "$NODE" >/dev/null
  dd if="$NODE" of="$BKDIR/primary.raw" bs="$SS" count="$FIRST" status=none
  NB=$((TOTAL - 1 - LAST)); dd if="$NODE" of="$BKDIR/backup.raw" bs="$SS" skip=$((LAST + 1)) count="$NB" status=none
  [ -z "$SGD" ] || $SGD -p "$NODE" > "$BKDIR/gpt-print.txt" 2>&1 || true
  eng diag > "$BKDIR/engine-diag.txt" || true
  cat > "$BKDIR/restore.sh" <<RST
# run-with sh
# Restores the partition table that existed when this backup was taken (plain dd, works anywhere). usage: sh restore.sh DISKNODE
D=\${1:?usage: sh restore.sh /path/to/whole-disk-node}; cd "\$(dirname "\$0")" || exit 1
sha256sum -c SHA256SUMS || exit 1
dd if=primary.raw of="\$D" bs=$SS count=$FIRST conv=notrunc,fsync && dd if=backup.raw of="\$D" bs=$SS seek=$((LAST + 1)) count=$NB conv=notrunc,fsync && sync && echo "partition table restored; reboot (or umount the shared partition first, then reboot)"
RST
  (cd "$BKDIR" && sha256sum primary.raw backup.raw > SHA256SUMS && { { [ -f gpt.sgdisk  ]; [ $? -ne 0 ]; } || sha256sum gpt.sgdisk >> SHA256SUMS; } && cat SHA256SUMS)
  echo "$BKDIR" > "$STATE/latest-backup"
  echo "backup in $BKDIR  (primary.raw=$((FIRST*SS)) bytes, backup.raw=$((NB*SS)) bytes, entries=$NENT)"
}
need_backup() { # backup dir must exist, verify, and describe the CURRENT table
  local d=${BK:-$(cat "$STATE/latest-backup" 2>/dev/null || true)}
  [ -n "$d" ] && [ -s "$d/SHA256SUMS" ] || die "no backup: run  shared-part-create.sh backup  first"
  (cd "$d" && sha256sum -c --quiet SHA256SUMS) || die "backup $d does not match its checksums"
  dd if="$NODE" bs="$SS" count="$FIRST" status=none | cmp -s - "$d/primary.raw" || die "disk changed since the backup in $d: take a new one (backup)"
  NB=$((TOTAL - 1 - LAST)); dd if="$NODE" bs="$SS" skip=$((LAST + 1)) count="$NB" status=none | cmp -s - "$d/backup.raw" || die "backup copy of the GPT changed since $d: take a new backup"
  BKDIR=$d; echo "backup OK: $BKDIR"
}
record_state() { dd if="$NODE" bs="$SS" count="$FIRST" status=none | sha256sum | cut -d' ' -f1 > "$STATE/last-written.sha"; echo "$1 $(date -Iseconds) entries=$(getkv n) backup=$BKDIR" >> "$STATE/log"; }
sg_ok() { [ -z "$SGD" ] || { local v; v=$($SGD -v "$NODE" 2>&1 || true); echo "$v" | tail -2; echo "$v" | grep -q "No problems found"; }; }

case $cmd in
check)
  eng diag
  if [ "$(getkv exists)" = 0 ]; then echo; eng plan | sed -n '/raw GPT edit/,$p'; fi
  echo; echo "--- environment ---"
  for t in sgdisk partx blockdev mkfs.ext4 dumpe2fs e2fsck tune2fs setfacl wipefs blkid findmnt; do printf '%-10s %s\n' "$t" "$(command -v $t || echo MISSING)"; done
  [ -n "${SP_NOSYS:-}" ] || { echo "root fs: $(findmnt -no SOURCE,FSTYPE /)"; echo "partitions of sda:"; for s in /sys/block/sda/sda*; do printf '  %s name=%s start=%s size=%sMiB ro=%s\n' "${s##*/}" "$(sed -n 's/^PARTNAME=//p' "$s/uevent")" "$(cat "$s/start")" $(( $(cat "$s/size") / 2048 )) "$(cat "$s/ro")"; done; }
  echo "(nothing was written)";;
backup) do_backup "${LABELARG:-manual}";;
grow)
  [ "$NENT" -lt 33 ] || die "table already holds $NENT entries (grow already done)"
  need_backup; eng plan | sed -n '/raw GPT edit/,$p'
  if { case "$YES" in 1) false;; *) true;; esac; }; then printf 'This raises the entry count of the GPT from %s to 33 (new entry empty). Backup: %s\nType GROW to continue: ' "$NENT" "$BKDIR"; read -r a; [ "$a" = GROW ] || die cancelled; fi
  V0=$(rows | md5sum); sg_ok || echo "NOTE: sgdisk -v not clean before the edit"
  udev_stop; eng grow || die "raw edit failed; restore with: sh $BKDIR/restore.sh $NODE"; sync; udev_start
  KV=$(kv); [ "$(getkv n)" = 33 ] || die "entry count did not change; restore with: sh $BKDIR/restore.sh $NODE"
  [ "$(getkv last)" = "$LAST" ] && [ "$(getkv first)" = "$FIRST" ] || die "usable range changed; restore with: sh $BKDIR/restore.sh $NODE"
  [ "$(rows | md5sum)" = "$V0" ] || die "partition rows changed; restore with: sh $BKDIR/restore.sh $NODE"
  sg_ok || die "sgdisk -v reports problems; restore with: sh $BKDIR/restore.sh $NODE"
  record_state grow
  echo "GROWN: 32 -> 33 entries, partitions untouched. NOW: reboot Ubuntu ('sync; reboot'), check it comes back, then reboot-to bootloader + 'fastboot getvar all', then boot Android once. Only then run: create";;
create)
  [ "$NENT" -ge 33 ] || die "only $NENT entries: run grow first, reboot both systems, then create"
  [ "$(getkv exists)" = 0 ] || die "a partition named $NAME already exists"
  need_backup; eng plan | sed -n '/raw GPT edit/,$p'
  S=$(getkv start); E=$(getkv end)
  if { case "$YES" in 1) false;; *) true;; esac; }; then printf 'This writes the partition table: new partition %s, sectors %s..%s (%s MiB). Backup: %s\nType CREATE to continue: ' "$NAME" "$S" "$E" $(( (E - S + 1) * SS / 1048576 )) "$BKDIR"; read -r a; [ "$a" = CREATE ] || die cancelled; fi
  V0=$(rows | md5sum); sg_ok || echo "NOTE: sgdisk -v not clean before the edit"
  udev_stop; eng create || die "raw edit failed; restore with: sh $BKDIR/restore.sh $NODE"; sync
  KV=$(kv); [ "$(getkv exists)" = 1 ] || die "new entry missing after write; restore with: sh $BKDIR/restore.sh $NODE"
  [ "$(getkv last)" = "$LAST" ] && [ "$(getkv first)" = "$FIRST" ] || die "usable range changed; restore with: sh $BKDIR/restore.sh $NODE"
  [ "$(rows | head -n -1 | md5sum)" = "$V0" ] || { echo "(row comparison:)"; rows | tail -3; die "existing partition rows changed; restore with: sh $BKDIR/restore.sh $NODE"; }
  sg_ok || die "sgdisk -v reports problems; restore with: sh $BKDIR/restore.sh $NODE"
  rows | tail -3
  record_state create
  if [ -z "${SP_NOSYS:-}" ]; then
    IDX=$(rows | awk -v n="$NAME" '$7==n{print $1}')
    partx -a --nr "$IDX:$IDX" "$NODE" 2>&1 || echo "partx could not add the partition live; a reboot will make it appear"
    udev_start
    udevadm trigger --action=add "/sys/block/sda/sda$IDX" 2>/dev/null || true; udevadm settle -t 10 2>/dev/null || true
    sleep 1; ls -l /dev/sda"$IDX" 2>&1 || true
  else udev_start; fi
  echo "CREATED partition $NAME. Next: format";;
format)
  [ "$(getkv exists)" = 1 ] || die "no partition named $NAME in the GPT yet (run create)"
  [ -z "${SP_NOSYS:-}" ] || die "format needs the real phone"
  PN=""; CNT=0
  for s in /sys/block/sda/sda*; do [ "$(sed -n 's/^PARTNAME=//p' "$s/uevent")" = "$NAME" ] && { PN=${s##*/}; CNT=$((CNT+1)); }; done
  [ "$CNT" = 1 ] || die "kernel sees $CNT partitions named $NAME (need exactly 1; reboot if partx failed)"
  DEV=/dev/$PN
  if { [ -b "$DEV"  ]; [ $? -ne 0 ]; }; then mknod "$DEV" b "$(sed -n 's/^MAJOR=//p' /sys/block/sda/"$PN"/uevent)" "$(sed -n 's/^MINOR=//p' /sys/block/sda/"$PN"/uevent)"; fi
  # sysfs geometry (512-byte units) must match the GPT entry
  S=$(getkv start); E=$(getkv end)
  [ "$(cat /sys/block/sda/"$PN"/start)" = $((S * SS / 512)) ] && [ "$(cat /sys/block/sda/"$PN"/size)" = $(( (E - S + 1) * SS / 512 )) ] || die "kernel geometry of $PN does not match the GPT entry"
  case $PN in sda31|sda32) die "refusing: $PN is Android userdata / Ubuntu root";; esac
  [ "$(sed -n 's/^PARTNAME=//p' /sys/block/sda/sda31/uevent)" = userdata ] || die "sda31 is not userdata: unexpected layout"
  [ "$(sed -n 's/^PARTNAME=//p' /sys/block/sda/sda32/uevent)" = ubuntu ] || die "sda32 is not ubuntu: unexpected layout"
  findmnt -S "$DEV" >/dev/null 2>&1 && die "$DEV is mounted: umount it first (and it already has a file system?)"
  for t in blkid mkfs.ext4 setfacl dumpe2fs; do command -v "$t" >/dev/null || die "need $t"; done
  SIG=$(blkid -p "$DEV" 2>/dev/null || true)
  if [ -n "$SIG" ]; then
    if [ "$WIPE" = 1 ]; then echo "existing signature: $SIG (wiping, --wipe)"; wipefs -a "$DEV" >/dev/null; else die "$DEV already has a signature: $SIG  (re-run with --wipe only if you are sure it is empty of value)"; fi
  fi
  [ -n "$UIDS" ] || UIDS=$(getent passwd 1000 | cut -d: -f3 || true); [ -n "$UIDS" ] || UIDS=1000
  echo "will format $DEV ($(( $(cat /sys/block/sda/"$PN"/size) / 2048 )) MiB) as ext4, label $LABEL; Ubuntu uids with access:$UIDS; Android group 1023 (media_rw)"
  if { case "$YES" in 1) false;; *) true;; esac; }; then printf 'Type FORMAT to continue: '; read -r a; [ "$a" = FORMAT ] || die cancelled; fi
  blockdev --setrw "$DEV" || true
  [ "$(blockdev --getro "$DEV")" = 0 ] || die "$DEV is still read-only"
  MK="mkfs.ext4 -F -q -L $LABEL -m 0 -b 4096 -I 256 -E lazy_itable_init=1,lazy_journal_init=1,nodiscard,root_owner=0:1023"
  # conservative feature set: no orphan_file (older kernels), journal kept
  $MK -O ^orphan_file "$DEV" 2>/dev/null || $MK "$DEV" || die "mkfs failed (nothing else was touched)"
  tune2fs -c 0 -i 0 "$DEV" >/dev/null 2>&1 || true
  dumpe2fs -h "$DEV" 2>/dev/null | grep -E '^(Filesystem (volume name|features)|Block count|Block size):'
  M=/run/shared-part-fmt; mkdir -p "$M"; mount -t ext4 -o rw,noatime "$DEV" "$M"
  chown 0:1023 "$M"; chmod 2770 "$M"
  ACL="u::rwx,g::rwx,g:1023:rwx,o::---,m::rwx"; DACL=$ACL
  for u in $UIDS; do ACL="$ACL,u:$u:rwx"; DACL="$DACL,u:$u:rwx"; done
  setfacl -m "$ACL" "$M"; setfacl -d -m "$DACL" "$M"
  : > "$M/.shared-part-marker"; chown 0:1023 "$M/.shared-part-marker"; chmod 660 "$M/.shared-part-marker"
  getfacl -p "$M" 2>/dev/null | sed 's/^/  /'
  sync; umount "$M"; rmdir "$M" 2>/dev/null || true
  echo "FORMATTED $DEV (ext4, $LABEL). Next: shared-part-ubuntu.sh install, then the Android script.";;
*) sed -n '2,16p' "$0"; exit 2;;
esac
