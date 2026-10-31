# SPDX-License-Identifier: GPL-3.0-or-later
# One-time Mac setup for root-toggle on the Pixel 7 Pro.
# Usage: bash $HOME/cheetah-dual/root-toggle/mac/setup.sh
# Needs: adb, phone on Android slot a, USB debugging, Magisk su granted to Shell.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOCK="${STOCK:-$HOME/cheetah-dual/root/init_boot_stock.img}"
PHONE_SD=/sdcard/roottoggle
PHONE_ADB=/data/adb/roottoggle

echo "ROOT=$ROOT"
echo "STOCK=$STOCK"

if adb get-state >/dev/null 2>&1; then
  :
else
  echo "STOP: no adb device"
  exit 1
fi

if adb shell su -c id 2>/dev/null | grep -q uid=0; then
  :
else
  echo "STOP: su not working. Open Magisk - Superuser - enable Shell"
  exit 1
fi

slot=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
echo "slot=$slot"
if [ "$slot" = "_a" ]; then
  :
else
  echo "STOP: phone must be on slot a (Android). Got $slot"
  exit 1
fi

if [ -f "$STOCK" ]; then
  sz=$(wc -c < "$STOCK" | tr -d ' ')
  echo "stock size=$sz"
  if [ "$sz" = "8388608" ]; then
    :
  else
    echo "WARN: stock size is not 8388608 - continue only if you know this is correct for your build"
  fi
else
  echo "STOP: missing $STOCK"
  echo "Put the stock init_boot.img of YOUR build there (from the factory zip)."
  exit 1
fi

echo "creating dirs on phone"
adb shell "mkdir -p $PHONE_SD"
adb shell su -c "mkdir -p $PHONE_ADB"

echo "pushing stock init_boot"
adb push "$STOCK" "$PHONE_SD/init_boot_stock.img"
adb shell su -c "cp -f $PHONE_SD/init_boot_stock.img $PHONE_ADB/init_boot_stock.img"

echo "dumping current (patched) init_boot_a from phone"
adb shell su -c "dd if=/dev/block/by-name/init_boot_a of=$PHONE_SD/init_boot_patched.img bs=4096"
adb shell su -c "cp -f $PHONE_SD/init_boot_patched.img $PHONE_ADB/init_boot_patched.img"
mkdir -p "$HOME/cheetah-dual/root-toggle-images"
adb pull "$PHONE_SD/init_boot_patched.img" "$HOME/cheetah-dual/root-toggle-images/init_boot_patched.img"
cp -f "$STOCK" "$HOME/cheetah-dual/root-toggle-images/init_boot_stock.img"
echo "saved Mac copies in $HOME/cheetah-dual/root-toggle-images/"

echo "pushing scripts"
for f in common.sh unroot.sh reroot.sh status.sh soft-hide.sh soft-show.sh; do
  adb push "$ROOT/phone/$f" "$PHONE_SD/$f" >/dev/null
  adb shell su -c "cp -f $PHONE_SD/$f $PHONE_ADB/$f"
done
adb shell su -c "chmod 755 $PHONE_ADB/*.sh"

echo "state=rooted" 
adb shell "echo rooted > $PHONE_SD/state"
adb shell su -c "echo rooted > $PHONE_ADB/state"

if [ -f "$ROOT/android/RootToggle.apk" ]; then
  echo "installing RootToggle.apk"
  adb install -r "$ROOT/android/RootToggle.apk" || adb install "$ROOT/android/RootToggle.apk"
else
  echo "WARN: RootToggle.apk missing - build it first"
fi

echo ""
echo "==== SETUP-OK ===="
echo "Next on phone:"
echo "  1. Open Magisk - Superuser - enable Root Toggle (and Bank Mode / Root Mode if listed)"
echo "  2. Home screen should show icons: وضع البنك  and  وضع الروت"
echo "  3. Tap وضع البنك to unroot (reboots). Banking apps may still fail if they check the unlocked bootloader."
echo "  4. To re-root: connect Mac, run:  bash $HOME/cheetah-dual/root-toggle/mac/reroot.sh"
echo "Never lock the bootloader. Never flash slot b. Ubuntu and shared partition are untouched."
