# SPDX-License-Identifier: GPL-3.0-or-later
# Usage: bash $HOME/cheetah-dual/root-toggle/mac/status.sh
set -e
adb shell su -c "sh /data/adb/roottoggle/status.sh" 2>/dev/null || adb shell "sh /sdcard/roottoggle/status.sh" 2>/dev/null || {
  echo "cannot run status (no root and scripts missing from sdcard)"
  adb shell "cat /sdcard/roottoggle/state 2>/dev/null; ls -l /sdcard/roottoggle/ 2>/dev/null; getprop ro.boot.slot_suffix; getprop ro.boot.verifiedbootstate"
}
