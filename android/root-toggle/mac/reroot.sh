# SPDX-License-Identifier: GPL-3.0-or-later
# Re-root after hard unroot. Needs Mac + USB + fastboot.
# Usage: bash $HOME/cheetah-dual/root-toggle/mac/reroot.sh
# Prefers $HOME/cheetah-dual/root-toggle-images/init_boot_patched.img (saved by setup).

set -e
IMG="${1:-$HOME/cheetah-dual/root-toggle-images/init_boot_patched.img}"

if [ -f "$IMG" ]; then
  :
else
  echo "STOP: missing patched image at $IMG"
  echo "If the phone still has it: adb pull /sdcard/roottoggle/init_boot_patched.img $IMG"
  echo "(That pull works even without root.)"
  exit 1
fi

sz=$(wc -c < "$IMG" | tr -d ' ')
echo "patched img=$IMG size=$sz"

# Prefer pulling a fresh copy from the phone sdcard if present (works without root)
if adb get-state >/dev/null 2>&1; then
  if adb shell "test -f /sdcard/roottoggle/init_boot_patched.img" 2>/dev/null; then
    echo "refreshing patched image from phone sdcard"
    adb pull /sdcard/roottoggle/init_boot_patched.img "$IMG"
  fi
  echo "rebooting to bootloader"
  adb reboot bootloader
else
  echo "adb not in device mode - assuming phone is already in fastboot"
fi

echo "waiting for fastboot"
ok=0
i=0
while [ "$i" -lt 60 ]; do
  if fastboot devices 2>/dev/null | grep -q fastboot; then
    ok=1
    break
  fi
  sleep 1
  i=$((i + 1))
done
if [ "$ok" = "1" ]; then
  :
else
  echo "STOP: no fastboot device. Hold Vol-Down+Power to enter fastboot, then retry."
  exit 1
fi

slot=$(fastboot getvar current-slot 2>&1 | grep current-slot | awk '{print $2}' | tr -d '\r')
echo "fastboot current-slot=$slot"
if [ "$slot" = "a" ]; then
  :
else
  echo "STOP: fastboot slot is not a (got $slot). Refusing to flash."
  exit 1
fi

echo "flashing init_boot_a"
fastboot flash init_boot_a "$IMG"
echo "rebooting"
fastboot reboot
echo "REROOT-OK: phone rebooting into Magisk. Wait 1-2 minutes, then open Magisk to confirm."
