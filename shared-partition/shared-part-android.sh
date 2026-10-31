# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash shared-part-android.sh
# shared-part-android.sh  -  runs ON ANDROID as root (Magisk). POSIX sh (toybox / mksh / busybox ash).
# Mounts the ext4 partition named "shared" (label SHARED) and makes it visible as the folder
#   /sdcard/Shared   (= /storage/emulated/0/Shared = /data/media/0/Shared)
# It also works as the Magisk boot script: install copies it to /data/adb/service.d/shared-part.sh.
#
#   install      copy to /data/adb/service.d/shared-part.sh (chmod 755) and run it now in the background
#   once         do everything once in the foreground, print each step (use this to test)
#   run          (boot mode, used by service.d) wait for unlock, mount, keep watching
#   status       read-only: what is mounted, is it visible to the FUSE view, last log lines
#   diag         read-only: GPT entry count, free sectors, partitions (no python needed)
#   umount       unmount the bind + the partition (nothing is deleted)
#   uninstall    umount, remove the service.d script, remove the (empty) mount folder
# Never writes to any partition except through the normal ext4 mount of the partition named shared, and refuses
# to mount anything whose ext4 label is not SHARED.

PATH=/system/bin:/system/xbin:/data/adb/magisk:$PATH
export PATH
BASE=/data/adb/shared-part
MNT=$BASE/mnt
TARGET=/data/media/0/Shared
FUSEVIEW=/mnt/user/0/emulated/0/Shared
LOG=$BASE/log
PARTNAME=shared
LABEL=SHARED
CTX=u:object_r:media_rw_data_file:s0
MARKER=.shared-part-marker
DST=/data/adb/service.d/shared-part.sh
OPTS="rw,noatime,nosuid,nodev,noexec,context=$CTX"
SELF=$0

mkdir -p "$BASE" 2>/dev/null
chmod 700 "$BASE" 2>/dev/null

say() { echo "$*"; echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }
quiet() { echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }
is_mounted() { grep -q " $1 " /proc/mounts 2>/dev/null; }

# ---- find the partition by its GPT name (kernel exports PARTNAME in uevent); exactly one must match ----
find_dev() {
  DEV=""; DEVNAME=""; n=0
  for u in /sys/class/block/sd*/uevent; do
    [ -r "$u" ] || continue
    if grep -qx "PARTNAME=$PARTNAME" "$u" 2>/dev/null; then
      d=${u%/uevent}; DEVNAME=${d##*/}; n=$((n + 1))
      MAJ=$(sed -n 's/^MAJOR=//p' "$u"); MIN=$(sed -n 's/^MINOR=//p' "$u")
    fi
  done
  [ "$n" = 1 ] || { NPART=$n; return 1; }
  case $DEVNAME in sda31 | sda32) say "REFUSE: $DEVNAME is userdata/ubuntu"; return 1 ;; esac
  DEV=/dev/block/$DEVNAME
  [ -b "$DEV" ] || mknod "$DEV" b "$MAJ" "$MIN" 2>/dev/null
  [ -b "$DEV" ] || { say "no block node $DEV"; return 1; }
  return 0
}

# ---- the ext4 superblock must say: magic EF53 at 1080, volume label SHARED at 1144 ----
fs_ok() {
  magic=$(dd if="$DEV" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ "$magic" = 53ef ] || { say "REFUSE: $DEV has no ext4 superblock (magic=$magic): run the Ubuntu 'format' step first"; return 1; }
  lbl=$(dd if="$DEV" bs=1 skip=1144 count=16 2>/dev/null | tr -d '\000')
  [ "$lbl" = "$LABEL" ] || { say "REFUSE: $DEV ext4 label is '$lbl', expected $LABEL"; return 1; }
  return 0
}

wait_unlocked() {
  # /data/media/0 file names are encrypted until the user unlocks the phone once after boot
  until [ "$(getprop sys.boot_completed)" = 1 ] && [ -d /data/media/0/Android ]; do sleep 5; done
}

mount_part() {
  is_mounted "$MNT" && return 0
  mkdir -p "$MNT"
  # Android marks unknown partitions read-only at the block layer; allow writes on THIS partition only
  blockdev --setrw "$DEV" 2>>"$LOG" || /data/adb/magisk/busybox blockdev --setrw "$DEV" 2>>"$LOG"
  mount -t ext4 -o "$OPTS" "$DEV" "$MNT" 2>>"$LOG"
  if [ $? -ne 0 ]; then
    say "mount with context= failed; retrying plain (labels of files made on Ubuntu may then be wrong)"
    mount -t ext4 -o rw,noatime,nosuid,nodev,noexec "$DEV" "$MNT" 2>>"$LOG" || { say "MOUNT FAILED: $(dmesg 2>/dev/null | tail -3)"; return 1; }
    chcon "$CTX" "$MNT" 2>/dev/null
  fi
  # files written by Ubuntu carry no SELinux label; give them the Android storage label
  chcon -R "$CTX" "$MNT" 2>>"$LOG"
  say "mounted $DEV at $MNT"
  return 0
}

bind_target() {
  is_mounted "$TARGET" && return 0
  mkdir -p "$TARGET" || { say "cannot create $TARGET"; return 1; }
  if [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
    say "REFUSE: $TARGET already holds files; move them away (they would be hidden by the mount)"; return 1
  fi
  chown 1023:1023 "$TARGET"; chmod 2770 "$TARGET"; chcon "$CTX" "$TARGET" 2>/dev/null
  mount -o bind "$MNT" "$TARGET" 2>>"$LOG" || { say "bind mount failed"; return 1; }
  say "bound $MNT -> $TARGET"
  return 0
}

ensure_marker() {
  [ -e "$MNT/$MARKER" ] || { : > "$MNT/$MARKER"; chown 1023:1023 "$MNT/$MARKER"; chmod 660 "$MNT/$MARKER"; }
}

# best effort: if root cannot even stat the FUSE root, assume it is fine
visible() { [ -d /mnt/user/0/emulated/0/Android ] || return 0; [ -e "$FUSEVIEW/$MARKER" ]; }

# fallback: put the same mount into MediaProvider's private mount namespace (what its FUSE daemon reads from)
mp_bind() {
  pid=""
  for pn in com.google.android.providers.media.module com.android.providers.media.module; do
    pid=$(pidof "$pn" 2>/dev/null | cut -d' ' -f1)
    [ -n "$pid" ] && break
  done
  [ -n "$pid" ] || { quiet "MediaProvider not running"; return 1; }
  NSE=nsenter; command -v nsenter >/dev/null 2>&1 || NSE="/data/adb/magisk/busybox nsenter"
  $NSE -t "$pid" -m -- sh -c "grep -q ' /storage/emulated/0/Shared ' /proc/mounts || { mkdir -p /storage/emulated/0/Shared && mount -t ext4 -o $OPTS $DEV /storage/emulated/0/Shared; }" 2>>"$LOG"
  rc=$?
  say "mounted inside MediaProvider namespace (pid $pid), rc=$rc"
  return $rc
}

scan_media() {
  if content call --uri content://media/ --method scan_volume --arg external_primary >/dev/null 2>&1; then
    quiet "media scan requested"
  else
    quiet "media scan call not accepted (files still show in Files; Gallery picks them up later)"
  fi
}

ensure_all() {
  find_dev || { [ "${NPART:-0}" = 0 ] && say "no partition named $PARTNAME yet (nothing to do)"; return 2; }
  fs_ok || return 2
  mount_part || return 1
  ensure_marker
  bind_target || return 1
  visible
  if [ $? -ne 0 ]; then
    sleep 2
    visible || { mp_bind; sleep 1; }
  fi
  if visible; then return 0; fi
  say "WARNING: mounted, but $FUSEVIEW is not visible through the FUSE view yet"
  return 1
}

do_umount() {
  pid=$(pidof com.google.android.providers.media.module com.android.providers.media.module 2>/dev/null | cut -d' ' -f1)
  [ -n "$pid" ] && nsenter -t "$pid" -m -- umount -l /storage/emulated/0/Shared 2>/dev/null
  is_mounted "$TARGET" && { umount "$TARGET" 2>/dev/null || umount -l "$TARGET"; }
  sync
  is_mounted "$MNT" && { umount "$MNT" 2>/dev/null || umount -l "$MNT"; }
  quiet "unmounted"
}

# Magisk runs service.d scripts with no argument: default to boot mode
[ -z "$1" ] && set -- run

case "$1" in
install)
  [ "$(id -u)" = 0 ] || { echo "run as root: su"; exit 1; }
  mkdir -p /data/adb/service.d
  cp "$SELF" "$DST"
  if [ $? -ne 0 ]; then echo "copy failed"; exit 1; fi
  chmod 755 "$DST"
  echo "installed $DST"
  ( setsid sh "$DST" run >/dev/null 2>&1 & )
  echo "started in the background; check with: sh $DST status"
  ;;
once)
  wait_unlocked
  ensure_all; rc=$?
  [ "$rc" = 0 ] && { say "OK: /sdcard/Shared is live"; scan_media; }
  exit $rc
  ;;
run)
  # boot mode: never blocks Magisk, never loops fast, exits when there is no such partition
  LOCK=$BASE/lock
  mkdir "$LOCK" 2>/dev/null
  if [ $? -ne 0 ]; then
    oldpid=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$oldpid" ] && [ -d "/proc/$oldpid" ]; then exit 0; fi
    rm -rf "$LOCK"; mkdir "$LOCK" || exit 1
  fi
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
  [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ] && mv "$LOG" "$LOG.old"
  quiet "run: start (pid $$)"
  wait_unlocked
  first=1; t=0
  while :; do
    ensure_all; rc=$?
    [ "$rc" = 2 ] && { quiet "run: nothing to do, exiting"; exit 0; }
    if [ "$rc" = 0 ] && [ "$first" = 1 ]; then first=0; say "OK: /sdcard/Shared is live"; scan_media; fi
    t=$((t + 1))
    if [ "$t" -gt 20 ]; then sleep 300; else sleep 20; fi
  done
  ;;
status)
  find_dev && echo "partition: $DEV ($DEVNAME)" || echo "partition named $PARTNAME: not found/ambiguous"
  [ -n "$DEV" ] && { fs_ok && echo "ext4 label OK ($LABEL)"; }
  is_mounted "$MNT" && echo "mounted: $MNT" || echo "NOT mounted: $MNT"
  is_mounted "$TARGET" && echo "mounted: $TARGET" || echo "NOT mounted: $TARGET"
  visible && echo "visible in the FUSE view ($FUSEVIEW): YES" || echo "visible in the FUSE view ($FUSEVIEW): no"
  df -h "$MNT" 2>/dev/null | tail -1
  echo "--- last log lines ($LOG)"; tail -8 "$LOG" 2>/dev/null
  ;;
diag)
  # NOTE: Android's sh (mksh) does 32-bit arithmetic: never multiply a big LBA by the sector size.
  # All values below are converted by small factors only (LBA count x 8 stays under 2^31).
  D=${SP_DISK:-/dev/block/sda}
  SY=${SP_SYS:-/sys}
  if { [ -b "$D"  ]; [ $? -ne 0 ]; } && [ -z "$SP_DISK" ]; then echo "no $D"; exit 1; fi
  SS=$(cat "$SY/block/sda/queue/logical_block_size")
  R=$((SS / 512)); EPS=$((SS / 128)); AL=$((1048576 / SS))
  hdr32() { dd if="$D" bs="$SS" skip="$1" count=1 2>/dev/null | od -An -tu4 -j"$2" -N4 | tr -d ' \n'; }
  zero_after() { dd if="$D" bs=128 skip=$(($1 * EPS + $2)) count=1 2>/dev/null | od -An -v -tx1 | tr -d ' 0\n'; }
  SIG=$(dd if="$D" bs="$SS" skip=1 count=1 2>/dev/null | dd bs=1 count=8 2>/dev/null)
  N=$(hdr32 1 80); ESZ=$(hdr32 1 84); FIRST=$(hdr32 1 40); LAST=$(hdr32 1 48); ALT=$(hdr32 1 32); ELBA=$(hdr32 1 72)
  [ "$SIG" = "EFI PART" ] && [ -n "$N" ] && [ -n "$ALT" ] || { echo "no GPT header at LBA 1 (signature '$SIG')"; exit 1; }
  AELBA=$(hdr32 "$ALT" 72); AN=$(hdr32 "$ALT" 80)
  CAPP=$(((FIRST - ELBA) * EPS)); CAPA=$(((ALT - AELBA) * EPS))
  ZP=$(zero_after "$ELBA" "$N"); ZA=$(zero_after "$AELBA" "$N")
  MAX512=0; HAVE_SHARED=0; HAVE_UD=0; HAVE_UB=0
  echo "--- partitions (start/size from sysfs are in 512-byte units; LBA = start / $R)"
  for u in "$SY"/class/block/sda[0-9]*; do
    [ -r "$u/start" ] || continue
    s=$(cat "$u/start"); z=$(cat "$u/size"); e=$((s + z - 1)); nm=$(sed -n 's/^PARTNAME=//p' "$u/uevent")
    [ "$e" -gt "$MAX512" ] && MAX512=$e
    case $nm in shared) HAVE_SHARED=1 ;; userdata) HAVE_UD=1 ;; ubuntu) HAVE_UB=1 ;; esac
    printf '%s name=%s start512=%s sizeMiB=%s LBA %s..%s\n' "${u##*/}" "$nm" "$s" $((z / 2048)) $((s / R)) $(((e + 1) / R - 1))
  done
  HIGH=$(((MAX512 + 1) / R - 1))
  TAILMIB=$(((LAST - HIGH) / AL))
  ST=$((((HIGH + 1 + AL - 1) / AL) * AL + 16 * AL)); EN=$((((LAST + 1) / AL) * AL - 1)); PMIB=$(((EN - ST + 1) / AL))
  OK=1
  [ "$N" -le 32 ] && [ "$CAPP" -ge 33 ] && [ "$CAPA" -ge 33 ] && [ -z "$ZP" ] && [ -z "$ZA" ] || OK=0
  [ "$HAVE_UD" = 1 ] && [ "$HAVE_UB" = 1 ] && [ "$HAVE_SHARED" = 0 ] && [ "$PMIB" -ge 10240 ] && [ "$ESZ" = 128 ] && [ "$AN" = "$N" ] || OK=0
  echo "================ SUMMARY (Android view) ================"
  echo "sector size $SS B (logical_block_size) | GPT $SIG | entries $N (backup copy says $AN) | entry size $ESZ"
  echo "array room: primary $CAPP entries, backup $CAPA entries (need 33)"
  echo "usable LBA $FIRST..$LAST | backup header LBA $ALT | array LBA primary $ELBA backup $AELBA"
  echo "bytes after array zero: primary=$([ -z "$ZP" ] && echo yes || echo NO) backup=$([ -z "$ZA" ] && echo yes || echo NO)"
  echo "userdata=$HAVE_UD ubuntu=$HAVE_UB shared-exists=$HAVE_SHARED"
  if [ "$HAVE_SHARED" = 1 ]; then echo "highest used LBA $HIGH (shared already created)"
  else echo "highest used LBA $HIGH | free tail $TAILMIB MiB | room for shared: LBA $ST..$EN = $PMIB MiB"; fi
  if [ "$OK" = 1 ]; then echo "VERDICT: READY (33rd entry fits, tail free)"
  elif [ "$HAVE_SHARED" = 1 ] || [ "$N" -ge 33 ]; then echo "VERDICT: ALREADY has shared / 33 entries"
  else echo "VERDICT: NOT READY - send this screen"; fi
  ;;
umount)
  do_umount; echo "done"
  ;;
uninstall)
  do_umount
  rm -f "$DST"
  rmdir "$TARGET" 2>/dev/null
  rmdir "$MNT" 2>/dev/null
  echo "uninstalled (the partition and its files are untouched; log kept in $LOG)"
  ;;
*)
  sed -n '2,15p' "$0"; exit 2
  ;;
esac
