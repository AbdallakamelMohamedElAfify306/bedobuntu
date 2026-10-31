# SPDX-License-Identifier: GPL-3.0-or-later
# Phone-side Shamiko install. Run as root:
#   sh /data/local/tmp/shamiko-kit/10-install.sh
# Soft-disables Zygisk-Assistant, installs Shamiko, sets DenyList OFF,
# adds bank packages, clears their data. Does NOT touch bootloader,
# Ubuntu slot, userdata partitions, or Magisk itself.

BASE=/data/local/tmp/shamiko-kit
LOG="$BASE/install-log.txt"
exec >"$LOG" 2>&1

echo "==== SHAMIKO INSTALL $(date) ===="

TARGETS="com.htsu.hsbcpersonalbanking com.ofss.obdx.and.nbe.com.eg com.emeint.android.myservices com.egyptianbanks.instapay com.paypal.android.p2pmobile"
EXTRA="com.android.vending"

echo
echo "== Magisk / Zygisk =="
magisk -v 2>&1 || true
magisk --sqlite "REPLACE INTO settings(key,value) VALUES(\"zygisk\",1);" 2>&1 || true
magisk --sqlite "SELECT key,value FROM settings WHERE key=\"zygisk\";" 2>&1 || true

echo
echo "== Soft-disable Zygisk-Assistant (keep files; Shamiko is the hider) =="
if [ -d /data/adb/modules/zygisk-assistant ]; then
  touch /data/adb/modules/zygisk-assistant/disable
  echo "zygisk-assistant: disable flag written"
  ls -la /data/adb/modules/zygisk-assistant/disable
else
  echo "zygisk-assistant: not installed (ok)"
fi

echo
echo "== Soft-disable other known competing hiders if present =="
for m in zygisk_shamiko_old nohello; do
  if [ -d "/data/adb/modules/$m" ]; then
    touch "/data/adb/modules/$m/disable"
    echo "disabled $m"
  fi
done

echo
echo "== Install Shamiko module =="
ZIP="$BASE/Shamiko-v1.2.5-414-release.zip"
if [ -f "$ZIP" ]; then
  echo "zip present: $ZIP"
  ls -l "$ZIP"
  magisk --install-module "$ZIP" 2>&1 || true
else
  echo "ERROR: Shamiko zip missing at $ZIP"
  echo "INSTALL_FAIL"
  exit 1
fi

if [ -d /data/adb/modules/zygisk_shamiko ]; then
  echo "zygisk_shamiko module dir present"
  if [ -f /data/adb/modules/zygisk_shamiko/disable ]; then
    rm -f /data/adb/modules/zygisk_shamiko/disable
    echo "removed stale disable flag on Shamiko"
  fi
  if [ -f /data/adb/modules/zygisk_shamiko/module.prop ]; then
    cat /data/adb/modules/zygisk_shamiko/module.prop
  fi
else
  echo "WARN: /data/adb/modules/zygisk_shamiko missing after install"
  echo "If Magisk Manager is available, Modules - Install from storage - pick the zip on /sdcard/Download"
fi

echo
echo "== DenyList: Enforce OFF (required for Shamiko) =="
magisk --denylist disable 2>&1 || true
magisk --sqlite "REPLACE INTO settings(key,value) VALUES(\"denylist\",0);" 2>&1 || true
magisk --denylist status 2>&1 || true

add_pkg_all_procs() {
  pkg="$1"
  echo "---- denylist add $pkg ----"
  magisk --denylist add "$pkg" 2>&1 || true
  magisk --denylist add "$pkg" "$pkg" 2>&1 || true
  for sfx in remote webview :webview :remote :gmsclient :playcore_missing_splits_activity; do
    magisk --denylist add "$pkg" "${pkg}${sfx}" 2>&1 || true
  done
  magisk --denylist add "$pkg" "isolated" 2>&1 || true
  dumpsys package "$pkg" 2>/dev/null | tr " " "\n" | grep -E "^${pkg}|processName=|android:process=" | sed "s/.*processName=//;s/.*android:process=//;s/[\"']//g" | sort -u | while read -r proc; do
    if [ -n "$proc" ]; then
      case "$proc" in
        *"$pkg"*|isolated*|webview*)
          magisk --denylist add "$pkg" "$proc" 2>&1 || true
          ;;
      esac
    fi
  done
}

echo
echo "== Add bank packages to DenyList =="
for p in $TARGETS $EXTRA; do
  if pm path "$p" >/dev/null 2>&1; then
    add_pkg_all_procs "$p"
  else
    echo "skip missing package $p"
  fi
done

echo
echo "-- denylist after adds --"
magisk --denylist ls 2>&1 || true

echo
echo "== Do NOT enable whitelist mode (blacklist/DenyList mode is default) =="
if [ -f /data/adb/shamiko/whitelist ]; then
  rm -f /data/adb/shamiko/whitelist
  echo "removed /data/adb/shamiko/whitelist"
else
  echo "whitelist not present (good; blacklist mode)"
fi
mkdir -p /data/adb/shamiko
chmod 700 /data/adb/shamiko

echo
echo "== Clear target app data (forces fresh integrity check after reboot) =="
for p in $TARGETS; do
  if pm path "$p" >/dev/null 2>&1; then
    echo "clear $p"
    am force-stop "$p" 2>/dev/null || true
    pm clear "$p" 2>&1 || true
  fi
done
am force-stop com.android.vending 2>/dev/null || true
pm clear com.android.vending 2>&1 || true
am force-stop com.google.android.gms 2>/dev/null || true
am force-stop com.google.android.gms.unstable 2>/dev/null || true
for d in /data/data/com.google.android.gms/app_dg_cache /data/data/com.google.android.gms/app_dg_cache_* /data/data/com.google.android.gms/databases/dg.db*; do
  if [ -e "$d" ]; then
    rm -rf "$d" 2>/dev/null && echo "removed $d" || true
  fi
done

echo
echo "== Modules snapshot =="
ls -la /data/adb/modules 2>&1 || true
for m in zygisk_shamiko zygisk-assistant playintegrityfix; do
  if [ -d "/data/adb/modules/$m" ]; then
    if [ -f "/data/adb/modules/$m/disable" ]; then
      echo "STATUS $m DISABLED"
    else
      echo "STATUS $m active"
    fi
  else
    echo "STATUS $m MISSING"
  fi
done

echo
echo "== Manual notes =="
echo "1) Magisk Settings: Zygisk ON, Enforce DenyList OFF"
echo "2) Configure DenyList: bank apps with ALL processes ticked"
echo "3) Developer options OFF after you finish adb (Egyptian banks check this)"
echo "4) Magisk 31.1 has no Hide Magisk app; optional: uninstall Magisk Manager APK only after verify"
echo "LIMIT: Shamiko hides Magisk mounts/props from DenyList apps. It does NOT spoof locked bootloader / Strong integrity."

echo
echo "==== INSTALL DONE $(date) ===="
echo "REBOOT_REQUIRED"
echo "INSTALL_OK"
