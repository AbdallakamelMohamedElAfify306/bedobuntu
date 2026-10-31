# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 11-lockscreen-check.sh
# Phase 1b - LOCK SCREEN inspection. Read-only. Looks for the usual causes of "something is off on the lock screen".
# shellcheck disable=SC2015,SC2012,SC2010,SC2016
# Usage: bash 11-lockscreen-check.sh [--quiet]
# Phosh 0.38 facts used (from the phosh source): the lock screen has its own clock/date labels
# (phosh-lockscreen-clock / phosh-lockscreen-date), a PIN entry + keypad, a keyboard button that needs the OSK
# (D-Bus name sm.puri.OSK0), notifications gated by org.gnome.desktop.notifications show-in-lock-screen, and
# auto-blank/lock driven by org.gnome.desktop.session idle-delay + org.gnome.desktop.screensaver lock-enabled/lock-delay,
# which are acted on by gnome-session / gnome-settings-daemon (phosh itself does not watch idle-delay).
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log

OV=/opt/phosh-overlay/sm/puri/phosh/ui/top-panel.ui
U=$(phosh_unit); P=$(phosh_pid)
[ -n "$P" ] || { rec "Phosh running" FAIL "phosh not running - nothing on the lock screen can work"; }

sect "L1. leftover overrides in /opt/phosh-overlay"
find /opt/phosh-overlay -type f -printf '%p  (%s bytes, %TY-%Tm-%Td %TH:%TM)\n' 2>/dev/null >> "$LOG"
extra=$(find /opt/phosh-overlay -type f -not -path '*/sm/puri/phosh/ui/top-panel.ui' 2>/dev/null)
if [ -z "$extra" ]; then rec "Overlay files" OK "only ui/top-panel.ui (expected)"; else rec "Overlay files" FAIL "unexpected files: $(printf '%s' "$extra" | tr '\n' ' ') - run 00-step0-undo-wallpaper.sh --apply"; fi
ov=$(phosh_env G_RESOURCE_OVERLAYS); info "running G_RESOURCE_OVERLAYS=${ov:-<none>}"
case "$ov" in *stylesheet=*) rec "Running overlays" FAIL "stylesheet override still loaded by running phosh (restart needed)";; *) rec "Running overlays" OK "no stylesheet override";; esac
if [ -n "$U" ]; then
  cfg=$(systemctl show -p Environment --value "$U" 2>/dev/null | tr ' ' '\n' | sed -n 's/^G_RESOURCE_OVERLAYS=//p' | tr -d '"' | head -n1)
  [ "$cfg" = "$ov" ] && rec "Unit vs process" OK "service config matches the running process" || rec "Unit vs process" WARN "unit says '${cfg:-none}' but process has '${ov:-none}' (restart phosh to apply)"
fi
for g in /home/user/.config/gtk-3.0/gtk.css /home/user/.config/gtk-4.0/gtk.css; do
  [ -f "$g" ] && { grep -qE 'phosh|lockscreen|lockshield|background' "$g" && rec "User gtk.css" WARN "$g contains phosh/background rules (can recolor the lock screen)" || info "$g exists, no phosh rules"; }
done
bw=$(find /etc /usr/local /opt /home/user/.config -name '*.bak-wall' 2>/dev/null | head -n 5 | tr '\n' ' '); [ -z "$bw" ] && rec "Leftover .bak-wall" OK none || rec "Leftover .bak-wall" WARN "$bw"

sect "L2. top-panel.ui overlay (hidden clock) sanity"
if [ -f "$OV" ]; then
  need="arrow batteryinfo box box_clock box_top_bar btn_lock btn_power click_gesture lbl_clock lbl_clock2 lbl_date lbl_lang menu_system settings stack"
  miss=""
  for i in $need; do grep -q "id=\"$i\"" "$OV" || miss="$miss $i"; done
  [ -z "$miss" ] && rec "top-panel.ui template ids" OK "all 15 children phosh binds are present" || rec "top-panel.ui template ids" FAIL "missing ids:$miss (phosh will log criticals / misbehave)"
  if have xmllint; then xmllint --noout "$OV" 2>>"$LOG" && rec "top-panel.ui XML" OK "well-formed" || rec "top-panel.ui XML" FAIL "not well-formed"
  elif have python3; then python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "$OV" 2>>"$LOG" && rec "top-panel.ui XML" OK "well-formed" || rec "top-panel.ui XML" FAIL "not well-formed"
  else info "no xmllint/python3: XML not parsed"; fi
  say "  lines mentioning opacity/visibility in the overlay:"
  grep -nE 'opacity|name="visible">False|no-show-all|"sensitive">False' "$OV" | head -n 15 | sed 's/^/    /' | tee -a "$LOG" > /dev/null
  [ "$QUIET" = 1 ] || grep -nE 'opacity|name="visible">False|no-show-all' "$OV" | head -n 15 | sed 's/^/    /'
  # compare with stock UI embedded in phosh
  stock=""
  if have gresource; then
    for f in /usr/libexec/phosh /usr/lib/aarch64-linux-gnu/libphosh-0.38.so /usr/lib/*/libphosh*.so*; do
      [ -e "$f" ] || continue
      t=$(gresource extract "$f" /sm/puri/phosh/ui/top-panel.ui 2>/dev/null) && [ -n "$t" ] && { stock="$t"; break; }
    done
  fi
  if [ -n "$stock" ]; then
    printf '%s\n' "$stock" > "$HEALTH_DIR/top-panel.ui.stock"
    d=$(diff -u "$HEALTH_DIR/top-panel.ui.stock" "$OV" | head -n 60)
    say "  diff stock -> overlay (saved stock copy: $HEALTH_DIR/top-panel.ui.stock):"
    printf '%s\n' "$d" | sed 's/^/    /' >> "$LOG"; [ "$QUIET" = 1 ] || printf '%s\n' "$d" | sed 's/^/    /' | head -n 40
    nl=$(printf '%s\n' "$d" | grep -cE '^[+-][^+-]')
    [ "$nl" -le 8 ] && rec "top-panel.ui vs stock" OK "$nl changed lines (small, clock tweak only)" || rec "top-panel.ui vs stock" WARN "$nl changed lines: more than a clock tweak, review the diff in the log"
    if printf '%s\n' "$d" | grep -E '^[+-]' | grep -qE 'lbl_clock2|lbl_date|btn_lock|batteryinfo|menu_system|box_top_bar'; then rec "Overlay touches other widgets" WARN "diff changes lbl_clock2/lbl_date/btn_lock/battery/system menu (date missing in the drawer? lock button gone?)"; else rec "Overlay touches other widgets" OK "only the top-bar clock"; fi
  else info "could not extract stock top-panel.ui (gresource tool/binary not available): diff skipped"; fi
else
  rec "top-panel.ui overlay" INFO "no overlay file: stock top bar (clock visible)"
fi

sect "L3. lock screen clock / date visibility"
tzs=$(timedatectl show -p Timezone --value 2>/dev/null); info "system timezone: ${tzs:-unknown}  local time: $(date '+%F %T %Z')"
if [ -z "$tzs" ]; then rec "Clock timezone" INFO "timedatectl unavailable"; elif [ "$tzs" = UTC ] || [ "$tzs" = Etc/UTC ]; then rec "Clock timezone" WARN "timezone is UTC: the lock screen clock is 3 hours behind Cairo (fix: 12-lockscreen-fix.sh --apply tz)"; else rec "Clock timezone" OK "$tzs"; fi
ntp=$(timedatectl show -p NTPSynchronized --value 2>/dev/null); [ "$ntp" = yes ] && rec "Clock synced (NTP)" OK yes || rec "Clock synced (NTP)" WARN "not NTP-synchronized: lock clock may be wrong (21-repair-system.sh time)"
cf=$(gs get org.gnome.desktop.interface clock-format); sd=$(gs get org.gnome.desktop.interface clock-show-date); ss=$(gs get org.gnome.desktop.interface clock-show-seconds)
info "clock-format=$cf clock-show-date=$sd clock-show-seconds=$ss"
case "$cf" in *12h*) rec "Clock format" INFO "12h clock (lock screen shows AM/PM); set 24h with 12-lockscreen-fix.sh clock24";; *24h*) rec "Clock format" OK "24h";; *) rec "Clock format" INFO "gsettings not readable ($cf)";; esac
l=$(locale 2>/dev/null | head -n1); info "$l"
css=$(journalctl -b --no-pager -q -u "${U:-pixel-phosh}" 2>/dev/null | grep -iE 'lockscreen|lockshield|css|parsing|Gtk-WARNING|Gtk-CRITICAL' | tail -n 8 | cut -c1-200)
[ -z "$css" ] && rec "Lock/CSS log warnings" OK "none from phosh" || { rec "Lock/CSS log warnings" WARN "phosh logged CSS/Gtk warnings (see log)"; printf '%s\n' "$css" >> "$LOG"; }
if have fc-list; then fc-list : family 2>/dev/null | grep -qi 'noto\|cantarell\|dejavu' && rec "Fonts" OK "common UI fonts present" || rec "Fonts" WARN "no Noto/Cantarell/DejaVu fonts: clock digits may render as boxes"; fi

sect "L4. PIN pad and on-screen keyboard"
sh=$(gs get sm.puri.phosh.lockscreen shuffle-keypad); info "shuffle-keypad=$sh (true = digits are randomized each time: users often think the pad is 'broken')"
case "$sh" in true) rec "PIN pad shuffle" INFO "keypad digits are shuffled (set false: 12-lockscreen-fix.sh keypad-fixed)";; *) rec "PIN pad shuffle" OK "$sh";; esac
[ -f /etc/pam.d/phosh ] && rec "PAM service 'phosh'" OK present || rec "PAM service 'phosh'" FAIL "/etc/pam.d/phosh missing: unlocking with the PIN/password cannot work"
ps=$(passwd -S user 2>/dev/null | awk '{print $2}'); case "$ps" in P) rec "user password state" OK "set";; L|LK) rec "user password state" FAIL "account password is LOCKED: lock screen cannot be unlocked";; NP) rec "user password state" WARN "NO password: lock screen unlock behaves oddly";; *) rec "user password state" INFO "${ps:-unknown}";; esac
[ -x /usr/local/bin/phosh-osk-stub ] && info "patched OSK present: /usr/local/bin/phosh-osk-stub" || rec "Patched OSK file" WARN "/usr/local/bin/phosh-osk-stub missing"
osk=$(pgrep -a -f 'phosh-osk|squeekboard|stevia' | head -n 3 | cut -c1-120)
[ -n "$osk" ] && rec "OSK process" OK "$osk" || rec "OSK process" WARN "no keyboard process running: the keyboard button on the lock screen does nothing"
if have busctl && [ -n "$P" ]; then
  own=$(ubus busctl --user --no-pager list 2>/dev/null | grep -E 'sm\.puri\.OSK0|org\.freedesktop\.Notifications|sm\.puri\.Phosh' | awk '{print $1}' | tr '\n' ' ')
  info "session bus names of interest: ${own:-none}"
  case "$own" in *sm.puri.OSK0*) rec "OSK D-Bus name" OK "sm.puri.OSK0 owned";; *) rec "OSK D-Bus name" WARN "nobody owns sm.puri.OSK0: lock screen keyboard button stays insensitive/blank";; esac
fi
sk=$(gs get org.gnome.desktop.a11y.applications screen-keyboard-enabled); info "a11y screen-keyboard-enabled=$sk"
[ -f /root/osk-tweaks.sh ] && info "/root/osk-tweaks.sh present" || info "/root/osk-tweaks.sh missing"
oe=$(journalctl -b --no-pager -q 2>/dev/null | grep -iE 'osk|stevia|squeekboard' | grep -iE 'error|critical|fail|segfault|abort' | tail -n 5 | cut -c1-180)
[ -z "$oe" ] && rec "OSK log errors" OK none || { rec "OSK log errors" WARN "keyboard logged errors (see log)"; printf '%s\n' "$oe" >> "$LOG"; }

sect "L5. status icons (top bar)"
sci=""
systemctl is-active upower >/dev/null 2>&1 || sci="$sci upower"
systemctl is-active NetworkManager >/dev/null 2>&1 || sci="$sci NetworkManager"
systemctl is-active bluetooth >/dev/null 2>&1 || sci="$sci bluetooth"
[ -z "$sci" ] && rec "Status-icon services" OK "upower, NetworkManager, bluetooth active" || rec "Status-icon services" WARN "inactive:$sci (their icons are missing from the top bar)"
dpkg -s adwaita-icon-theme >/dev/null 2>&1 && rec "Icon theme" OK "adwaita-icon-theme installed" || rec "Icon theme" WARN "adwaita-icon-theme missing: symbolic icons blank"
it=$(gs get org.gnome.desktop.interface icon-theme); info "icon-theme=$it"
bp=$(gs get org.gnome.desktop.interface show-battery-percentage); info "show-battery-percentage=$bp"
mi=$(journalctl -b --no-pager -q 2>/dev/null | grep -iE 'icon.*(not found|missing)|Could not load icon|Failed to load.*icon' | tail -n 5 | cut -c1-160); [ -z "$mi" ] && rec "Missing icons" OK "none logged" || { rec "Missing icons" WARN "icon load errors logged"; printf '%s\n' "$mi" >> "$LOG"; }
wb=$(gs get sm.puri.phosh wwan-backend); info "wwan-backend=$wb (no modem exposed -> no cellular icon, this is expected here)"
rfk=$(have rfkill && rfkill list 2>/dev/null | grep -c 'Soft blocked: yes'); [ "${rfk:-0}" -gt 0 ] && rec "rfkill" WARN "$rfk radio(s) soft-blocked (airplane mode?)" || rec "rfkill" OK "no soft blocks"

sect "L6. notifications on the lock screen"
sil=$(gs get org.gnome.desktop.notifications show-in-lock-screen); sb=$(gs get org.gnome.desktop.notifications show-banners)
info "show-in-lock-screen=$sil show-banners=$sb"
case "$sil" in true) rec "Notifications on lock screen" OK "enabled";; false) rec "Notifications on lock screen" WARN "disabled (set true with 12-lockscreen-fix.sh notif-on, or leave off for privacy)";; *) rec "Notifications on lock screen" INFO "unreadable ($sil)";; esac
if have busctl && [ -n "$P" ]; then ubus busctl --user --no-pager list 2>/dev/null | grep -q 'org.freedesktop.Notifications' && rec "Notification daemon" OK "org.freedesktop.Notifications owned (phosh)" || rec "Notification daemon" WARN "nobody owns org.freedesktop.Notifications"; fi
pl=$(gs get sm.puri.phosh.plugins lock-screen); info "lock-screen plugins: $pl"
systemctl is-active feedbackd >/dev/null 2>&1 && info "feedbackd active" || info "feedbackd not active (no haptic/sound on notifications)"
wk=$(gs get sm.puri.phosh.notifications wakeup-screen-triggers); info "wakeup-screen-triggers=$wk"

sect "L7. auto-lock / screen blank timeout"
idle=$(gs get org.gnome.desktop.session idle-delay); le=$(gs get org.gnome.desktop.screensaver lock-enabled); ld=$(gs get org.gnome.desktop.screensaver lock-delay)
info "idle-delay=$idle  lock-enabled=$le  lock-delay=$ld"
iv=$(printf '%s' "$idle" | tr -dc '0-9')
if [ -z "$iv" ]; then rec "idle-delay" INFO "unreadable ($idle)"
elif [ "$iv" = 0 ]; then rec "idle-delay" WARN "uint32 0 = screen NEVER blanks/locks by itself"
elif [ "$iv" -gt 600 ]; then rec "idle-delay" WARN "${iv}s (very long) - 12-lockscreen-fix.sh autolock 120"
else rec "idle-delay" OK "${iv}s"; fi
case "$le" in true) rec "lock-enabled" OK true;; false) rec "lock-enabled" WARN "false: screen blanks but does not lock (12-lockscreen-fix.sh autolock 120)";; *) rec "lock-enabled" INFO "unreadable ($le)";; esac
actor=$(pgrep -a -f 'gnome-session|gsd-power|gnome-settings-daemon' | head -n 3 | cut -c1-110)
[ -n "$actor" ] && rec "Idle handler" OK "$actor" || rec "Idle handler" WARN "no gnome-session/gsd-power running: nothing acts on idle-delay, so auto-blank/auto-lock cannot happen (phosh may have been started without gnome-session)"
cap_en=$(gs get sm.puri.phosh enable-suspend); info "phosh enable-suspend=$cap_en (the kernel s2idle is experimental here)"
sa=$(gs get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type); info "gsd power sleep-inactive-battery-type=$sa"
dm=$(gs get org.gnome.settings-daemon.plugins.power idle-dim); info "gsd idle-dim=$dm"
if have systemd-inhibit; then inh=$(systemd-inhibit --list --no-pager 2>/dev/null | grep -iE 'idle|sleep' | head -n 5 | cut -c1-140); [ -n "$inh" ] && { rec "Idle inhibitors" WARN "something blocks idle/sleep (see log)"; printf '%s\n' "$inh" >> "$LOG"; } || rec "Idle inhibitors" OK none; fi
sid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$3=="user"{print $1; exit}')
[ -n "$sid" ] && info "logind session $sid: $(loginctl show-session "$sid" -p Type -p State -p IdleHint -p LockedHint 2>/dev/null | tr '\n' ' ')"
[ -n "$P" ] && info "backlight: $(cat /sys/class/backlight/*/brightness 2>/dev/null | head -n1)/$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n1)"

sect "TABLE"
print_table "$TSV"
finish
