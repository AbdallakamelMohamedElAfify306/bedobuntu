# SPDX-License-Identifier: GPL-3.0-or-later
exec 2>&1
echo "RootToggle unroot wrapper start"
if [ -f /data/adb/roottoggle/unroot.sh ]; then
  sh /data/adb/roottoggle/unroot.sh
  ec=$?
  echo "exit=$ec"
  exit $ec
fi
if [ -f /sdcard/roottoggle/unroot.sh ]; then
  sh /sdcard/roottoggle/unroot.sh
  ec=$?
  echo "exit=$ec"
  exit $ec
fi
echo "STOP: scripts not installed. Run Mac setup first:"
echo "  bash $HOME/cheetah-dual/root-toggle/mac/setup.sh"
exit 99
