# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash shared-part-rollback.sh
# shared-part-rollback.sh  -  runs ON UBUNTU (phone) as root. Undoes the "shared" partition work.
#   status                          read-only
#   soft                            only unmount + remove the Ubuntu auto-mount (service/udev rule/links). Partition stays.
#   gpt [--to original|empty33] [--backup DIR] [--yes]
#                                   put the GPT back from a backup taken by shared-part-create.sh:
#                                     original = the 32-entry table from before 'grow'  (default; partition 33 disappears)
#                                     empty33  = the 33-entry table from before 'create' (entry 33 empty)
#                                   Refuses unless the GPT is still exactly what the create script last wrote, and the
#                                   partition is unmounted. Writes only the first/last GPT sectors with dd; no partition
#                                   data is touched. Afterwards reboot.
# Android side:  sh /data/adb/service.d/shared-part.sh uninstall     (run it in Android, as root)
# Data note: 'gpt' removes the partition from the table, it does NOT erase its data; re-creating the same range later
# brings the files back (only if nothing wrote there meanwhile).
set -euo pipefail
export LC_ALL=C
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
STATE=${SP_STATE:-/root/shared-part-state}
cmd=${1:-status}; shift || true
TO=original; BK=""; YES=0
while [ $# -gt 0 ]; do case $1 in --to) TO=$2; shift 2;; --backup) BK=$2; shift 2;; --yes) YES=1; shift;; *) shift;; esac; done
die() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || [ -n "${SP_DISK:-}" ] || die "run as root"
HERE=$(cd "$(dirname "$0")" && pwd)

NODE=""; TMPNODE=""
cleanup() { [ -z "$TMPNODE" ] || rm -f "$TMPNODE"; }
trap cleanup EXIT
mknode() {
  if [ -n "${SP_DISK:-}" ]; then NODE=$SP_DISK; SS=${SP_SS:-4096}; return; fi
  [ -r /sys/block/sda/dev ] || die "/sys/block/sda not found"
  SS=$(cat /sys/block/sda/queue/logical_block_size)
  TMPNODE=/run/shared-part-sda.$$; mknod "$TMPNODE" b $(cut -d: -f1 /sys/block/sda/dev) $(cut -d: -f2 /sys/block/sda/dev); NODE=$TMPNODE
}

case $cmd in
status)
  echo "backups:"; ls -d "$STATE"/backup-* 2>/dev/null || echo "  none"
  echo "log:"; cat "$STATE/log" 2>/dev/null || echo "  (empty)"
  [ -x /usr/local/sbin/shared-mount ] && /usr/local/sbin/shared-mount status || echo "Ubuntu auto-mount not installed"
  ;;
soft)
  if [ -x "$HERE/shared-part-ubuntu.sh" ]; then "$HERE/shared-part-ubuntu.sh" uninstall
  else
    systemctl disable --now shared-part.service 2>/dev/null || true
    rm -f /etc/systemd/system/shared-part.service /usr/local/sbin/shared-mount /etc/udev/rules.d/99-shared-part.rules
    systemctl daemon-reload; udevadm control --reload 2>/dev/null || true
  fi
  echo "soft rollback done. Android side: in Android run  su -M -c 'sh /data/adb/service.d/shared-part.sh uninstall'"
  ;;
gpt)
  case $TO in original) PAT="backup-pre-grow-*";; empty33) PAT="backup-pre-create-*";; *) die "--to must be original or empty33";; esac
  D=$BK
  # shellcheck disable=SC2086,SC2012
  [ -n "$D" ] || D=$(ls -d "$STATE"/$PAT 2>/dev/null | tail -1)
  [ -n "$D" ] && [ -s "$D/SHA256SUMS" ] || die "no backup matching $PAT in $STATE"
  (cd "$D" && sha256sum -c --quiet SHA256SUMS) || die "backup $D is damaged"
  mknode
  # 1) unmounted and not in use
  if findmnt -n /mnt/shared >/dev/null 2>&1; then die "/mnt/shared is mounted: run  systemctl stop shared-part.service  first"; fi
  for s in /sys/block/sda/sda*; do
    [ "$(sed -n 's/^PARTNAME=//p' "$s/uevent" 2>/dev/null)" = shared ] && { findmnt -S "/dev/${s##*/}" >/dev/null 2>&1 && die "/dev/${s##*/} is mounted"; SHAREDPN=${s##*/}; }
  done
  # 2) the GPT must still be what the create script wrote
  PB=$(stat -c %s "$D/primary.raw"); BB=$(stat -c %s "$D/backup.raw")
  CUR=$(dd if="$NODE" bs="$SS" count=$((PB / SS)) status=none | sha256sum | cut -d' ' -f1)
  [ -s "$STATE/last-written.sha" ] || die "no record of the create script's last write (state dir $STATE): not restoring blindly"
  [ "$CUR" = "$(cat "$STATE/last-written.sha")" ] || die "the GPT changed since the create script last wrote it (someone else edited it): not restoring"
  echo "restoring $D  (target: $TO, whole-disk node $NODE, $((PB / SS)) front sectors + $((BB / SS)) tail sectors)"
  if { case "$YES" in 1) false;; *) true;; esac; }; then printf 'Type ROLLBACK to continue: '; read -r a; [ "$a" = ROLLBACK ] || die cancelled; fi
  sh "$D/restore.sh" "$NODE"
  # verify what is on disk now equals the backup
  dd if="$NODE" bs="$SS" count=$((PB / SS)) status=none | cmp -s - "$D/primary.raw" || die "primary GPT differs from the backup after restore."
  TOTALS=$(( $(blockdev --getsize64 "$NODE") / SS ))
  dd if="$NODE" bs="$SS" skip=$((TOTALS - BB / SS)) status=none | cmp -s - "$D/backup.raw" || die "backup GPT differs from the backup after restore."
  echo "GPT now equals the backup byte for byte."
  dd if="$NODE" bs="$SS" count=$((PB / SS)) status=none | sha256sum | cut -d' ' -f1 > "$STATE/last-written.sha"
  echo "gpt-rollback $TO $(date -Iseconds) from $D" >> "$STATE/log"
  if [ -z "${SP_DISK:-}" ] && [ -n "${SHAREDPN:-}" ]; then
    N=${SHAREDPN#sda}; partx -d --nr "$N:$N" "$NODE" 2>&1 || echo "(partx -d failed; reboot clears the stale entry)"
  fi
  echo "DONE. Reboot now ('sync; reboot'). Android's script then simply finds no partition named shared."
  ;;
*) sed -n '2,16p' "$0"; exit 2;;
esac
