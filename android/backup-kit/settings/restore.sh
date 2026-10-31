# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# shellcheck disable=SC2086,SC2012,SC2094,SC2162
# Restore ONLY the items marked SAFE, SAME DEVICE, SAME BUILD. Run as root on the phone.
#   sh restore.sh <backup-dir> <item>      items: wallpaper notification_policy wifi launcher gboard clock roles bluetooth
# Refuses to run if fingerprint differs from the one recorded in the backup.
# Not provided on purpose: raw settings_*.xml / system_users_0 (use `settings put` from settings/*.txt instead).
set -eu
B=$1; ITEM=$2
[ "$(id -u)" = 0 ] || { echo need root; exit 1; }
[ "$(getprop ro.build.fingerprint)" = "$(sed -n 2p $B/info/device.txt)" ] || { echo "build differs from backup - refusing"; exit 1; }
T="$B/raw/$ITEM.tar"; [ -f "$T" ] || { echo "no $T"; exit 1; }
case $ITEM in
  wifi)       svc wifi disable ;;
  bluetooth)  svc bluetooth disable ;;
  launcher)   am force-stop com.google.android.apps.nexuslauncher ;;
  gboard)     am force-stop com.google.android.inputmethod.latin ;;
  clock)      am force-stop com.google.android.deskclock ;;
  wallpaper|notification_policy|roles) ;;
  *) echo "item not restorable by this script"; exit 1 ;;
esac
# keep the current state so the restore itself is undoable
mkdir -p /data/local/tmp/pre-restore-$ITEM
tar -tf "$T" | while read p; do [ -e "/$p" ] && cp -a "/$p" /data/local/tmp/pre-restore-$ITEM/ 2>/dev/null; done || true
tar -xpf "$T" -C /
tar -tf "$T" | sed 's#^#/#' | while read p; do restorecon -R "$p" 2>/dev/null; done
echo "restored $ITEM. REBOOT now (wifi, bluetooth, wallpaper, notification_policy, roles are read at boot)."
