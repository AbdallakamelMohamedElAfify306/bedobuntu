# SPDX-License-Identifier: GPL-3.0-or-later
# Print current root-toggle status. Safe, read-only.

. /data/adb/roottoggle/common.sh

rt_setup_dirs

echo "==== root-toggle status ===="
echo "date=$(date)"
echo "slot=$(getprop ro.boot.slot_suffix)"
echo "build=$(getprop ro.build.id)"
echo "fingerprint=$(getprop ro.build.fingerprint)"
echo "verifiedbootstate=$(getprop ro.boot.verifiedbootstate)"
echo "flash.locked=$(getprop ro.boot.flash.locked)"
echo "vbmeta.device_state=$(getprop ro.boot.vbmeta.device_state)"
echo "debuggable=$(getprop ro.debuggable)"
echo "development_settings=$(settings get global development_settings_enabled)"
echo "adb_enabled=$(settings get global adb_enabled)"

if [ -f "$SD_DIR/state" ]; then
  echo "state_file=$(cat $SD_DIR/state)"
else
  echo "state_file=absent"
fi

if magisk -v >/dev/null 2>&1; then
  echo "magisk_ver=$(magisk -v)"
  echo "magisk_live=yes"
else
  echo "magisk_live=no"
fi

id_out=$(id 2>/dev/null || echo none)
echo "id=$id_out"

isz_a=$(blockdev --getsize64 /dev/block/by-name/init_boot_a 2>/dev/null || echo na)
echo "init_boot_a_size=$isz_a"

for f in init_boot_stock.img init_boot_patched.img; do
  if [ -f "$SD_DIR/$f" ]; then
    echo "sd_$f=$(wc -c < $SD_DIR/$f | tr -d ' ') bytes"
  else
    echo "sd_$f=missing"
  fi
done

echo "magisk_backups:"
ls -d /data/magisk_backup_* 2>/dev/null || echo "(none)"

echo "==== end ===="
