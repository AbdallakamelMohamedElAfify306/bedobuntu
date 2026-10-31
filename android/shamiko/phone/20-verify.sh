# SPDX-License-Identifier: GPL-3.0-or-later
# Phone-side verify after reboot. Run as root:
#   sh /data/local/tmp/shamiko-kit/20-verify.sh

OUT="${1:-/data/local/tmp/shamiko-kit/verify.txt}"
exec >"$OUT" 2>&1

echo "==== SHAMIKO VERIFY $(date) ===="
echo
echo "== Magisk / Zygisk =="
magisk -v 2>&1 || true
magisk --sqlite "SELECT key,value FROM settings" 2>&1 || true

echo
echo "== Modules =="
ls /data/adb/modules 2>&1 || true
for m in zygisk_shamiko zygisk-assistant playintegrityfix; do
  if [ -d "/data/adb/modules/$m" ]; then
    if [ -f "/data/adb/modules/$m/disable" ]; then
      echo "STATUS $m DISABLED"
    else
      echo "STATUS $m active"
      if [ -f "/data/adb/modules/$m/module.prop" ]; then
        cat "/data/adb/modules/$m/module.prop"
      fi
    fi
  else
    echo "STATUS $m MISSING"
  fi
done

echo
echo "== Shamiko whitelist (should be absent = blacklist mode) =="
if [ -f /data/adb/shamiko/whitelist ]; then
  echo "WARN whitelist present (remove for bank apps)"
else
  echo "whitelist absent (blacklist / DenyList mode OK)"
fi

echo
echo "== DenyList (expect NOT enforced; Shamiko mode) =="
magisk --denylist status 2>&1 || true
echo "-- target entries --"
magisk --denylist ls 2>&1 | grep -iE "hsbc|nbe|myservices|instapay|paypal|vending" || echo "(no target lines matched)"

echo
echo "== Props (spoof if present from earlier kit) =="
for k in ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.vbmeta.device_state ro.debuggable ro.secure ro.build.tags ro.build.type; do
  printf "%s=" "$k"; getprop "$k"
done

echo
echo "== Developer options =="
echo -n "development_settings_enabled="; settings get global development_settings_enabled
echo -n "adb_enabled="; settings get global adb_enabled

echo
echo "== Magisk Manager =="
if pm path com.topjohnwu.magisk >/dev/null 2>&1; then
  echo "Manager still installed (optional: uninstall APK only after you confirm root still works)"
else
  echo "Manager not installed"
fi

echo
echo "== Launch smoke (each app 8s) =="
for p in com.htsu.hsbcpersonalbanking com.ofss.obdx.and.nbe.com.eg com.emeint.android.myservices com.egyptianbanks.instapay com.paypal.android.p2pmobile; do
  if pm path "$p" >/dev/null 2>&1; then
    echo "LAUNCH $p"
    am force-stop "$p" 2>/dev/null || true
    monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    sleep 8
    if pidof "$p" >/dev/null 2>&1; then
      echo "RUNNING $p"
    else
      if ps -A 2>/dev/null | grep -F "$p" >/dev/null 2>&1; then
        echo "RUNNING $p (ps)"
      else
        echo "NOT_RUNNING $p (may have crashed or exited)"
      fi
    fi
    am force-stop "$p" 2>/dev/null || true
  else
    echo "SKIP missing $p"
  fi
done

echo
echo "== Crash hints =="
logcat -d -t 400 2>/dev/null | grep -iE "FATAL EXCEPTION|Integrity|DroidGuard|root|tamper|instapay|hsbc|nbe|paypal|myservices" | tail -50 || true

echo
echo "==== VERIFY DONE ===="
echo "VERIFY_OK"
