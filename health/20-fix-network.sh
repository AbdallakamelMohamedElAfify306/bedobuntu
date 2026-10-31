# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 20-fix-network.sh
# Phase 2a - make apt use Wi-Fi: remove the default route over usb0 WITHOUT breaking USB SSH.
# shellcheck disable=SC2015,SC2016
# Usage: bash 20-fix-network.sh [--check|--apply]
# The USB link keeps its own connected route (172.16.42.0/24 dev usb0), so the Mac can always reach the phone.
# Only the *default* route via usb0 is removed, and only when Wi-Fi really has a default route of its own.
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log

USB=usb0
FIX=/usr/local/sbin/cheetah-route-fix
SVC=/etc/systemd/system/cheetah-route-fix.service
DISP=/etc/NetworkManager/dispatcher.d/90-cheetah-route-fix

sect "N1. current state"
cap ip -br addr
cap ip route
wl=$(wifi_iface)
[ -n "$wl" ] && rec "Wi-Fi interface" OK "$wl" || { rec "Wi-Fi interface" FAIL "no wireless interface: Wi-Fi firmware/driver missing (10-check.sh section 17)"; finish; exit 1; }
ip link show "$USB" >/dev/null 2>&1 && info "$USB present: $(ip -4 -br addr show $USB | awk '{print $3}')" || info "$USB not present (cable unplugged?)"
wdef=$(ip -4 route show default dev "$wl" 2>/dev/null | head -n1)
udef=$(ip -4 route show default dev "$USB" 2>/dev/null | head -n1)
[ -n "$wdef" ] && rec "Wi-Fi default route" OK "$wdef" || rec "Wi-Fi default route" WARN "Wi-Fi has NO default route: connect first (Settings > Wi-Fi, or: nmcli device wifi connect SSID --ask)"
[ -n "$udef" ] && rec "usb0 default route" WARN "$udef (competes with Wi-Fi)" || rec "usb0 default route" OK "none"

sect "N2. who configures usb0?"
nmc=""
if have nmcli; then nmc=$(nmcli -g GENERAL.CONNECTION device show "$USB" 2>/dev/null | head -n1); fi
info "NetworkManager connection for $USB: ${nmc:-<none>}"
nwf=""
if have networkctl; then nwf=$(networkctl status "$USB" --no-pager 2>/dev/null | sed -n 's/^ *Network File: *//p' | head -n1); fi
info "systemd-networkd file for $USB: ${nwf:-<none>}"
systemctl is-active NetworkManager >/dev/null 2>&1 && info "NetworkManager active" || info "NetworkManager inactive"
systemctl is-active systemd-networkd >/dev/null 2>&1 && info "systemd-networkd active" || info "systemd-networkd inactive"

sect "N3. immediate fix (only when both defaults exist)"
if [ -n "$udef" ] && [ -n "$wdef" ]; then
  act "ip route del default dev $USB (Wi-Fi keeps the default; USB subnet route stays)" ip route del default dev "$USB"
elif [ -n "$udef" ] && [ -z "$wdef" ]; then
  warn "usb0 is the only default route and Wi-Fi is not connected: left as is. Connect Wi-Fi, then run this script again."
else ok "nothing to remove now"; fi

sect "N4. persistent fix"
if [ -n "$nmc" ] && { case "$nmc" in "--") false;; *) true;; esac; }; then
  if [ "$APPLY" = 1 ]; then
    nmcli connection modify "$nmc" ipv4.never-default yes ipv6.never-default yes >> "$LOG" 2>&1 && ok "NetworkManager '$nmc': never-default yes (takes effect at next reconnect; SSH not interrupted)" || fail "nmcli modify failed"
  else dry "nmcli connection modify '$nmc' ipv4.never-default yes ipv6.never-default yes"; fi
fi
if [ -n "$nwf" ] && { case "$nwf" in n/a) false;; *) true;; esac; } && [ -f "$nwf" ]; then
  nd="/etc/systemd/network/$(basename "$nwf").d"
  if [ "$APPLY" = 1 ]; then
    mkdir -p "$nd" && printf '[Network]\nGateway=\n\n[DHCPv4]\nUseGateway=false\n' > "$nd/10-cheetah-no-default.conf" && ok "networkd drop-in $nd/10-cheetah-no-default.conf (effective at next boot; networkd NOT reloaded now)" || fail "could not write networkd drop-in"
  else dry "write $nd/10-cheetah-no-default.conf (Gateway= reset, UseGateway=false)"; fi
fi

sect "N5. safety net: boot service + NetworkManager dispatcher (idempotent)"
FIXBODY='# run-with sh
# cheetah-route-fix: if Wi-Fi has a default route, drop the default route over usb0. Never touches the usb0 subnet route.
wl=""
for d in /sys/class/net/*; do
  if [ -d "$d/wireless" ] || [ -d "$d/phy80211" ]; then wl=$(basename "$d"); break; fi
done
[ -n "$wl" ] || exit 0
[ -n "$(ip -4 route show default dev "$wl" 2>/dev/null)" ] || exit 0
while ip -4 route show default dev usb0 2>/dev/null | grep -q default; do
  ip route del default dev usb0 2>/dev/null || break
done
exit 0'
SVCBODY='[Unit]
Description=Prefer Wi-Fi default route over usb0 (cheetah)
After=NetworkManager.service systemd-networkd.service
Wants=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c "for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do /usr/local/sbin/cheetah-route-fix; sleep 4; done"
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target'
DISPBODY='# run-with sh
# NetworkManager dispatcher: re-run the route fix whenever an interface comes up or DHCP changes.
case "$2" in up|dhcp4-change|connectivity-change) /usr/local/sbin/cheetah-route-fix ;; esac
exit 0'
inst() { # inst PATH MODE BODY
  if [ -f "$1" ] && [ "$(cat "$1")" = "$3" ]; then ok "$1 already up to date"; return 0; fi
  if [ "$APPLY" = 1 ]; then
    mkdir -p "$(dirname "$1")"; backup "$1"
    printf '%s\n' "$3" > "$1" && chmod "$2" "$1" && ok "installed $1" || fail "could not install $1"
  else dry "install $1 (mode $2)"; fi
}
inst "$FIX" 755 "$FIXBODY"
inst "$SVC" 644 "$SVCBODY"
if [ -d /etc/NetworkManager ]; then inst "$DISP" 755 "$DISPBODY"; fi
if [ "$APPLY" = 1 ]; then
  sh -n "$FIX" && ok "cheetah-route-fix syntax OK" || fail "cheetah-route-fix syntax error"
  systemctl daemon-reload >> "$LOG" 2>&1
  systemctl enable cheetah-route-fix.service >> "$LOG" 2>&1 && ok "enabled cheetah-route-fix.service (runs at boot, retries for 60 s)" || fail "enable failed"
else dry "systemctl daemon-reload; systemctl enable cheetah-route-fix.service"; fi

sect "N6. DNS"
if [ -L /etc/resolv.conf ] && [ "$(readlink /etc/resolv.conf)" = /run/systemd/resolve/stub-resolv.conf ]; then ok "/etc/resolv.conf -> systemd-resolved stub"
else
  warn "/etc/resolv.conf is not the resolved stub link"
  if [ "$APPLY" = 1 ]; then backup /etc/resolv.conf; ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf && ok "relinked resolv.conf"; else dry "ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf"; fi
fi
systemctl is-active systemd-resolved >/dev/null 2>&1 && ok "systemd-resolved active" || { warn "systemd-resolved inactive"; act "enable+start systemd-resolved" systemctl enable --now systemd-resolved; }

sect "N7. verification"
if [ "$APPLY" = 1 ]; then
  sleep 1
  cap ip route
  r=$(ip -4 route get 1.1.1.1 2>/dev/null | head -n1); info "route to 1.1.1.1: $r"
  case "$r" in *"dev $wl"*) rec "Route to internet" OK "via $wl";; *"dev $USB"*) rec "Route to internet" FAIL "still via usb0";; *) rec "Route to internet" WARN "no route (Wi-Fi not connected?)";; esac
  ip -4 route show | grep -q '172.16.42.0/24 dev usb0' && rec "USB SSH subnet route" OK "172.16.42.0/24 dev usb0 intact" || rec "USB SSH subnet route" WARN "usb0 subnet route not found (cable out?)"
  ping -c1 -W4 1.1.1.1 >/dev/null 2>&1 && rec "Ping 1.1.1.1" OK ok || rec "Ping 1.1.1.1" WARN "no reply"
  getent hosts ports.ubuntu.com >/dev/null 2>&1 && rec "DNS ports.ubuntu.com" OK ok || rec "DNS ports.ubuntu.com" WARN "no resolution"
  if have curl; then c=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' https://ports.ubuntu.com/ubuntu-ports/dists/noble/Release 2>>"$LOG"); [ "$c" = 200 ] && rec "HTTPS ports.ubuntu.com" OK "HTTP 200 (apt will work)" || rec "HTTPS ports.ubuntu.com" WARN "HTTP ${c:-none}"; fi
else info "CHECK only. Run with --apply to change routes."; fi
finish
