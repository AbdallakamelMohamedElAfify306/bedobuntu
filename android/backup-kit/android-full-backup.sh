# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=bash
# android-full-backup.sh - full backup of a rooted Pixel 7 Pro to this Mac, over adb.
#
#   bash android-full-backup.sh            run (or resume) the backup
#   bash android-full-backup.sh verify     re-check SHA256SUMS of the newest backup
#   ONLY=apps,media bash android-full-backup.sh      run only some steps
#       steps: manifest settings contacts root switch partitions apps media
#   DEST=/path/to/android-20261029 bash android-full-backup.sh   resume a backup from another day
#   IGNORE_SPACE=1 ...   skip the free-space check (not recommended)
#
# Works with the stock bash 3.2 of macOS. The phone is only READ. The only writes on the phone are
# temp files in /data/local/tmp/abk (removed at the end) and the stay-awake setting (restored at the end).

umask 077
KIT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RTMP=/data/local/tmp/abk
TODAY=$(date +%Y%m%d)
DEST=${DEST:-$HOME/cheetah-dual/backup/android-$TODAY}
ONLY=${ONLY:-}
IGNORE_SPACE=${IGNORE_SPACE:-0}
MARGIN_KB=2097152
START_TS=$(date +%s)

N_OK=0; N_SKIP=0; N_FAIL=0; N_WARN=0
FAILED=""
LOGFILE=/dev/null
ERRLOG=/dev/null
BGPID=""
CAFF_PID=""
STAYON_ON=0
PREV_STAYON=null
REMOTE_MADE=0
CLEANED=0

if [ -t 1 ]; then C_G=$(printf '\033[32m'); C_R=$(printf '\033[31m'); C_Y=$(printf '\033[33m'); C_0=$(printf '\033[0m'); else C_G=; C_R=; C_Y=; C_0=; fi

# ---------------------------------------------------------------- logging
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOGFILE"; }
say()  { printf '%s\n' "$*" | tee -a "$LOGFILE"; }
ok()   { N_OK=$((N_OK + 1));     printf '[%s] %sOK%s    %s\n'   "$(date +%H:%M:%S)" "$C_G" "$C_0" "$*" | tee -a "$LOGFILE"; }
skip() { N_SKIP=$((N_SKIP + 1)); printf '[%s] SKIP  %s\n'        "$(date +%H:%M:%S)" "$*" | tee -a "$LOGFILE"; }
warn() { N_WARN=$((N_WARN + 1)); printf '[%s] %sWARN%s  %s\n'   "$(date +%H:%M:%S)" "$C_Y" "$C_0" "$*" | tee -a "$LOGFILE"; }
fail() { N_FAIL=$((N_FAIL + 1)); FAILED="$FAILED
  - $*"; printf '[%s] %sFAIL%s  %s\n' "$(date +%H:%M:%S)" "$C_R" "$C_0" "$*" | tee -a "$LOGFILE"; }
fatal() { printf '[%s] %sFATAL%s %s\n' "$(date +%H:%M:%S)" "$C_R" "$C_0" "$*" | tee -a "$LOGFILE"; exit 3; }

human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ } printf "%.1f %s", b, u[i] }'; }
fsize() { wc -c < "$1" | tr -d ' '; }

# ---------------------------------------------------------------- adb wrappers
# stdin is always /dev/null so adb never eats the stdin of a surrounding while-read loop.
# exec-out is binary safe (no tty, no CRLF translation). It merges stderr into stdout, so every
# remote command that produces binary output redirects its own stderr (see device/*.sh).
dsh() { adb shell "$1" < /dev/null; }
dsu() { adb exec-out "su -c '$1'" < /dev/null; }

ensure_device() {
  local i=0 st
  while [ "$i" -lt 30 ]; do
    st=$(adb get-state 2> /dev/null < /dev/null)
    [ "$st" = device ] && return 0
    i=$((i + 1))
    [ "$i" = 1 ] && log "WAIT  phone not connected, waiting up to 60 s (replug the cable)"
    sleep 2
  done
  return 1
}

need_device() { ensure_device || fatal "phone disconnected. Reconnect it and run the same command again: it resumes."; }

# ---------------------------------------------------------------- cleanup
stayon_restore() {
  [ "$STAYON_ON" = 1 ] || return 0
  if [ "$PREV_STAYON" = null ]; then
    adb shell "settings delete global stay_on_while_plugged_in" < /dev/null > /dev/null 2>&1
  else
    adb shell "settings put global stay_on_while_plugged_in $PREV_STAYON" < /dev/null > /dev/null 2>&1
  fi
  STAYON_ON=0
  rm -f "$DEST/.stayon.prev"
  log "stay-awake setting restored (stay_on_while_plugged_in=$PREV_STAYON)"
}

cleanup() {
  [ "$CLEANED" = 1 ] && return 0
  CLEANED=1
  [ -n "$BGPID" ] && kill "$BGPID" 2> /dev/null
  [ -n "$CAFF_PID" ] && kill "$CAFF_PID" 2> /dev/null
  if command -v adb > /dev/null 2>&1 && [ -n "${ANDROID_SERIAL:-}" ]; then
    stayon_restore
    if [ "$REMOTE_MADE" = 1 ]; then
      adb exec-out "su -c 'rm -rf $RTMP'" < /dev/null > /dev/null 2>&1 && log "phone temp files removed ($RTMP)"
    fi
  fi
  find "$DEST" -name '*.part' -delete 2> /dev/null
  rm -rf "$DEST/.tmp"
}
on_signal() { log "interrupted. Run the same command again to resume."; exit 130; }
trap on_signal INT TERM HUP
trap cleanup EXIT

# ---------------------------------------------------------------- verification and streaming
gz_ok()  { [ -s "$1" ] && gzip -t "$1" 2> /dev/null; }
# tar_ok keeps the file listing in $TAR_LIST, so big archives are only read once
TAR_LIST=""
tar_ok() { [ -s "$1" ] && tar -tf "$1" > "$TAR_LIST" 2> /dev/null; }
verify_kind() { case $1 in gz) gz_ok "$2" ;; tar) tar_ok "$2" ;; *) return 1 ;; esac; }

# run_stream OUT REMOTE_CMD [progress]  - stream su command output into OUT
run_stream() {
  local out=$1 rcmd=$2 prog=${3:-} t0 n
  if [ "$prog" = progress ]; then
    adb exec-out "su -c '$rcmd'" < /dev/null > "$out" 2>> "$ERRLOG" &
    BGPID=$(jobs -p | tail -1)
    t0=$(date +%s); n=0
    while kill -0 "$BGPID" 2> /dev/null; do
      sleep 2
      n=$((n + 1))
      if [ $((n % 10)) = 0 ]; then
        printf '      ... %s received, %s min elapsed\n' "$(human "$(fsize "$out")")" "$(( ($(date +%s) - t0) / 60 ))"
      fi
    done
    wait "$BGPID"; BGPID=""
  else
    adb exec-out "su -c '$rcmd'" < /dev/null > "$out" 2>> "$ERRLOG"
  fi
}

# fetch_verified LABEL OUTFILE KIND REMOTE_CMD [strict] [progress]
# returns 0 ok or already done, 1 failed, 2 empty (nothing to back up)
fetch_verified() {
  local label=$1 out=$2 kind=$3 rcmd=$4 strict=${5:-lenient} prog=${6:-}
  mkdir -p "$(dirname "$out")"
  if [ -f "$out" ] && verify_kind "$kind" "$out"; then
    skip "$label already done ($(human "$(fsize "$out")"))"
    return 0
  fi
  rm -f "$out" "$out.part"
  need_device
  run_stream "$out.part" "$rcmd" "$prog"
  if [ -s "$out.part" ]; then :; else
    rm -f "$out.part"
    if [ "$strict" = strict ]; then fail "$label (empty output)"; return 1; fi
    warn "$label: nothing to back up"
    return 2
  fi
  if verify_kind "$kind" "$out.part"; then
    mv "$out.part" "$out"
    ok "$label ($(human "$(fsize "$out")"), verified with $( [ "$kind" = gz ] && echo 'gzip -t' || echo 'tar -t'))"
    return 0
  fi
  rm -f "$out.part"
  fail "$label (archive is damaged or truncated)"
  return 1
}

# capture LABEL REMOTE_CMD OUTFILE [req|opt]  - small text output
capture() {
  local label=$1 rcmd=$2 out=$3 mode=${4:-req} rc
  mkdir -p "$(dirname "$out")"
  need_device
  adb exec-out "su -c '$rcmd'" < /dev/null > "$out.part" 2>> "$ERRLOG"
  rc=$?
  tr -d '\r' < "$out.part" > "$out"
  rm -f "$out.part"
  if [ "$rc" = 0 ] && [ -s "$out" ]; then
    ok "$label ($(wc -l < "$out" | tr -d ' ') lines)"
  elif [ "$mode" = opt ]; then
    warn "$label (empty or error, optional)"
  else
    fail "$label"
  fi
}

in_want() { case ",${ONLY}," in ",,") return 0 ;; *",$1,"*) return 0 ;; esac; return 1; }
valid_pkg() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'; }
valid_apk_path() { case $1 in *..*) return 1 ;; esac; printf '%s\n' "$1" | grep -Eq '^/[A-Za-z0-9_./=~+-]+\.apk$'; }

# ---------------------------------------------------------------- preflight
preflight() {
  local n serial model build slot used_kb need_kb have_kb have_dest_kb
  mkdir -p "$DEST" || { echo "cannot create $DEST"; exit 1; }
  chmod 700 "$DEST"
  LOGFILE="$DEST/backup.log"; ERRLOG="$DEST/adb-errors.log"
  mkdir -p "$DEST/logs" "$DEST/manifest" "$DEST/.tmp"
  TAR_LIST="$DEST/.tmp/last-tar-list.txt"
  say "=== Android full backup  $(date '+%Y-%m-%d %H:%M:%S')  ->  $DEST"
  find "$DEST" -name '*.part' -delete 2> /dev/null

  local t
  for t in adb awk gzip tar shasum find df wc tr sed grep unzip; do
    command -v "$t" > /dev/null 2>&1 || fatal "tool not found on the Mac: $t (adb: brew install android-platform-tools)"
  done
  log "adb: $(adb version 2> /dev/null | head -1)"

  adb start-server > /dev/null 2>&1
  n=$(adb devices < /dev/null | awk 'NR > 1 && $2 == "device" { c++ } END { print c + 0 }')
  if [ "$n" = 0 ]; then
    adb devices < /dev/null | awk 'NR > 1 && $2 == "unauthorized" { f = 1 } END { exit f ? 0 : 1 }' \
      && fatal "phone is unauthorized: unlock it and accept the USB debugging prompt."
    fatal "no phone found over adb. Plug it in, unlock it, enable USB debugging."
  fi
  if [ "$n" -gt 1 ] && [ -z "${ANDROID_SERIAL:-}" ]; then
    fatal "more than one adb device. Unplug the others or run with ANDROID_SERIAL=<serial>."
  fi
  if [ -z "${ANDROID_SERIAL:-}" ]; then
    serial=$(adb devices < /dev/null | awk 'NR > 1 && $2 == "device" { print $1; exit }')
    export ANDROID_SERIAL=$serial
  fi
  log "device serial: $ANDROID_SERIAL"

  # root check (Magisk may show a prompt on the phone: press Grant)
  if dsh "su -c id" 2> /dev/null | grep -q 'uid=0'; then
    ok "root works (su -c id gives uid=0)"
  else
    fatal "su failed. Look at the phone: grant root to Shell in Magisk, then run again."
  fi

  model=$(dsh "getprop ro.product.model" | tr -d '\r\n')
  build=$(dsh "getprop ro.build.id" | tr -d '\r\n')
  slot=$(dsh "getprop ro.boot.slot_suffix" | tr -d '\r\n')
  log "phone: $model, build $build, slot $slot"
  [ "$model" = "Pixel 7 Pro" ] || warn "model is '$model', this kit was written for Pixel 7 Pro"
  [ "$slot" = "_a" ] || warn "running slot is '$slot', not _a. The partition images below are still the _a ones, as asked"

  # phone work dir + helper scripts
  dsh "mkdir -p $RTMP && chmod 755 $RTMP" > /dev/null 2>&1
  REMOTE_MADE=1
  local f
  for f in "$KIT_DIR"/device/*.sh; do
    adb push "$f" "$RTMP/$(basename "$f")" < /dev/null > /dev/null 2>> "$ERRLOG" || fatal "adb push failed for $f"
  done
  adb push "$KIT_DIR/settings/backup.sh" "$RTMP/settings-backup.sh" < /dev/null > /dev/null 2>> "$ERRLOG" || fatal "adb push failed for settings/backup.sh"
  dsu "touch $RTMP/tar.err; chmod 666 $RTMP/tar.err" > /dev/null
  ok "helper scripts pushed to $RTMP (temporary)"

  tar_selftest

  # free space: phone used space under /data (upper bound, includes apps and media) + margin
  used_kb=$(dsu "df -k /data" | tr -d '\r' | awk 'NF >= 4 { v = $(NF - 3) } END { print v }')
  if printf '%s\n' "$used_kb" | grep -Eq '^[0-9]+$'; then :; else
    warn "could not read phone used space (got '$used_kb'), assuming 128 GB"; used_kb=134217728
  fi
  have_dest_kb=$(du -sk "$DEST" 2> /dev/null | awk '{ print $1 }')
  need_kb=$((used_kb + MARGIN_KB - ${have_dest_kb:-0}))
  [ "$need_kb" -lt 0 ] && need_kb=0
  have_kb=$(df -Pk "$DEST" | awk 'NR == 2 { print $4 }')
  log "space: phone /data used $(human $((used_kb * 1024))), Mac free $(human $((have_kb * 1024))), needed (with margin) $(human $((need_kb * 1024)))"
  if [ "$have_kb" -lt "$need_kb" ]; then
    if [ "$IGNORE_SPACE" = 1 ]; then
      warn "not enough free space on the Mac, continuing because IGNORE_SPACE=1"
    else
      fatal "not enough free space on the Mac. Free up $(human $(((need_kb - have_kb) * 1024))) or use an external drive: DEST=/Volumes/X/android-$TODAY bash ... (IGNORE_SPACE=1 skips this check)"
    fi
  fi

  # keep screen awake while plugged in
  if [ -f "$DEST/.stayon.prev" ]; then
    PREV_STAYON=$(cat "$DEST/.stayon.prev")
  else
    PREV_STAYON=$(dsh "settings get global stay_on_while_plugged_in" | tr -d '\r\n ')
    case $PREV_STAYON in 0|1|2|3|4|5|6|7) ;; *) PREV_STAYON=null ;; esac
    printf '%s\n' "$PREV_STAYON" > "$DEST/.stayon.prev"
  fi
  dsh "svc power stayon usb" > /dev/null 2>&1
  dsh "input keyevent KEYCODE_WAKEUP" > /dev/null 2>&1
  STAYON_ON=1
  log "screen stays awake while plugged in (previous value: $PREV_STAYON, restored at the end)"

  # keep the Mac awake as well
  if command -v caffeinate > /dev/null 2>&1; then
    caffeinate -dims -w $$ > /dev/null 2>&1 &
    CAFF_PID=$(jobs -p | tail -1)
  fi
}

# test which tar features the phone's toybox tar really has, with the exact forms used below
tar_selftest() {
  local td="$DEST/.tmp/selftest" ok1=0 ok2=0 base=data/local/tmp/abk/t
  mkdir -p "$td"
  dsu "tar --help 2>&1; toybox --version 2>&1" > "$DEST/logs/device-tar-help.txt" 2> /dev/null
  dsu "rm -rf $RTMP/t; mkdir -p $RTMP/t/DCIM $RTMP/t/Android/keep; echo one > $RTMP/t/DCIM/p.jpg; echo two > $RTMP/t/Android/keep/k.txt" > /dev/null
  dsu "sh $RTMP/tarpaths.sh $base" > "$td/t.tgz" 2> /dev/null
  if gzip -t "$td/t.tgz" 2> /dev/null && tar -tzf "$td/t.tgz" 2> /dev/null | grep -q 'DCIM/p.jpg' \
     && tar -tzf "$td/t.tgz" 2> /dev/null | grep -q 'Android/keep/k.txt'; then ok1=1; fi
  dsu "tar -cf - -C / $base/DCIM 2>/dev/null" > "$td/t.tar" 2> /dev/null
  if tar -tf "$td/t.tar" 2> /dev/null | grep -q 'DCIM/p.jpg'; then ok2=1; fi
  dsu "rm -rf $RTMP/t" > /dev/null
  rm -rf "$td"
  if [ "$ok1" = 1 ] && [ "$ok2" = 1 ]; then
    ok "phone tar self-test passed (tar -czf - -C / PATH and tar -cf - -C / PATH, no GNU-only flags)"
  else
    fatal "phone tar self-test failed (gz=$ok1 plain=$ok2). See logs/device-tar-help.txt"
  fi
}

# ---------------------------------------------------------------- step: manifest
step_manifest() {
  log "--- step: device manifest"
  local m="$DEST/manifest"
  capture "getprop"                "getprop"                                        "$m/getprop.txt"
  capture "partition names"        "ls -l /dev/block/by-name"                       "$m/block-by-name.txt"
  capture "df"                     "df"                                             "$m/df.txt"
  capture "df -h"                  "df -h"                                          "$m/df-h.txt" opt
  capture "mounts"                 "cat /proc/mounts"                               "$m/mounts.txt" opt
  capture "kernel"                 "uname -a"                                       "$m/uname.txt" opt
  capture "pm list -3"             "pm list packages -3"                            "$m/pm-packages-3.txt"
  capture "pm list -3 -f"          "pm list packages -3 -f"                         "$m/pm-packages-3-f.txt"
  capture "pm list -3 -U (uids)"   "pm list packages -3 -U"                         "$m/pm-packages-3-uid.txt"
  capture "pm list (full)"         "pm list packages"                               "$m/pm-packages-full.txt"
  capture "pm list -f -U (full)"   "pm list packages -f -U"                         "$m/pm-packages-full-f-uid.txt"
  capture "pm list -d (disabled)"  "pm list packages -d"                            "$m/pm-packages-disabled.txt" opt
  capture "pm list -s (system)"    "pm list packages -s"                            "$m/pm-packages-system.txt" opt
  capture "phone user list"        "pm list users"                                  "$m/pm-users.txt" opt
  capture "/data/local/tmp listing" "ls -laZ /data/local/tmp"                       "$m/ls-local-tmp.txt" opt
  capture "internal storage top level" "ls -laZ /data/media/0"                      "$m/ls-media-0.txt" opt
  capture "Shared mount check"     "ls -ldZ /data/media/0/Shared; grep -i shared /proc/mounts; true" "$m/shared-partition.txt" opt
  capture "partition table (sizes)" "cat /proc/partitions"                          "$m/proc-partitions.txt" opt
  cp -f "$m/pm-packages-3.txt" "$DEST/packages-3.txt" 2> /dev/null
  cp -f "$m/pm-packages-full.txt" "$DEST/packages-all.txt" 2> /dev/null
}

# ---------------------------------------------------------------- step: settings (reuses settings/backup.sh)
step_settings() {
  log "--- step: settings (settings/backup.sh run on the phone as root)"
  local out="$DEST/settings/android-settings-backup.tar" slog="$DEST/logs/settings-backup.log"
  mkdir -p "$DEST/settings"
  cp -f "$KIT_DIR/settings/restore.sh" "$KIT_DIR/settings/RESTORE-SAFETY.md" "$DEST/settings/"
  if [ -f "$out" ] && tar_ok "$out"; then
    skip "settings bundle already done ($(human "$(fsize "$out")"))"
    return 0
  fi
  need_device
  dsu "rm -rf $RTMP/settings-out $RTMP/settings-out.tar" > /dev/null
  dsu "sh $RTMP/settings-backup.sh $RTMP/settings-out" > "$slog" 2>&1
  if grep -q '^DONE' "$slog"; then :; else
    fail "settings/backup.sh did not finish (see logs/settings-backup.log)"
    return 1
  fi
  if fetch_verified "settings bundle (system/secure/global, Wi-Fi, Bluetooth, launcher, wallpaper, roles, DND, Gboard, clock)" \
       "$out" tar "cat $RTMP/settings-out.tar" strict; then
    mkdir -p "$DEST/settings/extracted"
    tar -xf "$out" -C "$DEST/settings/extracted" > /dev/null 2>&1 || true
    [ -d "$DEST/settings/extracted" ] && log "      readable copy: settings/extracted/ (settings_*.txt, info/)"
    dsu "rm -rf $RTMP/settings-out $RTMP/settings-out.tar" > /dev/null
  fi
}

# ---------------------------------------------------------------- step: contacts, call log, sms
step_contacts() {
  log "--- step: contacts, call log, SMS"
  local out="$DEST/contacts/contacts-sms-calllog.tar.gz" p
  local paths=""
  for p in contacts telephony blockednumber; do
    paths="$paths data/data/com.android.providers.$p/databases data/user_de/0/com.android.providers.$p/databases"
  done
  if fetch_verified "contact/call-log/SMS databases (+wal/shm, /data/data and /data/user_de/0)" "$out" gz \
       "sh $RTMP/tarpaths.sh $paths" strict; then
    tar -tzf "$out" 2> /dev/null > "$DEST/contacts/archive-listing.txt"
    for p in contacts2.db mmssms.db telephony.db; do
      if grep -q "/$p\$" "$DEST/contacts/archive-listing.txt"; then ok "  found $p in archive"; else warn "  $p not found in archive (this Android version may keep it elsewhere)"; fi
    done
    if grep -qE '/(contacts2|mmssms|telephony)\.db-wal$' "$DEST/contacts/archive-listing.txt"; then
      log "      -wal files included"
    else
      log "      no -wal files present (databases were checkpointed)"
    fi
  fi
  local c="$DEST/contacts/export"
  capture "export contacts (text)"       "content query --user 0 --uri content://com.android.contacts/contacts"                           "$c/contacts.txt" opt
  capture "export phone numbers (text)"  "content query --user 0 --uri content://com.android.contacts/data/phones --projection display_name:data1:data2:contact_id" "$c/phones.txt" opt
  capture "export raw contacts (text)"   "content query --user 0 --uri content://com.android.contacts/raw_contacts"                       "$c/raw_contacts.txt" opt
  capture "export contact data rows"     "content query --user 0 --uri content://com.android.contacts/data --projection raw_contact_id:mimetype:data1:data2:data3:data4" "$c/data.txt" opt
  capture "export call log (text)"       "content query --user 0 --uri content://call_log/calls"                                          "$c/call_log.txt" opt
  capture "export SMS (text)"            "content query --user 0 --uri content://sms"                                                     "$c/sms.txt" opt
}

# ---------------------------------------------------------------- step: root setup
step_root() {
  log "--- step: root setup (/data/adb, Magisk)"
  mkdir -p "$DEST/root"
  fetch_verified "/data/adb (modules, service.d incl. shared-part.sh, magisk.db, PIF)" "$DEST/root/data-adb.tar.gz" gz \
    "sh $RTMP/tarpaths.sh data/adb" strict
  capture "magisk --denylist ls" "magisk --denylist ls 2>&1" "$DEST/root/magisk-denylist.txt" opt
  capture "magisk info (version, su grants, ls)" "sh $RTMP/rootinfo.sh" "$DEST/root/magisk-info.txt" opt
}

# ---------------------------------------------------------------- APK helper
# backup_apks INDEXFILE OUTDIR  (index lines: pkg TAB path TAB size)
backup_apks() {
  local index=$1 outdir=$2 pkg path size base dst n_ok=0 n_bad=0 n_skip=0 p
  while IFS="$(printf '\t')" read -r pkg path size; do
    valid_pkg "$pkg" || continue
    if valid_apk_path "$path" && printf '%s\n' "$size" | grep -Eq '^[0-9]+$'; then :; else
      fail "apk path/size rejected: $pkg $path"; n_bad=$((n_bad + 1)); continue
    fi
    base=$(basename "$path")
    dst="$outdir/$pkg/$base"
    mkdir -p "$outdir/$pkg"
    if [ -f "$dst" ] && [ "$(fsize "$dst")" = "$size" ] && unzip -tq "$dst" > /dev/null 2>&1; then
      n_skip=$((n_skip + 1)); continue
    fi
    need_device
    rm -f "$dst" "$dst.part"
    adb exec-out "su -c 'cat $path'" < /dev/null > "$dst.part" 2>> "$ERRLOG"
    if [ -f "$dst.part" ] && [ "$(fsize "$dst.part")" = "$size" ] && unzip -tq "$dst.part" > /dev/null 2>&1; then
      mv "$dst.part" "$dst"; n_ok=$((n_ok + 1))
    else
      rm -f "$dst.part"; n_bad=$((n_bad + 1)); fail "apk $pkg/$base (size or zip check failed)"
    fi
  done < "$index"
  p=$(cut -f1 "$index" | sort -u | wc -l | tr -d ' ')
  if [ "$n_bad" = 0 ]; then ok "APK files: $n_ok copied, $n_skip already present, $p packages (splits included, size and zip verified)"
  else warn "APK files: $n_ok copied, $n_skip present, $n_bad failed"; fi
}

# ---------------------------------------------------------------- step: apps
step_apps() {
  log "--- step: apps and data"
  local a="$DEST/apps" list="$DEST/manifest/pm-packages-3.txt" total i=0 pkg f
  mkdir -p "$a/data" "$a/apks"
  [ -s "$list" ] || capture "pm list -3" "pm list packages -3" "$list"
  cp -f "$list" "$DEST/packages-3.txt"
  [ -s "$DEST/manifest/pm-packages-full.txt" ] || capture "pm list (full)" "pm list packages" "$DEST/manifest/pm-packages-full.txt"
  cp -f "$DEST/manifest/pm-packages-full.txt" "$DEST/packages-all.txt"
  capture "APK index (pm path of every -3 package)" "sh $RTMP/apklist.sh" "$a/apk-index-raw.txt"
  awk -F'\t' 'NF == 3' "$a/apk-index-raw.txt" > "$a/apk-index.tsv"
  backup_apks "$a/apk-index.tsv" "$a/apks"

  sed 's/^package://' "$list" | tr -d '\r' | sort -u > "$a/packages.txt"
  total=$(wc -l < "$a/packages.txt" | tr -d ' ')
  log "app data: $total packages (tar.gz per package: /data/data, /data/user_de/0, Android/data)"
  while IFS= read -r pkg; do
    i=$((i + 1))
    valid_pkg "$pkg" || { warn "[$i/$total] skipping odd package name '$pkg'"; continue; }
    f="$a/data/$pkg.tar.gz"
    fetch_verified "[$i/$total] $pkg" "$f" gz "sh $RTMP/pkgtar.sh $pkg" lenient
  done < "$a/packages.txt"

  fetch_verified "Android/obb (all game data)" "$a/obb.tar.gz" gz "sh $RTMP/tarpaths.sh data/media/0/Android/obb" lenient progress
}

# ---------------------------------------------------------------- step: media
step_media() {
  log "--- step: photos, videos, all internal storage (plain tar of /data/media/0, without Shared, Android/data, Android/obb)"
  mkdir -p "$DEST/media"
  fetch_verified "internal storage tar" "$DEST/media/internal-storage.tar" tar "sh $RTMP/mediatar.sh" strict progress
  if [ -f "$DEST/media/internal-storage.tar" ] && [ -s "$TAR_LIST" ]; then
    cp -f "$TAR_LIST" "$DEST/media/internal-storage.list.txt"
    if grep -qE '^(\./)?(Shared|Android/data|Android/obb)(/|$)' "$TAR_LIST"; then
      fail "internal storage tar contains Shared or Android/data or Android/obb (it must not)"
    else
      ok "  confirmed: Shared, Android/data and Android/obb are not inside the media tar ($(wc -l < "$TAR_LIST" | tr -d ' ') entries listed in media/internal-storage.list.txt)"
    fi
  fi
}

# ---------------------------------------------------------------- step: SwitchToUbuntu app
step_switch() {
  log "--- step: SwitchToUbuntu app (APK, data, scripts)"
  local s="$DEST/switch-ubuntu" lines line pkg n=0
  mkdir -p "$s"
  need_device
  dsu "pm list packages -f" | tr -d '\r' > "$s/pm-list-f-full.txt"
  grep -i ubuntu "$s/pm-list-f-full.txt" > "$s/matches.txt"
  if [ -s "$s/matches.txt" ]; then
    SWITCH_FOUND=1
  else
    SWITCH_FOUND=0
    warn "no package matching 'ubuntu' in pm list packages -f"
    grep -iE 'switch|cheetah|dualboot' "$s/pm-list-f-full.txt" > "$s/candidates.txt"
    [ -s "$s/candidates.txt" ] && warn "similar packages saved in switch-ubuntu/candidates.txt, check it by eye"
  fi
  if [ "$SWITCH_FOUND" = 1 ]; then
    lines=$(cat "$s/matches.txt")
    log "matches: $(printf '%s\n' "$lines" | tr '\n' ' ')"
    while IFS= read -r line; do
      pkg=${line##*=}
      valid_pkg "$pkg" || { warn "odd package name in '$line'"; continue; }
      n=$((n + 1))
      mkdir -p "$s/$pkg"
      capture "APK list for $pkg" "sh $RTMP/apklist.sh $pkg" "$s/$pkg/apk-index.txt"
      awk -F'\t' 'NF == 3' "$s/$pkg/apk-index.txt" > "$s/$pkg/apk-index.tsv"
      backup_apks "$s/$pkg/apk-index.tsv" "$s/apks"
      fetch_verified "$pkg data (/data/data, /data/user_de/0, Android/data)" "$s/$pkg/data.tar.gz" gz "sh $RTMP/pkgtar.sh $pkg" lenient
    done < "$s/matches.txt"
  fi
  fetch_verified "boot scripts /data/adb/service.d and post-fs-data.d" "$s/adb-scripts.tar.gz" gz \
    "sh $RTMP/tarpaths.sh data/adb/service.d data/adb/post-fs-data.d" strict
  fetch_verified "loose files in /data/local/tmp (scripts)" "$s/local-tmp.tar.gz" gz "sh $RTMP/tmptar.sh" lenient
}

# ---------------------------------------------------------------- step: partitions
PARTS="boot_a init_boot_a vendor_boot_a vendor_kernel_boot_a vendor_kernel_boot_b dtbo_a vbmeta_a vbmeta_b efs efs_backup modem_userdata persist"
MAX_PART_BYTES=2147483648

step_partitions() {
  log "--- step: critical partition images (read-only dd from /dev/block/by-name)"
  local d="$DEST/partitions" name size out got
  mkdir -p "$d"
  : > "$d/partitions.txt"
  for name in $PARTS; do
    case $name in userdata|userdata_*|super|super_*) fail "refusing to read $name"; continue ;; esac
    need_device
    size=$(dsu "sh $RTMP/partsize.sh $name" | tr -d '\r\n ')
    if printf '%s\n' "$size" | grep -Eq '^[0-9]+$'; then :; else
      skip "partition $name not present on this phone"
      continue
    fi
    if [ "$size" -gt "$MAX_PART_BYTES" ]; then fail "partition $name is $(human "$size"), too big, not read"; continue; fi
    out="$d/$name.img"
    printf '%s\t%s\n' "$name" "$size" >> "$d/partitions.txt"
    if [ -f "$out" ] && [ "$(fsize "$out")" = "$size" ]; then
      skip "partition $name already done ($(human "$size"))"
      continue
    fi
    rm -f "$out" "$out.part"
    adb exec-out "su -c 'dd if=/dev/block/by-name/$name bs=1048576 2>/dev/null'" < /dev/null > "$out.part" 2>> "$ERRLOG"
    got=$(fsize "$out.part" 2> /dev/null || echo 0)
    if [ "$got" = "$size" ]; then
      mv "$out.part" "$out"
      ok "partition $name ($(human "$size"))"
    else
      rm -f "$out.part"
      fail "partition $name (got $got of $size bytes)"
    fi
  done
}

# ---------------------------------------------------------------- checksums, verify, summary
step_checksums() {
  log "--- step: SHA256SUMS"
  # shellcheck disable=SC2094
  ( cd "$DEST" && find . -type f -not -name SHA256SUMS -not -name backup.log -not -name '.stayon.prev' -not -name '.verify.txt' -not -path './.tmp/*' -not -name '*.part' \
      | LC_ALL=C sort | while IFS= read -r f; do shasum -a 256 "$f"; done > SHA256SUMS )
  ok "SHA256SUMS written ($(wc -l < "$DEST/SHA256SUMS" | tr -d ' ') files)"
}

pull_device_errors() {
  local n
  if [ "$REMOTE_MADE" = 1 ] && ensure_device; then
    dsu "cat $RTMP/tar.err" | tr -d '\r' > "$DEST/logs/device-tar-errors.txt" 2> /dev/null
    n=$(grep -vc '^missing:' "$DEST/logs/device-tar-errors.txt")
    if [ "${n:-0}" -gt 0 ]; then
      warn "tar printed $n messages on the phone (files changing or unreadable). See logs/device-tar-errors.txt"
    fi
  fi
}

do_verify() {
  local dir=${1:-}
  if [ -z "$dir" ]; then dir=$(find "$HOME/cheetah-dual/backup" -maxdepth 1 -type d -name 'android-*' 2> /dev/null | sort | tail -1); fi
  [ -f "$dir/SHA256SUMS" ] || { echo "no SHA256SUMS in '$dir'"; return 1; }
  echo "verifying $dir ..."
  ( cd "$dir" && shasum -a 256 -c SHA256SUMS > "$dir/.verify.txt" 2>&1 )
  local bad
  bad=$(grep -vc ': OK$' "$dir/.verify.txt")
  if [ "$bad" = 0 ]; then echo "ALL FILES OK ($(wc -l < "$dir/.verify.txt" | tr -d ' ') files)"; rm -f "$dir/.verify.txt"; return 0; fi
  grep -v ': OK$' "$dir/.verify.txt" | head -20
  echo "PROBLEMS: $bad (details in $dir/.verify.txt)"
  return 1
}

summary() {
  local secs=$(( $(date +%s) - START_TS ))
  say ""
  say "================ SUMMARY ================"
  say "folder : $DEST"
  say "size   : $(du -sh "$DEST" 2> /dev/null | awk '{ print $1 }')"
  say "time   : $((secs / 3600)) h $(((secs % 3600) / 60)) min"
  say "OK=$N_OK  SKIP(already done)=$N_SKIP  WARN=$N_WARN  FAIL=$N_FAIL"
  if [ "$N_FAIL" -gt 0 ]; then
    say "Failed items:$FAILED"
    say "Run the same command again: finished items are skipped and only the failed ones are retried."
  else
    say "BACKUP-OK"
  fi
  say "Secrets inside (Wi-Fi passwords, Bluetooth keys, app data): keep this folder encrypted, for example:"
  say "  hdiutil create -encryption AES-256 -srcfolder \"$DEST\" -volname android-backup \"$DEST.dmg\""
  say "Re-check any time:  bash \"$KIT_DIR/android-full-backup.sh\" verify"
}

main() {
  case "${1:-run}" in
    verify) shift; do_verify "$@"; exit $? ;;
    run) ;;
    help|-h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1 (use: run | verify | help)"; exit 1 ;;
  esac
  preflight
  in_want manifest   && step_manifest
  in_want settings   && step_settings
  in_want contacts   && step_contacts
  in_want root       && step_root
  in_want switch     && step_switch
  in_want partitions && step_partitions
  in_want apps       && step_apps
  in_want media      && step_media
  pull_device_errors
  step_checksums
  summary
  [ "$N_FAIL" = 0 ]
}

main "$@"
