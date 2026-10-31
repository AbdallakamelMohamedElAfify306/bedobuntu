# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash shared-part-ubuntu.sh
# shared-part-ubuntu.sh  -  runs ON UBUNTU (phone) as root.
# Installs the auto-mount of the "shared" ext4 partition at /mnt/shared (+ ~/Shared link and a Files bookmark).
#   install [--user NAME]    install helper + systemd service + udev rule, enable, mount now
#   uninstall                stop + remove all of that (partition and files untouched)
#   status                   read-only
# The mount helper (/usr/local/sbin/shared-mount) finds the partition by its GPT name "shared", checks that the
# ext4 label is SHARED, switches ONLY that partition from read-only to read-write (the initramfs guard marks every
# non-allowlisted partition read-only on each boot; no initramfs change is needed), runs e2fsck -p if needed, mounts.
set -euo pipefail
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
cmd=${1:-status}; shift || true
USERNAME=""
while [ $# -gt 0 ]; do case $1 in --user) USERNAME=$2; shift 2;; *) shift;; esac; done
die() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root"
MNT=/mnt/shared
HELPER=/usr/local/sbin/shared-mount
UNIT=/etc/systemd/system/shared-part.service
RULE=/etc/udev/rules.d/99-shared-part.rules
[ -n "$USERNAME" ] || USERNAME=$(getent passwd 1000 | cut -d: -f1 || true)

case $cmd in
install)
  for t in dumpe2fs e2fsck blockdev mount findmnt; do command -v "$t" >/dev/null || die "missing $t"; done
  install -d -m 755 "$MNT"
  cat > "$HELPER" <<'HLP'
# run-with bash
# shared-mount start|stop|status  (installed by shared-part-ubuntu.sh)
export PATH="$PATH:/usr/sbin:/sbin"
NAME=shared; LABEL=SHARED; MNT=/mnt/shared
log() { echo "shared-mount: $*"; echo "shared-mount: $*" > /dev/kmsg 2>/dev/null || true; }
find_part() {
  PN=""; CNT=0
  for s in /sys/block/sda/sda*; do
    [ "$(sed -n 's/^PARTNAME=//p' "$s/uevent" 2>/dev/null)" = "$NAME" ] && { PN=${s##*/}; CNT=$((CNT + 1)); }
  done
  [ "$CNT" = 1 ]
}
case ${1:-status} in
start)
  findmnt -n "$MNT" >/dev/null 2>&1 && { log "already mounted"; exit 0; }
  find_part || { log "no single partition named $NAME (found $CNT): nothing to mount"; exit 0; }
  case $PN in sda31|sda32) log "REFUSE: $PN is userdata/ubuntu"; exit 1;; esac
  DEV=/dev/$PN
  [ -b "$DEV" ] || mknod "$DEV" b "$(sed -n 's/^MAJOR=//p' /sys/block/sda/$PN/uevent)" "$(sed -n 's/^MINOR=//p' /sys/block/sda/$PN/uevent)"
  [ "$(dumpe2fs -h "$DEV" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')" = "$LABEL" ] || { log "REFUSE: $DEV has no ext4 with label $LABEL (run the create script: format)"; exit 1; }
  # mounted somewhere else (e.g. by udisks)? move it to our place
  for t in $(findmnt -rn -S "$DEV" -o TARGET); do [ "$t" = "$MNT" ] || umount "$t" || true; done
  blockdev --setrw "$DEV"    # the initramfs guard left it read-only; only THIS partition is switched
  [ "$(blockdev --getro "$DEV")" = 0 ] || { log "REFUSE: $DEV stays read-only"; exit 1; }
  e2fsck -p "$DEV" >/dev/null 2>&1; rc=$?
  [ "$rc" -le 1 ] || { log "REFUSE: e2fsck -p returned $rc on $DEV; run e2fsck by hand"; exit 1; }
  mkdir -p "$MNT"
  mount -t ext4 -o rw,noatime,nosuid,nodev "$DEV" "$MNT" && log "mounted $DEV on $MNT"
  ;;
stop)
  findmnt -n "$MNT" >/dev/null 2>&1 || exit 0
  sync; umount "$MNT" && log "unmounted $MNT"
  ;;
status)
  findmnt -n "$MNT" || echo "not mounted"
  find_part && echo "partition: /dev/$PN ro=$(cat /sys/block/sda/$PN/ro)" || echo "partition named $NAME: found $CNT"
  ;;
esac
HLP
  chmod 755 "$HELPER"
  cat > "$UNIT" <<'UNITF'
[Unit]
Description=Shared ext4 partition (also used by Android) on /mnt/shared
After=local-fs.target systemd-udevd.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/shared-mount start
ExecStop=/usr/local/sbin/shared-mount stop
[Install]
WantedBy=multi-user.target
UNITF
  # keep udisks from auto-mounting it (we mount it ourselves)
  cat > "$RULE" <<'RULEF'
SUBSYSTEM=="block", ENV{ID_PART_ENTRY_NAME}=="shared", ENV{UDISKS_IGNORE}="1", ENV{UDISKS_AUTO}="0"
RULEF
  udevadm control --reload 2>/dev/null || true
  # nice names for Android's group, if the number is free
  getent group 1023 >/dev/null || groupadd -g 1023 media_rw || true
  if [ -n "$USERNAME" ] && id "$USERNAME" >/dev/null 2>&1; then
    H=$(getent passwd "$USERNAME" | cut -d: -f6)
    [ -e "$H/Shared" ] || ln -s "$MNT" "$H/Shared"
    install -d -o "$USERNAME" -g "$(id -gn "$USERNAME")" "$H/.config/gtk-3.0"
    B=$H/.config/gtk-3.0/bookmarks
    grep -q "file://$MNT" "$B" 2>/dev/null || { echo "file://$MNT Shared" >> "$B"; chown "$USERNAME" "$B"; }
    echo "linked $H/Shared and added the Files bookmark for $USERNAME"
  fi
  systemctl daemon-reload
  systemctl enable shared-part.service >/dev/null 2>&1
  systemctl restart shared-part.service || true
  "$HELPER" status
  echo "installed. It mounts at every boot."
  ;;
uninstall)
  systemctl disable --now shared-part.service 2>/dev/null || true
  rm -f "$UNIT" "$HELPER" "$RULE"
  systemctl daemon-reload; udevadm control --reload 2>/dev/null || true
  if [ -n "$USERNAME" ]; then
    H=$(getent passwd "$USERNAME" | cut -d: -f6)
    [ -L "$H/Shared" ] && rm -f "$H/Shared"
    [ -f "$H/.config/gtk-3.0/bookmarks" ] && sed -i "\#file://$MNT #d" "$H/.config/gtk-3.0/bookmarks"
  fi
  rmdir "$MNT" 2>/dev/null || true
  echo "uninstalled (partition and files untouched)"
  ;;
status)
  if [ -x "$HELPER" ]; then "$HELPER" status; else echo "not installed"; fi
  systemctl is-enabled shared-part.service 2>&1 | sed 's/^/service enabled: /' || true
  ;;
*) sed -n '2,8p' "$0"; exit 2;;
esac
