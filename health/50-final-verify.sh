# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 50-final-verify.sh
# Phase 5 - FINAL VERIFICATION (read-only): re-runs the key checks, includes the lock screen inspection, prints one summary table.
# shellcheck disable=SC2015,SC2016,SC2012,SC2010
# Usage: bash 50-final-verify.sh
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log
HERE=$(cd "$(dirname "$0")" && pwd)

sect "V1. core"
ov=$(phosh_env G_RESOURCE_OVERLAYS)
if [ -z "$(phosh_pid)" ]; then rec "Phosh running" FAIL "not running"; else rec "Phosh running" OK "pid $(phosh_pid) unit $(phosh_unit)"; fi
case "$ov" in *stylesheet=*) rec "Wallpaper override removed" FAIL "stylesheet still loaded";; *) [ -e /opt/phosh-overlay/sm/puri/phosh/stylesheet ] && rec "Wallpaper override removed" FAIL "directory still exists" || rec "Wallpaper override removed" OK "gone";; esac
case "$ov" in *"/sm/puri/phosh/ui="*) rec "Hidden-clock UI overlay" OK "active";; *) rec "Hidden-clock UI overlay" WARN "not active";; esac
nf=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l); [ "$nf" -eq 0 ] && rec "Failed units" OK none || rec "Failed units" WARN "$nf: $(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')"
[ -z "$(dpkg --audit 2>&1)" ] && rec "dpkg audit" OK clean || rec "dpkg audit" FAIL problems
apt-get check >/dev/null 2>&1 && rec "apt-get check" OK clean || rec "apt-get check" FAIL broken
r=$(ip -4 route get 1.1.1.1 2>/dev/null | head -n1)
case "$r" in *"dev usb0"*) rec "apt route" FAIL "via usb0";; "") rec "apt route" WARN "no route (Wi-Fi off?)";; *) rec "apt route" OK "$(printf '%s' "$r" | sed 's/ uid.*//' | cut -c1-70)";; esac
getent hosts ports.ubuntu.com >/dev/null 2>&1 && rec "DNS" OK "resolves" || rec "DNS" WARN "no resolution"
ip -4 route show | grep -q '172.16.42.0/24 dev usb0' && rec "USB SSH path" OK "usb0 subnet route present" || rec "USB SSH path" WARN "no usb0 route (cable?)"
sect "V2. repair results"
grep -q zram /proc/swaps && rec "zram swap" OK "$(awk '/zram/{print $1" "int($3/1024)"MB"}' /proc/swaps | head -n1)" || rec "zram swap" WARN "inactive"
[ -f /etc/systemd/journald.conf.d/10-cheetah.conf ] && rec "journald cap" OK "$(journalctl --disk-usage 2>/dev/null | sed 's/.*take up //;s/ in the.*//')" || rec "journald cap" WARN "not set"
systemctl is-enabled fstrim.timer >/dev/null 2>&1 && rec "fstrim timer" OK enabled || rec "fstrim timer" WARN disabled
[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] && rec "Time sync" OK "$(date '+%F %T %Z')" || rec "Time sync" WARN "not synchronized"
systemctl is-enabled cheetah-route-fix.service >/dev/null 2>&1 && rec "Route-fix service" OK enabled || rec "Route-fix service" INFO "not installed (20-fix-network.sh --apply)"
sect "V3. security"
dpkg -s unattended-upgrades >/dev/null 2>&1 && [ -f /etc/apt/apt.conf.d/52cheetah-unattended ] && rec "Unattended security updates" OK configured || rec "Unattended security updates" INFO "not set up"
h=$(apt-mark showhold | tr '\n' ' '); [ -n "$h" ] && rec "Held packages" OK "$h" || rec "Held packages" WARN "none held (31-sec-upgrade.sh --apply holds kernel/Mesa/Phosh)"
dpkg -s mesa-cheetah >/dev/null 2>&1 && rec "mesa-cheetah" OK "$(dpkg-query -W -f='${Version}' mesa-cheetah)" || rec "mesa-cheetah" WARN missing
pw=$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2}'); [ "$pw" = no ] && rec "SSH password login" OK disabled || rec "SSH password login" INFO "enabled (usb0 only)"
nft list ruleset 2>/dev/null | grep -qE "tcp dport 22" && rec "Firewall: ssh only on usb0" OK active || rec "Firewall: ssh only on usb0" FAIL "rule not active"
bash "$HERE/30-sec-audit.sh" --quiet >/dev/null 2>&1; sf=$(awk -F'\t' '$2=="FAIL"{print $1}' "$HEALTH_DIR/last-30-sec-audit.tsv" | tr '\n' ',' | sed 's/,$//')
[ -z "$sf" ] && rec "Security audit" OK "no FAIL rows" || rec "Security audit" FAIL "$sf"
sect "V4. custom tweaks preserved"
[ -x /usr/local/bin/phosh-osk-stub ] && rec "Patched OSK" OK present || rec "Patched OSK" FAIL missing
[ -f /root/osk-tweaks.sh ] && rec "osk-tweaks.sh" OK present || rec "osk-tweaks.sh" WARN missing
[ -f /etc/systemd/system/pixel-phosh.service.d/20-clock-right.conf ] && rec "20-clock-right.conf" OK present || rec "20-clock-right.conf" WARN missing
findmnt /mnt/shared >/dev/null 2>&1 && rec "/mnt/shared" OK mounted || rec "/mnt/shared" WARN "not mounted"
mount | grep -qE '/dev/sda31' && rec "Android userdata (sda31)" FAIL "MOUNTED in Ubuntu - unmount NOW" || rec "Android userdata (sda31)" OK "not mounted (untouched)"
findmnt -no SOURCE / | grep -q sda32 && rec "Root device" OK "$(findmnt -no SOURCE /)" || rec "Root device" INFO "$(findmnt -no SOURCE /)"
sect "V5. lock screen"
bash "$HERE/11-lockscreen-check.sh" --quiet >/dev/null 2>&1
lk="$HEALTH_DIR/last-11-lockscreen-check.tsv"
if [ -s "$lk" ]; then
  lf=$(awk -F'\t' '$2=="FAIL"{print $1}' "$lk" | tr '\n' ',' | sed 's/,$//'); lw=$(awk -F'\t' '$2=="WARN"{print $1}' "$lk" | tr '\n' ',' | sed 's/,$//')
  [ -n "$lf" ] && rec "Lock screen" FAIL "$lf" || { [ -n "$lw" ] && rec "Lock screen" WARN "$lw" || rec "Lock screen" OK "overrides, clock/date, PIN pad, keyboard, icons, notifications, auto-lock all pass"; }
  for k in "Overlay files" "top-panel.ui template ids" "Clock timezone" "OSK process" "OSK D-Bus name" "Notifications on lock screen" "idle-delay" "lock-enabled" "Idle handler"; do
    row=$(awk -F'\t' -v k="$k" '$1==k{print $2": "$3}' "$lk" | head -n1); [ -n "$row" ] && info "lock/$k -> $row"
  done
else rec "Lock screen" WARN "no result"; fi
sect "V6. hardware (informational)"
bash "$HERE/40-hw-check.sh" --quiet >/dev/null 2>&1
awk -F'\t' '{printf "  %-34s %-5s\n",$1,$2}' "$HEALTH_DIR/last-40-hw-check.tsv" | tee -a "$LOG" >/dev/null
[ "$QUIET" = 1 ] || awk -F'\t' '{printf "  %-34s %-5s\n",$1,$2}' "$HEALTH_DIR/last-40-hw-check.tsv"

sect "FINAL TABLE"
print_table "$TSV"
finish
