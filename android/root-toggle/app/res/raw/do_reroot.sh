# SPDX-License-Identifier: GPL-3.0-or-later
exec 2>&1
echo "RootToggle reroot wrapper start"
if [ -f /data/adb/roottoggle/reroot.sh ]; then
  sh /data/adb/roottoggle/reroot.sh
  ec=$?
  echo "exit=$ec"
  exit $ec
fi
if [ -f /sdcard/roottoggle/reroot.sh ]; then
  sh /sdcard/roottoggle/reroot.sh
  ec=$?
  echo "exit=$ec"
  exit $ec
fi
echo "STOP: scripts not installed. Run Mac setup first."
exit 99
