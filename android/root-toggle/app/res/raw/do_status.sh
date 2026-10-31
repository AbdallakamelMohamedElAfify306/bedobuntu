# SPDX-License-Identifier: GPL-3.0-or-later
exec 2>&1
if [ -f /data/adb/roottoggle/status.sh ]; then
  sh /data/adb/roottoggle/status.sh
  exit $?
fi
if [ -f /sdcard/roottoggle/status.sh ]; then
  sh /sdcard/roottoggle/status.sh
  exit $?
fi
echo "scripts missing"
id
getprop ro.boot.slot_suffix
getprop ro.boot.verifiedbootstate
exit 0
