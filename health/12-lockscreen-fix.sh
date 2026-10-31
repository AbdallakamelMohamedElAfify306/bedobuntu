# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 12-lockscreen-fix.sh
# Phase 1c - targeted LOCK SCREEN fixes. Default is a dry run; add --apply to change things.
# shellcheck disable=SC2015,SC2016
# Usage: bash 12-lockscreen-fix.sh [--apply] FIX [FIX ...]
# FIX is one of:
#   tz                  set timezone ${CHEETAH_TZ:-UTC} (lock screen clock shows UTC unless CHEETAH_TZ is set)
#   clock24             24-hour clock + show date
#   autolock SECONDS    idle-delay=SECONDS, lock-enabled=true, lock-delay=0   (e.g. autolock 120)
#   notif-on|notif-off  show / hide notifications on the lock screen
#   keypad-fixed        PIN pad digits stay in order (shuffle-keypad=false)
#   top-panel-stock     move the clock-hiding top-panel.ui overlay to backup (stock top bar returns)
#   osk-start           best effort: start /usr/local/bin/phosh-osk-stub inside the session
#   restart-phosh       restart the phosh service (applies overlay changes; closes open apps)
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log

setgs() { # setgs SCHEMA KEY VALUE
  if [ "$APPLY" = 1 ]; then
    if gs set "$1" "$2" "$3" >> "$LOG" 2>&1; then ok "gsettings $1 $2 = $3 (now: $(gs get "$1" "$2"))"; else fail "gsettings set $1 $2 $3 failed (schema missing or phosh not running)"; fi
  else dry "gsettings set $1 $2 $3   (current: $(gs get "$1" "$2"))"; fi
}

set -- "${REST_ARGS[@]}"
[ "$#" -gt 0 ] || { fail "give at least one FIX (see the header of this script)"; finish; exit 1; }
while [ "$#" -gt 0 ]; do
  f=$1; shift
  sect "fix: $f"
  case "$f" in
    tz)
      if [ "$APPLY" = 1 ]; then timedatectl set-timezone ${CHEETAH_TZ:-UTC} >> "$LOG" 2>&1 && ok "timezone ${CHEETAH_TZ:-UTC} ($(date '+%F %T %Z'))" || fail "set-timezone failed"
      else dry "timedatectl set-timezone ${CHEETAH_TZ:-UTC} (now $(timedatectl show -p Timezone --value 2>/dev/null))"; fi ;;
    clock24)
      setgs org.gnome.desktop.interface clock-format "'24h'"
      setgs org.gnome.desktop.interface clock-show-date true ;;
    autolock)
      n=${1:-120}; shift
      case "$n" in '') fail "autolock needs a number of seconds"; continue;; esac
      setgs org.gnome.desktop.session idle-delay "uint32 $n"
      setgs org.gnome.desktop.screensaver lock-enabled true
      setgs org.gnome.desktop.screensaver lock-delay "uint32 0"
      pgrep -f 'gnome-session|gsd-power|gnome-settings-daemon' >/dev/null
      if [ $? -ne 0 ]; then
        warn "no gnome-session/gsd-power is running, so these settings alone will NOT blank the screen. phosh was started bare. Manual (advanced): start phosh through gnome-session (ExecStart=/usr/bin/gnome-session --session=phosh) after checking 'systemctl cat $(phosh_unit)'. Not changed by this script."
      fi ;;
    notif-on) setgs org.gnome.desktop.notifications show-in-lock-screen true ;;
    notif-off) setgs org.gnome.desktop.notifications show-in-lock-screen false ;;
    keypad-fixed) setgs sm.puri.phosh.lockscreen shuffle-keypad false ;;
    top-panel-stock)
      OV=/opt/phosh-overlay/sm/puri/phosh/ui/top-panel.ui
      if [ -f "$OV" ]; then
        if [ "$APPLY" = 1 ]; then
          mkdir -p "$HEALTH_DIR/backup/ui-$TS" && mv "$OV" "$HEALTH_DIR/backup/ui-$TS/top-panel.ui" && ok "overlay moved to $HEALTH_DIR/backup/ui-$TS/top-panel.ui (clock visible again after restart-phosh)"
          info "restore with: mv $HEALTH_DIR/backup/ui-$TS/top-panel.ui $OV"
        else dry "mv $OV -> backup (top bar clock becomes visible)"; fi
      else ok "no overlay present"; fi ;;
    osk-start)
      OSK=/usr/local/bin/phosh-osk-stub
      if { [ -x "$OSK"  ]; [ $? -ne 0 ]; }; then fail "$OSK missing"; continue; fi
      if pgrep -f 'phosh-osk' >/dev/null; then ok "an OSK process is already running"; continue; fi
      xr=$(phosh_env XDG_RUNTIME_DIR); wd=$(phosh_env WAYLAND_DISPLAY); db=$(phosh_env DBUS_SESSION_BUS_ADDRESS)
      xr=${xr:-/run/user/1000}; wd=${wd:-wayland-0}; db=${db:-unix:path=$xr/bus}
      if [ "$APPLY" = 1 ]; then
        setsid runuser -u user -- env "XDG_RUNTIME_DIR=$xr" "WAYLAND_DISPLAY=$wd" "DBUS_SESSION_BUS_ADDRESS=$db" "$OSK" >> "$LOG" 2>&1 < /dev/null &
        sleep 3
        pgrep -f 'phosh-osk' >/dev/null && ok "OSK started (best effort; it is not persistent across restarts)" || fail "OSK did not stay up - see: journalctl -b | grep -i osk ; and /root/osk-tweaks.sh"
      else dry "start $OSK as user with WAYLAND_DISPLAY=$wd"; fi ;;
    restart-phosh)
      u=$(phosh_unit) || { fail "cannot find the phosh unit"; continue; }
      act "systemctl restart $u" systemctl restart "$u" ;;
    *) fail "unknown fix '$f'" ;;
  esac
done
[ "$APPLY" = 1 ] || info "DRY RUN. Re-run with --apply to change things."
finish
