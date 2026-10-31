# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=bash
# lib.sh - shared helpers for the cheetah health kit. Sourced by every script. Never writes to block devices.
# Env: HEALTH_DIR (default /root/health), HEALTH_TEST=1 (skip root check; used only for offline tests)

HEALTH_DIR=${HEALTH_DIR:-/root/health}
TS=$(date +%Y%m%d-%H%M%S)
SCRIPT_NAME=$(basename "${0%.sh}")
APPLY=0
QUIET=0
N_OK=0
N_WARN=0
N_FAIL=0
REST_ARGS=()

parse_args() {
  REST_ARGS=()
  local a
  for a in "$@"; do
    case "$a" in
      --apply) APPLY=1 ;;
      --check|--dry-run) APPLY=0 ;;
      --quiet) QUIET=1 ;;
      *) REST_ARGS+=("$a") ;;
    esac
  done
}

init_log() {
  if { case "${HEALTH_TEST:-0}" in 1) false;; *) true;; esac; } && { case "$(id -u)" in 0) false;; *) true;; esac; }; then
    echo "[FAIL] must run as root (use the ssh command from the guide)"; exit 2
  fi
  mkdir -p "$HEALTH_DIR/backup" 2>/dev/null || { echo "[FAIL] cannot create $HEALTH_DIR"; exit 2; }
  LOG="$HEALTH_DIR/$SCRIPT_NAME-$TS.log"
  TSV="$HEALTH_DIR/last-$SCRIPT_NAME.tsv"
  : > "$LOG"; : > "$TSV"
  say "# $SCRIPT_NAME  $(date -Is)  mode=$([ "$APPLY" = 1 ] && echo APPLY || echo CHECK)  host=$(hostname)"
}

say() { printf '%s\n' "$*" >> "$LOG"; [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
sect() { say ""; say "=== $* ==="; }
info() { say "[INFO] $*"; }
ok() { N_OK=$((N_OK + 1)); say "[OK]   $*"; }
warn() { N_WARN=$((N_WARN + 1)); say "[WARN] $*"; }
fail() { N_FAIL=$((N_FAIL + 1)); say "[FAIL] $*"; }
dry() { say "[DRY]  would: $*"; }

# rec AREA STATUS(OK|WARN|FAIL|INFO|N/A) DETAIL : adds a row to the summary table and prints the matching marker
rec() {
  local area=$1 st=$2 det=${3:-}
  printf '%s\t%s\t%s\n' "$area" "$st" "$det" >> "$TSV"
  case "$st" in
    OK) ok "$area: $det" ;;
    WARN) warn "$area: $det" ;;
    FAIL) fail "$area: $det" ;;
    *) info "$area [$st]: $det" ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# cap CMD... : run, log full output, show at most MAXL lines (default 40) on screen
cap() {
  local out
  say "\$ $*"
  out=$("$@" 2>&1); local rc=$?
  printf '%s\n' "$out" >> "$LOG"
  if { case "$QUIET" in 1) false;; *) true;; esac; }; then printf '%s\n' "$out" | head -n "${MAXL:-40}"; fi
  return $rc
}

# capsh 'shell pipeline' : like cap but for a shell string
capsh() {
  local out
  say "\$ $1"
  out=$(bash -c "$1" 2>&1); local rc=$?
  printf '%s\n' "$out" >> "$LOG"
  if { case "$QUIET" in 1) false;; *) true;; esac; }; then printf '%s\n' "$out" | head -n "${MAXL:-40}"; fi
  return $rc
}

backup() { # backup FILE  (copies to $HEALTH_DIR/backup, keeps original in place)
  local f=$1 d
  [ -e "$f" ] || return 0
  d="$HEALTH_DIR/backup/$(printf '%s' "$f" | tr '/' '_').$TS"
  cp -a "$f" "$d" && info "backup: $f -> $d"
}

# act DESCRIPTION CMD... : runs the command only in --apply mode
act() {
  local d=$1; shift
  if [ "$APPLY" = 1 ]; then
    if "$@" >> "$LOG" 2>&1; then ok "$d"; return 0; else fail "$d (command failed: $*)"; return 1; fi
  else
    dry "$d"; return 0
  fi
}

phosh_pid() { pgrep -o -x phosh 2>/dev/null; }

phosh_unit() {
  local p cg u
  p=$(phosh_pid) || p=""
  if [ -n "$p" ]; then
    cg=$(sed -n 's/^0:://p' "/proc/$p/cgroup" 2>/dev/null)
    u=$(printf '%s' "$cg" | grep -o '[^/]*\.service' | tail -n1)
    if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
  fi
  for u in pixel-phosh.service phosh.service; do
    if systemctl cat "$u" >/dev/null 2>&1; then printf '%s' "$u"; return 0; fi
  done
  return 1
}

phosh_env() { # phosh_env VAR -> value from the running phosh process
  local p; p=$(phosh_pid) || return 1
  tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n "s/^$1=//p" | head -n1
}

# gs ARGS... : run gsettings as user 'user' inside phosh's session bus. Prints 'n/a' when impossible.
gs() {
  local p xr dbus
  p=$(phosh_pid) || { echo "n/a(no-phosh)"; return 1; }
  xr=$(phosh_env XDG_RUNTIME_DIR); dbus=$(phosh_env DBUS_SESSION_BUS_ADDRESS)
  [ -n "$xr" ] || xr=/run/user/1000
  [ -n "$dbus" ] || dbus="unix:path=$xr/bus"
  have gsettings || { echo "n/a(no-gsettings)"; return 1; }
  local out
  if out=$(runuser -u user -- env "XDG_RUNTIME_DIR=$xr" "DBUS_SESSION_BUS_ADDRESS=$dbus" gsettings "$@" 2>&1); then
    printf '%s\n' "$out"
  else
    echo "n/a"; return 1
  fi
}

# ubus ARGS... : run a command as user 'user' on phosh's session bus (busctl --user ...)
ubus() {
  local xr dbus
  phosh_pid >/dev/null || return 1
  xr=$(phosh_env XDG_RUNTIME_DIR); dbus=$(phosh_env DBUS_SESSION_BUS_ADDRESS)
  [ -n "$xr" ] || xr=/run/user/1000
  [ -n "$dbus" ] || dbus="unix:path=$xr/bus"
  runuser -u user -- env "XDG_RUNTIME_DIR=$xr" "DBUS_SESSION_BUS_ADDRESS=$dbus" "$@"
}

wifi_iface() {
  if [ -n "${WIFI_IFACE:-}" ]; then printf "%s" "$WIFI_IFACE"; return 0; fi
  local d
  for d in /sys/class/net/*; do
    if [ -d "$d/wireless" ] || [ -d "$d/phy80211" ]; then basename "$d"; return 0; fi
  done
  return 1
}

say_always() { printf '%s\n' "$*" >> "$LOG"; printf '%s\n' "$*"; }

finish() {
  say_always ""
  say_always "SUMMARY $SCRIPT_NAME: ok=$N_OK warn=$N_WARN fail=$N_FAIL   log=$LOG"
  if [ "$N_FAIL" -gt 0 ]; then say_always "RESULT: FAIL"; return 1
  elif [ "$N_WARN" -gt 0 ]; then say_always "RESULT: WARN"; return 0
  else say_always "RESULT: PASS"; return 0; fi
}

print_table() { # print_table TSVFILE
  [ -s "$1" ] || return 0
  awk -F'\t' 'BEGIN{printf "%-26s %-6s %s\n","AREA","STATUS","DETAIL"; printf "%-26s %-6s %s\n","--------------------------","------","------"} {printf "%-26s %-6s %s\n",$1,$2,$3}' "$1" | tee -a "$LOG"
}
