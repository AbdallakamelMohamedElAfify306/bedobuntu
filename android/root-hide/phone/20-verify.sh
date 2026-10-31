# SPDX-License-Identifier: GPL-3.0-or-later
# Phone-side verify after reboot. Run as: su -c "sh /data/local/tmp/roothide-fix/20-verify.sh"

OUT="${1:-/data/local/tmp/roothide-verify.txt}"
exec >"$OUT" 2>&1

echo "==== ROOTHIDE VERIFY $(date) ===="
echo
echo "== Magisk / Zygisk =="
magisk -v 2>&1 || true
magisk --sqlite "SELECT key,value FROM settings" 2>&1 || true
echo
echo "== Modules =="
ls /data/adb/modules 2>&1 || true
for m in playintegrityfix zygisk-assistant; do
  if [ -d "/data/adb/modules/$m" ]; then
    if [ -f "/data/adb/modules/$m/disable" ]; then
      echo "$m DISABLED"
    else
      echo "$m active"
    fi
  else
    echo "$m MISSING"
  fi
done
echo
echo "== DenyList (expect NOT enforced; ZA mode) =="
magisk --denylist status 2>&1 || true
echo "-- target entries --"
magisk --denylist ls 2>&1 | grep -iE "hsbc|nbe|myservices|instapay|payoneer|paypal|vending" || echo "(no target lines matched)"
echo
echo "== Props =="
for k in ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.vbmeta.device_state ro.debuggable ro.secure ro.build.tags ro.build.type; do
  printf "%s=" "$k"; getprop "$k"
done
echo
echo "== props-spoof service =="
if [ -f /data/adb/service.d/99-props-spoof.sh ]; then echo "99-props-spoof.sh present"; else echo "MISSING props spoof"; fi
if [ -f /data/local/tmp/props-spoof.log ]; then echo "-- log --"; cat /data/local/tmp/props-spoof.log; fi
if [ -f /data/adb/service.d/shared-part.sh ]; then echo "shared-part.sh still present (ok)"; fi
echo
echo "== Magisk Manager =="
if pm path com.topjohnwu.magisk >/dev/null 2>&1; then
  echo "STILL_VISIBLE: uninstall Magisk Manager from Settings after you are done"
else
  echo "Manager not installed (good)"
fi
echo
echo "== Developer options =="
echo -n "development_settings_enabled="; settings get global development_settings_enabled
echo -n "adb_enabled="; settings get global adb_enabled
echo
echo "== Launch smoke (each app 8s) =="
for p in com.htsu.hsbcpersonalbanking com.ofss.obdx.and.nbe.com.eg com.emeint.android.myservices com.egyptianbanks.instapay com.payoneer.android com.paypal.android.p2pmobile; do
  if pm path "$p" >/dev/null 2>&1; then
    echo "LAUNCH $p"
    am force-stop "$p" 2>/dev/null || true
    monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    sleep 8
    # If process still alive, likely opened
    if pidof "$p" >/dev/null 2>&1; then
      echo "RUNNING $p"
    else
      # some apps use different process names
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
logcat -d -t 400 2>/dev/null | grep -iE "FATAL EXCEPTION|Integrity|DroidGuard|root|tamper|instapay|hsbc|nbe|paypal|payoneer|myservices" | tail -50 || true
echo
echo "==== VERIFY DONE ===="
echo "VERIFY_OK"
