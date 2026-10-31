# SPDX-License-Identifier: GPL-3.0-or-later
# Mac-side kit. Usage:
#   bash $HOME/cheetah-dual/roothide-fix/fix-all.sh
#   bash $HOME/cheetah-dual/roothide-fix/fix-all.sh verify
# Requires: adb, phone on Android with USB debugging, Magisk su granting shell.

set -e
MODE="${1:-fix}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)
LOGDIR="$HOME/cheetah-dual/roothide-logs"
mkdir -p "$LOGDIR"
MACLOG="$LOGDIR/run-$STAMP.log"
PHONE_DIR=/data/local/tmp/roothide-fix

log() { echo "[$STAMP] $*" | tee -a "$MACLOG"; }

need_adb() {
  if adb get-state >/dev/null 2>&1; then
    :
  else
    log "ERROR: no adb device. Unlock phone, allow USB debugging, then retry."
    exit 1
  fi
  # root check
  if adb shell su -c id 2>/dev/null | grep -q uid=0; then
    :
  else
    log "ERROR: su not working for adb shell. Open Magisk and grant Shell root, then retry."
    exit 1
  fi
}

push_kit() {
  log "pushing kit to $PHONE_DIR"
  adb shell "mkdir -p $PHONE_DIR" 
  adb push "$ROOT/phone/00-diagnose.sh" "$PHONE_DIR/00-diagnose.sh" >/dev/null
  adb push "$ROOT/phone/10-fix.sh" "$PHONE_DIR/10-fix.sh" >/dev/null
  adb push "$ROOT/phone/20-verify.sh" "$PHONE_DIR/20-verify.sh" >/dev/null
  adb push "$ROOT/phone/props-spoof.sh" "$PHONE_DIR/props-spoof.sh" >/dev/null
  if [ -f "$ROOT/assets/Zygisk-Assistant-v2.1.4.zip" ]; then
    adb push "$ROOT/assets/Zygisk-Assistant-v2.1.4.zip" "$PHONE_DIR/Zygisk-Assistant-v2.1.4.zip" >/dev/null
  else
    log "WARN: Zygisk-Assistant zip missing in assets/"
  fi
  adb shell su -c "chmod 755 $PHONE_DIR/*.sh"
}

pull_file() {
  remote="$1"; localname="$2"
  adb exec-out su -c "cat $remote" >"$LOGDIR/$localname" 2>/dev/null || adb shell su -c "cat $remote" >"$LOGDIR/$localname" 2>/dev/null || true
  if [ -s "$LOGDIR/$localname" ]; then
    log "saved $LOGDIR/$localname ($(wc -c <"$LOGDIR/$localname") bytes)"
  else
    log "WARN: could not pull $remote"
  fi
}

run_diagnose() {
  log "running diagnose on phone"
  adb shell su -c "sh $PHONE_DIR/00-diagnose.sh $PHONE_DIR/diag.txt"
  pull_file "$PHONE_DIR/diag.txt" "diag-$STAMP.txt"
  # also print a short summary
  if [ -s "$LOGDIR/diag-$STAMP.txt" ]; then
    log "---- diagnose summary ----"
    grep -E "^(====|== |MAGISK_|INSTALLED|MISSING|Denylist|value=|ro\.|development_|adb_|EXISTS|absent|FOUND|NOT_INSTALLED|INSTALLED|custom\.pif|MANUAL|package:|zygisk|playintegrity)" "$LOGDIR/diag-$STAMP.txt" | tee -a "$MACLOG" || true
  fi
}

run_fix() {
  log "running fix on phone (this can take 1-3 minutes)"
  adb shell su -c "sh $PHONE_DIR/10-fix.sh"
  pull_file "$PHONE_DIR/fix-log.txt" "fix-$STAMP.txt"
  if [ -s "$LOGDIR/fix-$STAMP.txt" ]; then
    log "---- fix tail ----"
    tail -80 "$LOGDIR/fix-$STAMP.txt" | tee -a "$MACLOG"
  fi
}

run_verify() {
  log "running verify on phone"
  adb shell su -c "sh $PHONE_DIR/20-verify.sh $PHONE_DIR/verify.txt"
  pull_file "$PHONE_DIR/verify.txt" "verify-$STAMP.txt"
  if [ -s "$LOGDIR/verify-$STAMP.txt" ]; then
    log "---- verify summary ----"
    grep -E "^(====|== |LAUNCH|RUNNING|NOT_RUNNING|SKIP|STILL_|Manager|development_|adb_|ro\.|Denylist|active|MISSING|DISABLED|present|VERIFY)" "$LOGDIR/verify-$STAMP.txt" | tee -a "$MACLOG" || true
  fi
}

log "ROOT=$ROOT MODE=$MODE LOGDIR=$LOGDIR"
need_adb
push_kit

case "$MODE" in
  diagnose|diag)
    run_diagnose
    log "DONE diagnose. Full log: $LOGDIR/diag-$STAMP.txt"
    ;;
  verify)
    run_verify
    log "DONE verify. Full log: $LOGDIR/verify-$STAMP.txt"
    log "If apps still refuse: turn OFF Developer options, uninstall Magisk Manager APK only, reboot, retry."
    ;;
  fix|all|"")
    run_diagnose
    run_fix
    log ""
    log "============================================================"
    log "FIX applied. Phone must REBOOT for Zygisk + ZA + props."
    log "Run this when ready:"
    log "  adb reboot"
    log "After phone is up (1-2 min), run:"
    log "  bash $ROOT/fix-all.sh verify"
    log ""
    log "MANUAL after reboot (important for Egyptian banks):"
    log "  1) Magisk 31.1 has no Hide Magisk app. Uninstall Magisk Manager from Settings-Apps (root stays)."
    log "  2) Turn OFF Developer options (Settings - System - Developer options)."
    log "     Do this last; it cuts adb."
    log "  3) Open each bank app once (data was cleared; you will log in again)."
    log ""
    log "LIMITS: unlocked bootloader cannot reliably pass DEVICE/STRONG Play Integrity."
    log "HSBC/NBE/Instapay may still refuse if they require hardware attestation."
    log "Logs: $LOGDIR"
    log "============================================================"
    ;;
  reboot)
    log "rebooting phone"
    adb reboot
    ;;
  *)
    log "Usage: bash $ROOT/fix-all.sh [fix|diagnose|verify|reboot]"
    exit 2
    ;;
esac
