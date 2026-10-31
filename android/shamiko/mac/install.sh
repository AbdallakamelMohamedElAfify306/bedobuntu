# SPDX-License-Identifier: GPL-3.0-or-later
# Mac-side Shamiko kit. Usage:
#   bash $HOME/cheetah-dual/shamiko-kit/mac/install.sh
#   bash $HOME/cheetah-dual/shamiko-kit/mac/install.sh verify
# Requires: adb, phone on Android with USB debugging, Magisk su granting shell.
# Does NOT flash bootloader, touch Ubuntu slot b / sda33 / userdata, or uninstall Magisk.

set -e
MODE="${1:-install}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)
LOGDIR="$HOME/cheetah-dual/shamiko-logs"
mkdir -p "$LOGDIR"
MACLOG="$LOGDIR/run-$STAMP.log"
PHONE_DIR=/data/local/tmp/shamiko-kit
SDCARD_ZIP=/sdcard/Download/Shamiko-v1.2.5-414-release.zip
ASSET_ZIP="$ROOT/assets/Shamiko-v1.2.5-414-release.zip"

log() { echo "[$STAMP] $*" | tee -a "$MACLOG"; }

need_adb() {
  if adb get-state >/dev/null 2>&1; then
    :
  else
    log "ERROR: no adb device. Unlock phone, allow USB debugging, then retry."
    exit 1
  fi
  if adb shell su -c id 2>/dev/null | grep -q uid=0; then
    :
  else
    log "ERROR: su not working for adb shell. Open Magisk and grant Shell root, then retry."
    exit 1
  fi
}

push_kit() {
  log "pushing kit to $PHONE_DIR and $SDCARD_ZIP"
  if [ -f "$ASSET_ZIP" ]; then
    :
  else
    log "ERROR: missing $ASSET_ZIP"
    log "Download from: https://github.com/LSPosed/LSPosed.github.io/releases/download/shamiko-414/Shamiko-v1.2.5-414-release.zip"
    log "Place it at: $ASSET_ZIP"
    exit 1
  fi
  adb shell "mkdir -p $PHONE_DIR /sdcard/Download"
  adb push "$ROOT/phone/10-install.sh" "$PHONE_DIR/10-install.sh" >/dev/null
  adb push "$ROOT/phone/20-verify.sh" "$PHONE_DIR/20-verify.sh" >/dev/null
  adb push "$ASSET_ZIP" "$PHONE_DIR/Shamiko-v1.2.5-414-release.zip" >/dev/null
  adb push "$ASSET_ZIP" "$SDCARD_ZIP" >/dev/null
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

run_install() {
  log "running Shamiko install on phone"
  adb shell su -c "sh $PHONE_DIR/10-install.sh"
  pull_file "$PHONE_DIR/install-log.txt" "install-$STAMP.txt"
  if [ -s "$LOGDIR/install-$STAMP.txt" ]; then
    log "---- install tail ----"
    tail -100 "$LOGDIR/install-$STAMP.txt" | tee -a "$MACLOG"
  fi
}

run_verify() {
  log "running verify on phone"
  adb shell su -c "sh $PHONE_DIR/20-verify.sh $PHONE_DIR/verify.txt"
  pull_file "$PHONE_DIR/verify.txt" "verify-$STAMP.txt"
  if [ -s "$LOGDIR/verify-$STAMP.txt" ]; then
    log "---- verify summary ----"
    grep -E "^(====|== |STATUS|LAUNCH|RUNNING|NOT_RUNNING|SKIP|Manager|development_|adb_|whitelist|VERIFY)" "$LOGDIR/verify-$STAMP.txt" | tee -a "$MACLOG" || true
  fi
}

log "ROOT=$ROOT MODE=$MODE LOGDIR=$LOGDIR"
need_adb
push_kit

case "$MODE" in
  verify)
    run_verify
    log "DONE verify. Full log: $LOGDIR/verify-$STAMP.txt"
    log "If apps still refuse: turn OFF Developer options, then retry each app."
    log "LIMIT: unlocked bootloader cannot pass Strong / hardware attestation."
    ;;
  install|all|"")
    run_install
    log ""
    log "============================================================"
    log "Shamiko install applied. Phone must REBOOT."
    log "Run when ready:"
    log "  adb reboot"
    log "After phone is up (1-2 min), run:"
    log "  bash $ROOT/mac/install.sh verify"
    log ""
    log "CHECK in Magisk Settings after reboot:"
    log "  Zygisk = ON"
    log "  Enforce DenyList = OFF"
    log "  Configure DenyList = bank apps with ALL processes ticked"
    log ""
    log "Zygisk-Assistant was soft-disabled (disable file). Shamiko is the hider."
    log "PlayIntegrityFork left alone."
    log ""
    log "LIMIT: Shamiko hides Magisk from DenyList apps. It does NOT lock the"
    log "bootloader or forge Strong integrity. HSBC / NBE / Instapay may still"
    log "refuse if they require hardware attestation."
    log "Logs: $LOGDIR"
    log "============================================================"
    ;;
  reboot)
    log "rebooting phone"
    adb reboot
    ;;
  *)
    log "Usage: bash $ROOT/mac/install.sh [install|verify|reboot]"
    exit 2
    ;;
esac
