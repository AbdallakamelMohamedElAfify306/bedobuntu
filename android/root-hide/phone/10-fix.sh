# SPDX-License-Identifier: GPL-3.0-or-later
# Phone-side fix. Run as: su -c "sh /data/local/tmp/roothide-fix/10-fix.sh"
# Strategy (Magisk 31.x late 2026):
#   - Enable Zygisk
#   - Install Zygisk-Assistant (active hide)
#   - Enforce DenyList OFF (required so ZA can inject into denylist targets)
#   - Put banking apps + Play Store on DenyList (ZA target list)
#   - Do NOT put com.google.android.gms on DenyList (PIF must keep injecting)
#   - Install props spoof service.d
#   - Refresh PIF fingerprint if stale
#   - Clear target apps + Play Store + DroidGuard cache
# Does NOT disable adb (would cut the session). Does NOT uninstall apps.
# Does NOT touch partitions / bootloader / Ubuntu slot.

# set -e disabled: magisk denylist status returns non-zero when not enforced
BASE=/data/local/tmp/roothide-fix
LOG="$BASE/fix-log.txt"
exec >"$LOG" 2>&1

echo "==== ROOTHIDE FIX $(date) ===="

TARGETS="com.htsu.hsbcpersonalbanking com.ofss.obdx.and.nbe.com.eg com.emeint.android.myservices com.egyptianbanks.instapay com.payoneer.android com.paypal.android.p2pmobile"
EXTRA_DENY="com.android.vending"

echo
echo "== 1) Enable Zygisk in Magisk DB =="
magisk --sqlite "REPLACE INTO settings(key,value) VALUES(\"zygisk\",1);" 2>&1 || magisk --sqlite "INSERT INTO settings(key,value) VALUES(\"zygisk\",1);" 2>&1 || true
magisk --sqlite "SELECT key,value FROM settings WHERE key=\"zygisk\";" 2>&1 || true

echo
echo "== 2) Install Zygisk-Assistant if missing =="
ZA_ZIP="$BASE/Zygisk-Assistant-v2.1.4.zip"
if [ -d /data/adb/modules/zygisk-assistant ]; then
  echo "Zygisk-Assistant already present"
  if [ -f /data/adb/modules/zygisk-assistant/disable ]; then
    echo "re-enabling (removing disable flag)"
    rm -f /data/adb/modules/zygisk-assistant/disable
  fi
else
  if [ -f "$ZA_ZIP" ]; then
    echo "installing from $ZA_ZIP"
    magisk --install-module "$ZA_ZIP" 2>&1 || true
  else
    echo "WARN: $ZA_ZIP missing; skip ZA install"
  fi
fi
ls -la /data/adb/modules/zygisk-assistant 2>&1 || echo "ZA still missing after install attempt"

echo
echo "== 3) DenyList: enforce OFF (ZA mode), then add targets =="
# ZA / Shamiko model: apps stay on the list, Enforce must be OFF
magisk --denylist disable 2>&1 || true
# Keep sqlite denylist setting at 0 so Magisk UI matches
magisk --sqlite "REPLACE INTO settings(key,value) VALUES(\"denylist\",0);" 2>&1 || true
magisk --denylist status 2>&1 || true

add_pkg_all_procs() {
  pkg="$1"
  echo "---- denylist add $pkg ----"
  magisk --denylist add "$pkg" 2>&1 || true
  magisk --denylist add "$pkg" "$pkg" 2>&1 || true
  # Common process suffixes
  for sfx in remote webview :webview :remote :gmsclient :playcore_missing_splits_activity; do
    magisk --denylist add "$pkg" "${pkg}${sfx}" 2>&1 || true
  done
  # Isolated marker used by some Magisk UIs
  magisk --denylist add "$pkg" "isolated" 2>&1 || true
  # Discover process names from package dump
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

for p in $TARGETS $EXTRA_DENY; do
  if pm path "$p" >/dev/null 2>&1; then
    add_pkg_all_procs "$p"
  else
    echo "skip missing package $p"
  fi
done

echo
echo "-- denylist after adds --"
magisk --denylist ls 2>&1 || true
magisk --denylist status 2>&1 || true

echo
echo "== 4) Props spoof service.d =="
mkdir -p /data/adb/service.d
cp "$BASE/props-spoof.sh" /data/adb/service.d/99-props-spoof.sh
chmod 755 /data/adb/service.d/99-props-spoof.sh
# Keep shared-part.sh untouched
if [ -f /data/adb/service.d/shared-part.sh ]; then
  echo "shared-part.sh present and left untouched"
fi
ls -la /data/adb/service.d/

# Apply props once now (before reboot) so immediate tests see them
echo "applying props once now"
resetprop ro.boot.verifiedbootstate green 2>/dev/null || true
resetprop ro.boot.flash.locked 1 2>/dev/null || true
resetprop ro.boot.vbmeta.device_state locked 2>/dev/null || true
resetprop ro.debuggable 0 2>/dev/null || true
resetprop ro.secure 1 2>/dev/null || true
resetprop ro.build.tags release-keys 2>/dev/null || true
resetprop ro.build.type user 2>/dev/null || true
echo "props now:"
for k in ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.vbmeta.device_state ro.debuggable ro.secure ro.build.tags ro.build.type; do
  printf "%s=" "$k"; getprop "$k"
done

echo
echo "== 5) Refresh Play Integrity Fork fingerprint if needed =="
PIF=/data/adb/modules/playintegrityfix
if [ -d "$PIF" ]; then
  NEED_REFRESH=0
  if [ -f "$PIF/custom.pif.prop" ]; then
    # Refresh if older than 5 days, or always attempt autopif when helper exists
    AGE=$(stat -c %Y "$PIF/custom.pif.prop" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    DIFF=$((NOW - AGE))
    echo "custom.pif.prop age_sec=$DIFF"
    if [ "$DIFF" -gt 432000 ]; then
      NEED_REFRESH=1
    fi
  else
    NEED_REFRESH=1
  fi
  # Always try a refresh once during this kit run; fingerprint Canary expires ~2026-11-18
  NEED_REFRESH=1
  if [ "$NEED_REFRESH" = "1" ]; then
    if [ -f "$PIF/autopif4.sh" ]; then
      echo "running autopif4.sh --strong"
      ( cd "$PIF" && sh ./autopif4.sh --strong ) 2>&1 || ( cd "$PIF" && sh ./autopif4.sh ) 2>&1 || echo "autopif failed"
    else
      echo "autopif4.sh missing"
    fi
    if [ -f "$PIF/killpi.sh" ]; then
      echo "running killpi.sh"
      ( cd "$PIF" && sh ./killpi.sh ) 2>&1 || true
    fi
  fi
  # Install / refresh the delayed helper into service.d
  cat > /data/adb/service.d/98-pif-refresh.sh << "PIFEOF"
# Auto-refresh PIF fingerprint when missing or older than 7 days
sleep 90
F=/data/adb/modules/playintegrityfix/custom.pif.prop
AP=/data/adb/modules/playintegrityfix/autopif4.sh
KP=/data/adb/modules/playintegrityfix/killpi.sh
if [ -f "$AP" ]; then
  DO=0
  if [ -f "$F" ]; then
    :
  else
    DO=1
  fi
  if [ -f "$F" ]; then
    if [ -n "$(find "$F" -mtime +7 2>/dev/null)" ]; then
      DO=1
    fi
  fi
  if [ "$DO" = "1" ]; then
    sh "$AP" --strong 2>/dev/null || sh "$AP" 2>/dev/null || true
    if [ -f "$KP" ]; then sh "$KP" 2>/dev/null || true; fi
  fi
fi
PIFEOF
  chmod 755 /data/adb/service.d/98-pif-refresh.sh
  echo "installed 98-pif-refresh.sh"
else
  echo "WARN: playintegrityfix not installed; skip PIF refresh"
fi

echo
echo "== 6) Clear detectable Magisk APKs in Download (rename, not delete) =="
for f in /sdcard/Download/Magisk*.apk /sdcard/Download/magisk*.apk /sdcard/Download/*magisk*.apk; do
  if [ -f "$f" ]; then
    mv "$f" "${f}.hidden" 2>/dev/null && echo "renamed $f" || true
  fi
done

echo
echo "== 7) SwitchToUbuntu package (report + optional hide from launcher only) =="
SWITCH_PKGS=$(pm list packages 2>/dev/null | grep -iE "ubuntu|switchto|omarchy" | sed "s/package://")
if [ -n "$SWITCH_PKGS" ]; then
  echo "found: $SWITCH_PKGS"
  echo "NOTE: not uninstalling. Banks that enumerate packages may still see it."
  echo "Optional later: pm disable-user --user 0 <pkg>  (reversible; does not uninstall)"
else
  echo "no switch/ubuntu package name matched"
fi

echo
echo "== 8) Force-stop + clear data for target apps + Play Store =="
for p in $TARGETS com.android.vending; do
  if pm path "$p" >/dev/null 2>&1; then
    echo "clear $p"
    am force-stop "$p" 2>/dev/null || true
    pm clear "$p" 2>&1 || true
  fi
done
# DroidGuard / GMS integrity cache (do NOT full-clear GMS; just stop + clear dg cache dirs)
am force-stop com.google.android.gms 2>/dev/null || true
am force-stop com.google.android.gms.unstable 2>/dev/null || true
for d in /data/data/com.google.android.gms/app_dg_cache /data/data/com.google.android.gms/app_dg_cache_* /data/data/com.google.android.gms/databases/dg.db*; do
  if [ -e "$d" ]; then
    rm -rf "$d" 2>/dev/null && echo "removed $d" || true
  fi
done
# Also clear GSF? skip — too disruptive

echo
echo "== 9) Magisk Manager visibility =="
if pm path com.topjohnwu.magisk >/dev/null 2>&1; then
  echo "MANUAL_REQUIRED: Magisk Manager still installed."
  echo "Magisk 31.1 removed Hide the Magisk app. After reboot and verifying root still works,"
  echo "uninstall ONLY the Magisk Manager app from Settings - Apps (modules and root stay)."
else
  echo "Magisk Manager package not present (good)"
fi

echo
echo "== 10) Developer options warning =="
DEV=$(settings get global development_settings_enabled)
ADB=$(settings get global adb_enabled)
echo "development_settings_enabled=$DEV adb_enabled=$ADB"
echo "MANUAL_REQUIRED: After this script finishes and you reboot, turn OFF Developer options"
echo "in Settings (Egyptian banks NBE / Instapay often refuse when Dev options or USB debugging is on)."
echo "Do that AFTER you finish adb work, because turning it off will cut USB debugging."

echo
echo "== Summary snapshot =="
magisk -v 2>&1 || true
magisk --sqlite "SELECT key,value FROM settings" 2>&1 || true
magisk --denylist status 2>&1 || true
ls /data/adb/modules 2>&1 || true
echo
echo "==== FIX DONE $(date) ===="
echo "REBOOT_REQUIRED"
echo "FIX_OK"
