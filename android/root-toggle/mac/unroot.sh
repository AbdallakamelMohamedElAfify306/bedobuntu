# SPDX-License-Identifier: GPL-3.0-or-later
# Optional Mac-side trigger for hard unroot (same as the phone icon).
# Usage: bash $HOME/cheetah-dual/root-toggle/mac/unroot.sh

set -e
if adb get-state >/dev/null 2>&1; then
  :
else
  echo "STOP: no adb device"
  exit 1
fi
echo "running phone unroot.sh (will reboot)"
adb shell su -c "sh /data/adb/roottoggle/unroot.sh"
