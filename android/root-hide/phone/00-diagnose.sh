# SPDX-License-Identifier: GPL-3.0-or-later
# Phone-side diagnose. Run as: su -c "sh /data/local/tmp/roothide-fix/00-diagnose.sh"
# No bang chars in this file.

OUT="${1:-/data/local/tmp/roothide-diag.txt}"
exec >"$OUT" 2>&1

echo "==== ROOTHIDE DIAG $(date) ===="
echo
echo "== Magisk =="
magisk -v 2>&1 || echo "magisk-v-fail"
magisk -V 2>&1 || true
echo
echo "== Magisk settings (sqlite) =="
magisk --sqlite "SELECT * FROM settings" 2>&1 || echo "sqlite-fail"
echo
echo "== Zygisk module folders =="
ls -la /data/adb/modules 2>&1 || true
echo
for d in /data/adb/modules/*; do
  if [ -d "$d" ]; then
    echo "-- $(basename "$d") --"
    cat "$d/module.prop" 2>/dev/null || true
    if [ -f "$d/disable" ]; then echo "STATE: DISABLED"; fi
    if [ -f "$d/remove" ]; then echo "STATE: REMOVE-PENDING"; fi
  fi
done
echo
echo "== DenyList status =="
magisk --denylist status 2>&1 || true
echo
echo "== DenyList contents =="
magisk --denylist ls 2>&1 || true
echo
echo "== Target packages installed =="
for p in com.htsu.hsbcpersonalbanking com.ofss.obdx.and.nbe.com.eg com.emeint.android.myservices com.egyptianbanks.instapay com.payoneer.android com.paypal.android.p2pmobile; do
  if pm path "$p" >/dev/null 2>&1; then
    echo "INSTALLED $p"
  else
    echo "MISSING   $p"
  fi
done
echo
echo "== Switch / Ubuntu related packages =="
pm list packages 2>/dev/null | grep -iE "ubuntu|switch|cheetah|omarchy|phosh" || echo "(none matched)"
echo
echo "== Magisk Manager package =="
if pm path com.topjohnwu.magisk >/dev/null 2>&1; then
  echo "MAGISK_APP_VISIBLE com.topjohnwu.magisk still installed (v31.1 has no Hide Magisk app; uninstall Manager after setup)"
else
  echo "MAGISK_APP_HIDDEN_OR_REMOVED ok"
fi
pm list packages 2>/dev/null | grep -i magisk || true
echo
echo "== Boot / build props =="
for k in ro.boot.verifiedbootstate ro.boot.flash.locked ro.boot.vbmeta.device_state ro.boot.warranty_bit ro.warranty_bit ro.debuggable ro.secure ro.build.tags ro.build.type ro.build.version.release ro.build.version.sdk ro.product.model; do
  printf "%s=" "$k"
  getprop "$k"
done
echo
echo "== Developer options / adb =="
echo -n "development_settings_enabled="; settings get global development_settings_enabled
echo -n "adb_enabled="; settings get global adb_enabled
echo -n "adb_wifi_enabled="; settings get global adb_wifi_enabled 2>/dev/null || echo "n/a"
echo
echo "== SELinux =="
getenforce 2>&1 || true
echo
echo "== Detectable paths =="
for f in /sbin/su /system/bin/su /system/xbin/su /data/adb/magisk /data/adb/modules /cache/magisk.log /data/adb/service.d/shared-part.sh; do
  if [ -e "$f" ]; then echo "EXISTS $f"; else echo "absent $f"; fi
done
ls /sdcard/Download/*.apk 2>/dev/null | head -30 || echo "(no apk in Download or unreadable)"
ls -d /sdcard/TWRP /sdcard/Download/magisk* /sdcard/Magisk* 2>/dev/null || echo "(no TWRP/Magisk folders matched)"
echo
echo "== Shared partition service.d =="
if [ -f /data/adb/service.d/shared-part.sh ]; then
  echo "FOUND shared-part.sh (kept; not removed)"
  cat /data/adb/service.d/shared-part.sh
  echo
  mount | grep -iE "sda33|Shared|shared" || echo "(shared mount not visible in this ns right now)"
else
  echo "shared-part.sh not found"
fi
echo
echo "== service.d scripts =="
ls -la /data/adb/service.d/ 2>&1 || true
echo
echo "== post-fs-data.d scripts =="
ls -la /data/adb/post-fs-data.d/ 2>&1 || true
echo
echo "== PIF fingerprint =="
PIF=/data/adb/modules/playintegrityfix
if [ -d "$PIF" ]; then
  ls -la "$PIF"/custom.pif.* "$PIF"/pif.* 2>/dev/null || true
  if [ -f "$PIF/custom.pif.prop" ]; then
    echo "-- custom.pif.prop (redacted keys) --"
    grep -E "^(FINGERPRINT|SECURITY_PATCH|DEVICE|MODEL|MANUFACTURER|BRAND|PRODUCT|RELEASE|ID|API_LEVEL|VERBOSE_LOGS|spoof)" "$PIF/custom.pif.prop" 2>/dev/null || head -40 "$PIF/custom.pif.prop"
    echo -n "custom.pif.prop mtime_epoch="
    stat -c %Y "$PIF/custom.pif.prop" 2>/dev/null || stat -f %m "$PIF/custom.pif.prop" 2>/dev/null || true
  else
    echo "no custom.pif.prop yet"
  fi
else
  echo "playintegrityfix module not installed"
fi
echo
echo "== Zygisk-Assistant =="
if [ -d /data/adb/modules/zygisk-assistant ]; then
  echo "INSTALLED"
  cat /data/adb/modules/zygisk-assistant/module.prop 2>/dev/null || true
  if [ -f /data/adb/modules/zygisk-assistant/disable ]; then echo "DISABLED"; fi
else
  echo "NOT_INSTALLED"
fi
echo
echo "== Mount leaks sample (magisk mounts) =="
cat /proc/self/mounts 2>/dev/null | grep -iE "magisk|KSU|adb/modules" | head -40 || echo "(none in this process)"
echo
echo "== Recent fatal / integrity log hints (last boot buffer) =="
logcat -d -t 200 2>/dev/null | grep -iE "instapay|IntegrityManager|DroidGuard|UNSUPPORTED|root detected|tamper" | tail -30 || true
echo
echo "==== DIAG DONE ===="
echo "DIAG_OK"
