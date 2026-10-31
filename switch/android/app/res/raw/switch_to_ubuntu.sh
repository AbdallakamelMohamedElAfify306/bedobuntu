# SPDX-License-Identifier: GPL-3.0-or-later
# Runs as root (via Magisk su). Placeholders are filled in by MainActivity.
exec 2>&1
LIBBC='@LIBBC@'
DRY=@DRY@
B=
for c in "$LIBBC" /data/adb/magisk/bootctl /system/bin/bootctl; do
  if [ -x "$c" ] && "$c" hal-info >/dev/null 2>&1; then B="$c"; break; fi
done
[ -n "$B" ] || { echo "ERR 11: no working bootctl found"; exit 11; }
echo "bootctl: $B"
"$B" hal-info
CUR=$("$B" get-current-slot)
echo "running slot: $CUR  (0 = a = Android)"
[ "$CUR" = 0 ] || { echo "ERR 13: this is not Android slot a, refusing"; exit 13; }
if [ -e /dev/block/by-name/ubuntu ] || grep -qs 'PARTNAME=ubuntu' /sys/block/sda/*/uevent; then
  echo "ubuntu partition: present"
else
  echo "ERR 16: no partition named ubuntu, refusing"; exit 16
fi
echo "slot b bootable (1 = yes): $("$B" is-slot-bootable 1)"
"$B" is-slot-bootable 1 >/dev/null 2>&1 || { echo "ERR 17: slot b is marked unbootable, refusing"; exit 17; }
echo "active slot before: $("$B" get-active-boot-slot)"
if [ "$DRY" = 1 ]; then echo "TEST OK: nothing was changed"; exit 0; fi
"$B" set-active-boot-slot 1 || { echo "ERR 14: set-active-boot-slot failed"; exit 14; }
A=$("$B" get-active-boot-slot)
echo "active slot after: $A"
if { case "$A" in 1) false;; *) true;; esac; }; then
  echo "ERR 15: read-back is not 1, putting slot a back"
  "$B" set-active-boot-slot 0
  exit 15
fi
echo "OK: next boot = slot b (Ubuntu). Rebooting now"
sync
sleep 2
reboot || svc power reboot
exit 0
