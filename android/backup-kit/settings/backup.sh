# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# shellcheck disable=SC2086,SC2012,SC2094,SC2162
# Android settings backup for Pixel 7 Pro (rooted, Magisk). Run AS ROOT ON THE PHONE (Android slot a).
#   adb push backup.sh /data/local/tmp/ && adb shell su -c 'sh /data/local/tmp/backup.sh'
#   adb pull /data/local/tmp/android-settings-backup-<stamp> .
# READ-ONLY with respect to the system: it only copies/reads, writes into $OUT.
# Optional: FORCE_STOP=1 stops Clock/Gboard/Launcher first for a perfectly consistent DB copy.
set -u
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=${1:-/data/local/tmp/android-settings-backup-$STAMP}
mkdir -p "$OUT"/settings "$OUT"/raw "$OUT"/apps "$OUT"/info
LOG="$OUT/backup.log"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
[ "$(id -u)" = 0 ] || { echo "run as root (su)"; exit 1; }

# 0. device identity (needed to know a restore is "same device / same build")
{ getprop ro.product.model; getprop ro.build.fingerprint; getprop ro.build.version.sdk;
  getprop ro.build.display.id; getprop ro.boot.slot_suffix; getprop ro.serialno; } > "$OUT/info/device.txt" 2>&1

# 1. settings list (text) for each namespace + current user
for ns in system secure global; do
  settings list $ns > "$OUT/settings/settings_$ns.txt" 2>>"$LOG" && log "settings list $ns: $(wc -l < "$OUT/settings/settings_$ns.txt") keys"
done

# helper: tar a path list (skips missing), keeps uid/gid/mode; records SELinux labels in a manifest
pack(){ # name path...
  name=$1; shift; have=""
  for p in "$@"; do [ -e "$p" ] && have="$have $p"; done
  if [ -z "$have" ]; then log "SKIP $name (nothing at: $*)"; return; fi
  ls -lZRd $have > "$OUT/info/$name.labels.txt" 2>&1
  ( ls -lZR $have >> "$OUT/info/$name.labels.txt" ) 2>/dev/null
  tar -cpf "$OUT/raw/$name.tar" $have 2>>"$LOG" && log "OK   $name <- $have ($(wc -c < "$OUT/raw/$name.tar") bytes)"
}
topack(){ pack "$@"; }

# 2. raw settings databases + all system-user XML (ABX binary on Android 12+)
pack system_users_0   /data/system/users/0
# also a readable XML copy of every ABX file (abx2xml exists on Android 12+)
if command -v abx2xml >/dev/null 2>&1; then
  mkdir -p "$OUT/settings/readable_xml"
  for f in /data/system/users/0/*.xml /data/system/notification_policy.xml \
           /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml \
           /data/misc_de/0/apexdata/com.android.permission/roles.xml; do
    [ -f "$f" ] && abx2xml "$f" "$OUT/settings/readable_xml/$(echo "$f" | tr / _).xml" 2>/dev/null
  done
  log "abx2xml readable copies: $(ls "$OUT/settings/readable_xml" | wc -l) files"
fi

# 3. Wi-Fi networks (contains PSKs)
pack wifi /data/misc/apexdata/com.android.wifi /data/misc/wifi /data/misc_ce/0/wifi

# 4. Bluetooth pairings (link keys) - bluedroid is the legacy path, bluetooth apex data on newer builds
pack bluetooth /data/misc/bluedroid /data/misc/bluetooth /data/misc/apexdata/com.android.btservices

# 5. Launcher layout (Pixel Launcher): credential-encrypted + device-protected storage
[ "${FORCE_STOP:-0}" = 1 ] && am force-stop com.google.android.apps.nexuslauncher
pack launcher /data/data/com.google.android.apps.nexuslauncher /data/user_de/0/com.google.android.apps.nexuslauncher

# 6. Wallpaper (home + lock files and wallpaper_info.xml)
mkdir -p "$OUT/wp"; WP=""
for f in /data/system/users/0/wallpaper*; do [ -e "$f" ] && WP="$WP $f"; done
[ -n "$WP" ] && pack wallpaper $WP

# 7. Accounts: NAMES AND TYPES ONLY, no tokens/passwords
dumpsys account 2>/dev/null | grep -E 'Account \{name=' | sed 's/^ *//' | sort -u > "$OUT/info/accounts_names_only.txt"
log "accounts listed: $(wc -l < "$OUT/info/accounts_names_only.txt") (names only)"

# 8. Default apps / roles
cmd role list >/dev/null 2>&1 && for r in android.app.role.HOME android.app.role.BROWSER android.app.role.DIALER \
  android.app.role.SMS android.app.role.ASSISTANT android.app.role.EMERGENCY android.app.role.CALL_REDIRECTION \
  android.app.role.CALL_SCREENING android.app.role.SYSTEM_GALLERY; do
  echo "$r: $(cmd role get-role-holders --user 0 $r 2>&1 | tr '\n' ' ')"; done > "$OUT/info/role_holders.txt"
pack roles /data/system/users/0/roles.xml /data/misc_de/0/apexdata/com.android.permission/roles.xml

# 9. Notification policy (DND rules, priority conversations, channels config)
pack notification_policy /data/system/notification_policy.xml
dumpsys notification 2>/dev/null | grep -iE 'zen|policy|DND|interruption' | head -200 > "$OUT/info/notification_zen_dump.txt"
cmd notification list 2>/dev/null > "$OUT/info/notification_listeners.txt"

# 10. Keyboard: Gboard + current IME selection
[ "${FORCE_STOP:-0}" = 1 ] && am force-stop com.google.android.inputmethod.latin
pack gboard /data/data/com.google.android.inputmethod.latin /data/user_de/0/com.google.android.inputmethod.latin
ime list -s > "$OUT/info/ime_enabled.txt" 2>&1; settings get secure default_input_method > "$OUT/info/ime_default.txt"

# 11. Clock / alarms (alarms.db lives in the app's databases dir)
[ "${FORCE_STOP:-0}" = 1 ] && am force-stop com.google.android.deskclock
pack clock /data/data/com.google.android.deskclock /data/user_de/0/com.google.android.deskclock

# 12. checksums + one bundle
( cd "$OUT" && find . -type f -not -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS )
tar -cpf "$OUT.tar" -C "$(dirname "$OUT")" "$(basename "$OUT")" && log "bundle: $OUT.tar"
echo "DONE -> $OUT.tar   (contains Wi-Fi passwords and Bluetooth keys: store encrypted)"
