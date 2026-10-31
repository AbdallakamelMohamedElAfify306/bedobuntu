# SPDX-License-Identifier: GPL-3.0-or-later
# run-with bash
# Phase 1 - FULL READ-ONLY health check. Changes nothing (only writes its own log under /root/health).
# shellcheck disable=SC2015,SC2012,SC2010,SC2016
# Usage: bash 10-check.sh [--quiet] [--no-lockscreen]
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log
DO_LOCK=1
for a in "${REST_ARGS[@]}"; do [ "$a" = "--no-lockscreen" ] && DO_LOCK=0; done
HERE=$(cd "$(dirname "$0")" && pwd)

sect "1. identity / kernel"
cap uname -a
. /etc/os-release 2>/dev/null; info "OS: ${PRETTY_NAME:-unknown}"
case "${VERSION_CODENAME:-}" in noble) rec "OS release" OK "Ubuntu noble ${VERSION_ID:-}";; *) rec "OS release" WARN "expected Ubuntu noble, got ${PRETTY_NAME:-unknown} - package names in this kit may differ";; esac
[ "$(uname -m)" = aarch64 ] && rec "Architecture" OK aarch64 || rec "Architecture" WARN "$(uname -m) (expected aarch64)"
kr=$(uname -r)
case "$kr" in *omamobile*) rec "Kernel" OK "$kr (custom Omarchy-Mobile kernel)";; *) rec "Kernel" WARN "$kr (not the omamobile kernel?)";; esac
[ -d "/usr/lib/modules/$kr" ] && rec "Kernel modules dir" OK "/usr/lib/modules/$kr" || rec "Kernel modules dir" FAIL "/usr/lib/modules/$kr missing: modprobe cannot load anything"
tn=$(cat /proc/sys/kernel/tainted 2>/dev/null); info "kernel taint=$tn (non-zero is normal for out-of-tree/rc kernels)"
cap uptime
capsh 'cat /proc/cmdline'
capsh 'findmnt -no SOURCE,FSTYPE,OPTIONS /'

sect "2. systemd failed units"
nf=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)
cap systemctl --failed --no-pager --plain
[ "$nf" -eq 0 ] && rec "Failed units" OK none || rec "Failed units" WARN "$nf failed (run 21-repair-system.sh units)"
st=$(systemctl is-system-running 2>/dev/null); info "is-system-running=$st"

sect "3. journal errors (this boot)"
ne=$(journalctl -b -p err --no-pager -q 2>/dev/null | wc -l)
MAXL=60 capsh 'journalctl -b -p err --no-pager -q | cut -c1-200 | tail -n 60'
[ "$ne" -eq 0 ] && rec "Journal errors" OK none || rec "Journal errors" WARN "$ne error lines this boot (see log)"
MAXL=25 capsh 'journalctl -b -p err --no-pager -q -o cat | sed -E "s/[0-9]+/N/g" | cut -c1-110 | sort | uniq -c | sort -rn | head -n 15'

sect "4. phosh / coredumps / crashes"
U=$(phosh_unit); P=$(phosh_pid)
if [ -n "$P" ]; then rec "Phosh process" OK "pid $P unit ${U:-?}"; else rec "Phosh process" FAIL "phosh not running (journalctl -u ${U:-pixel-phosh} -n 40)"; fi
if [ -n "$U" ]; then
  capsh "systemctl show -p ActiveState,SubState,NRestarts,ExecMainStartTimestamp '$U'"
  nr=$(systemctl show -p NRestarts --value "$U" 2>/dev/null); [ "${nr:-0}" -le 1 ] && rec "Phosh restarts" OK "NRestarts=${nr:-0}" || rec "Phosh restarts" WARN "NRestarts=$nr (crash loop?)"
fi
pgrep -x phoc >/dev/null && rec "phoc compositor" OK "running" || rec "phoc compositor" WARN "phoc process not found (compositor may be embedded or down)"
ov=$(phosh_env G_RESOURCE_OVERLAYS); info "G_RESOURCE_OVERLAYS=${ov:-<none>}"
case "$ov" in *stylesheet=*) rec "Stylesheet override" FAIL "still active - run 00-step0-undo-wallpaper.sh --apply";; *) rec "Stylesheet override" OK "not active";; esac
if have coredumpctl; then capsh 'coredumpctl list --no-pager 2>&1 | tail -n 10'; else info "coredumpctl not installed (systemd-coredump absent): no dumps are kept"; fi
ls /var/crash 2>/dev/null | head >> "$LOG"
nseg=$(journalctl -b --no-pager -q 2>/dev/null | grep -ciE 'segfault|core dumped|SIGSEGV|SIGABRT|Gdk-ERROR|Gtk-ERROR') 
[ "$nseg" -eq 0 ] && rec "Crash signatures" OK "none in journal" || { rec "Crash signatures" WARN "$nseg lines (segfault/abort)"; MAXL=15 capsh "journalctl -b --no-pager -q | grep -iE 'segfault|core dumped|SIGSEGV|SIGABRT|Gdk-ERROR|Gtk-ERROR' | cut -c1-200 | tail -n 15"; }
no=$(journalctl -b --no-pager -q 2>/dev/null | grep -ciE 'out of memory|oom-kill|killed process')
[ "$no" -eq 0 ] && rec "OOM kills" OK none || rec "OOM kills" WARN "$no OOM lines (memory pressure, see zram)"

sect "5. disk / inodes / mounts"
cap df -hT / /mnt/shared /tmp /run
cap df -i /
use=$(df --output=pcent / | tail -n1 | tr -dc '0-9'); [ "${use:-0}" -lt 85 ] && rec "Root usage" OK "${use}%" || rec "Root usage" WARN "${use}% full"
iuse=$(df --output=ipcent / | tail -n1 | tr -dc '0-9'); [ "${iuse:-0}" -lt 85 ] && rec "Root inodes" OK "${iuse}%" || rec "Root inodes" WARN "${iuse}% used"
ro=$(findmnt -no OPTIONS / | tr ',' '\n' | grep -cx ro); [ "$ro" -eq 0 ] && rec "Root mounted rw" OK rw || rec "Root mounted rw" FAIL "root is READ-ONLY (fs error? dmesg | grep -i ext4)"
if findmnt /mnt/shared >/dev/null 2>&1; then
  rec "/mnt/shared" OK "$(findmnt -no SOURCE,FSTYPE,OPTIONS /mnt/shared | cut -c1-90)"
else rec "/mnt/shared" WARN "not mounted"; fi
findmnt /boot >/dev/null 2>&1 && rec "/boot mount" WARN "/boot is a separate mount: $(findmnt -no SOURCE /boot)" || rec "/boot mount" OK "no separate /boot (apt cannot write boot partitions)"
ne4=$(dmesg 2>/dev/null | grep -ciE 'EXT4-fs error|I/O error|blk_update_request|Buffer I/O') ; [ "$ne4" -eq 0 ] && rec "Filesystem/IO errors" OK "none in dmesg" || rec "Filesystem/IO errors" WARN "$ne4 dmesg lines"
capsh 'lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,RO 2>/dev/null | grep -E "sda3[0-9]|NAME"'
capsh 'ls /sys/class/ufs* /sys/bus/platform/drivers/ufshcd* 2>/dev/null | head -n 5'

sect "6. memory / swap / zram"
cap free -m
capsh 'cat /proc/swaps'
if have zramctl; then capsh 'zramctl 2>&1'; fi
capsh 'sysctl vm.swappiness vm.page-cluster 2>&1'
[ -r /proc/pressure/memory ] && capsh 'cat /proc/pressure/memory'
if grep -q zram /proc/swaps 2>/dev/null; then rec "zram swap" OK "active"; elif [ -e /sys/block/zram0 ] || grep -q zram /proc/devices 2>/dev/null || find "/usr/lib/modules/$kr" -name 'zram.ko*' 2>/dev/null | grep -q .; then rec "zram swap" WARN "kernel supports zram but it is not active (21-repair-system.sh zram)"; else rec "zram swap" WARN "kernel has no zram module at all (needs kernel rebuild, see guide)"; fi
mt=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo); ma=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
[ "${ma:-0}" -gt 800 ] && rec "Memory available" OK "${ma} MB of ${mt} MB" || rec "Memory available" WARN "${ma} MB of ${mt} MB"

sect "7. thermal"
hot=0
for z in /sys/class/thermal/thermal_zone*; do
  [ -r "$z/temp" ] || continue
  t=$(cat "$z/temp" 2>/dev/null); ty=$(cat "$z/type" 2>/dev/null); say "  $ty: $((t/1000)) C"
  [ "${t:-0}" -gt 85000 ] && hot=1
done
ls /sys/class/thermal/thermal_zone* >/dev/null 2>&1 || rec "Thermal zones" WARN "no thermal zones exposed by the kernel"
[ "$hot" = 0 ] && rec "Temperature" OK "no zone above 85 C" || rec "Temperature" WARN "a zone is above 85 C"
have sensors && capsh 'sensors 2>&1 | head -n 30'

sect "8. battery / power"
bat_found=0
for b in /sys/class/power_supply/*; do
  [ -d "$b" ] || continue
  ty=$(cat "$b/type" 2>/dev/null); say "  $(basename "$b"): type=$ty status=$(cat "$b/status" 2>/dev/null) capacity=$(cat "$b/capacity" 2>/dev/null) health=$(cat "$b/health" 2>/dev/null) temp=$(cat "$b/temp" 2>/dev/null) voltage_uv=$(cat "$b/voltage_now" 2>/dev/null) current_ua=$(cat "$b/current_now" 2>/dev/null)"
  [ "$ty" = Battery ] && bat_found=1 && bcap=$(cat "$b/capacity" 2>/dev/null) && bst=$(cat "$b/status" 2>/dev/null)
done
[ "$bat_found" = 1 ] && rec "Battery" OK "${bcap:-?}% ${bst:-?}" || rec "Battery" WARN "no Battery power_supply found"
have upower && capsh 'upower -e 2>&1 | head'
systemctl is-active upower >/dev/null 2>&1 && rec "upower service" OK active || rec "upower service" WARN "inactive (battery icon in top bar may be missing)"
capsh 'cat /sys/power/mem_sleep 2>&1'

sect "9. network / routes / DNS"
cap ip -br addr
cap ip route
cap ip -6 route
dflt=$(ip -4 route show default 2>/dev/null)
wl=$(wifi_iface); info "wifi iface: ${wl:-none}"
if [ -z "$dflt" ]; then rec "IPv4 default route" WARN "no default route (no internet)"
elif printf '%s' "$dflt" | grep -q 'dev usb0' && [ -n "$wl" ]; then rec "IPv4 default route" FAIL "default goes via usb0 (apt will fail): run 20-fix-network.sh --apply"
else rec "IPv4 default route" OK "$(printf '%s' "$dflt" | head -n1)"; fi
[ -n "$wl" ] && { ip -4 addr show "$wl" 2>/dev/null | grep -q inet && rec "Wi-Fi IPv4" OK "$(ip -4 -br addr show "$wl" | awk '{print $3}')" || rec "Wi-Fi IPv4" WARN "$wl has no IPv4 (not connected)"; }
have nmcli && { cap nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device; }
have resolvectl && capsh 'resolvectl status 2>&1 | head -n 25'
[ -L /etc/resolv.conf ] && info "/etc/resolv.conf -> $(readlink /etc/resolv.conf)" || warn "/etc/resolv.conf is not a symlink to the resolved stub"
ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 && rec "Internet (IP)" OK "ping 1.1.1.1" || rec "Internet (IP)" WARN "no reply from 1.1.1.1"
getent hosts ports.ubuntu.com >/dev/null 2>&1 && rec "DNS" OK "ports.ubuntu.com resolves" || rec "DNS" WARN "cannot resolve ports.ubuntu.com"
have rfkill && cap rfkill list
have iw && capsh 'iw dev 2>&1 | head -n 20'
capsh 'ip -4 route get 1.1.1.1 2>&1'

sect "10. apt / dpkg"
aud=$(dpkg --audit 2>&1); [ -z "$aud" ] && rec "dpkg --audit" OK clean || { rec "dpkg --audit" FAIL "problems found"; say "$aud"; }
cap apt-mark showhold
bad=$(dpkg -l 2>/dev/null | awk 'NR>5 {ok=0; if($1=="ii") ok=1; if($1=="rc") ok=1; if(ok==0) print $1, $2}'); [ -z "$bad" ] && rec "Package states" OK "all installed packages are ii" || { rec "Package states" WARN "non-ii packages: $(printf '%s' "$bad" | tr '\n' ';' | cut -c1-150)"; }
apt-get check >> "$LOG" 2>&1 && rec "apt-get check" OK "no broken dependencies" || rec "apt-get check" FAIL "broken dependencies (apt-get -f install)"
dpkg -s mesa-cheetah >/dev/null 2>&1 && rec "mesa-cheetah" OK "$(dpkg-query -W -f='${Version}' mesa-cheetah)" || rec "mesa-cheetah" WARN "custom Mesa package missing: GPU falls back to Ubuntu Mesa/llvmpipe"
dpkg -s snapd >/dev/null 2>&1 && rec "snapd" WARN "snapd installed (build pinned it out)" || rec "snapd" OK "absent"
age=$(find /var/lib/apt/lists -maxdepth 1 -type f -name '*Packages*' -mtime -7 2>/dev/null | wc -l); [ "$age" -gt 0 ] && info "apt lists refreshed in the last 7 days" || info "apt lists older than 7 days or empty (31-sec-upgrade.sh runs apt update)"
capsh 'apt-get -s upgrade 2>/dev/null | grep -c "^Inst" | sed "s/^/pending upgrades (from cached lists): /"'
cap systemctl is-enabled apt-daily.timer apt-daily-upgrade.timer
capsh 'cat /etc/apt/preferences.d/* 2>/dev/null | head -n 20'

sect "11. kernel modules / firmware"
capsh 'lsmod | wc -l | sed "s/^/loaded modules: /"'
MAXL=60 capsh 'lsmod | awk "NR>1{print \$1}" | tr "\n" " " | fold -w 110'
fwf=$(dmesg 2>/dev/null | grep -iE 'firmware.*(fail|error|not found|-2\b)|direct firmware load|failed to load firmware|Falling back to sysfs fallback' | head -n 30)
if [ -z "$fwf" ]; then rec "Firmware load failures" OK "none in dmesg"; else rec "Firmware load failures" WARN "$(printf '%s\n' "$fwf" | wc -l) lines (see log; needs firmware from your factory image)"; printf '%s\n' "$fwf" | cut -c1-180 >> "$LOG"; printf '%s\n' "$fwf" | head -n 10 | cut -c1-160; fi
capsh 'ls /usr/lib/firmware 2>/dev/null | head -n 40 | tr "\n" " "'
dmesg 2>/dev/null | grep -iE 'panic|BUG:|Oops|WARNING:' | head -n 8 | cut -c1-160 >> "$LOG"

sect "12. sensors / IIO"
ls /sys/bus/iio/devices/ >> "$LOG" 2>&1
n=0; for d in /sys/bus/iio/devices/iio:device*; do [ -r "$d/name" ] && { say "  iio: $(cat "$d/name")"; n=$((n+1)); }; done
[ "$n" -gt 0 ] && rec "IIO sensors" OK "$n iio devices" || rec "IIO sensors" INFO "none: accelerometer/light/proximity need AoC userspace (guide phase 4)"
systemctl is-active iio-sensor-proxy >/dev/null 2>&1 && info "iio-sensor-proxy active" || info "iio-sensor-proxy not active"

sect "13. audio"
capsh 'cat /proc/asound/cards 2>&1'
have aplay && capsh 'aplay -l 2>&1 | head -n 12'
if [ -n "$P" ]; then
  xr=$(phosh_env XDG_RUNTIME_DIR); have wpctl && MAXL=25 capsh "runuser -u user -- env XDG_RUNTIME_DIR='${xr:-/run/user/1000}' wpctl status 2>&1 | head -n 25"
fi
grep -q '^ *[0-9]' /proc/asound/cards 2>/dev/null && rec "Sound card" OK "$(head -n1 /proc/asound/cards | cut -c1-70)" || rec "Sound card" INFO "no ALSA card (speakers/mics need AoC audio stack: not in this image)"

sect "14. modem / ModemManager / eSIM"
systemctl is-active ModemManager >/dev/null 2>&1 && info "ModemManager active" || info "ModemManager not active"
have mmcli && capsh 'mmcli -L 2>&1 | head'
ls /dev/wwan* /dev/cdc-wdm* /dev/ttyACM* 2>/dev/null >> "$LOG"
ls -d /sys/class/net/rmnet* /sys/class/net/wwan* 2>/dev/null >> "$LOG"
capsh 'dmesg | grep -iE "cpif|modem|s5300|exynos.*modem|mhi" | head -n 8 | cut -c1-160'
if have mmcli && mmcli -L 2>/dev/null | grep -q '/Modem/'; then rec "Modem" OK "visible to ModemManager"; else rec "Modem" INFO "no modem exposed: cellular/eSIM not available in this image (see guide phase 4)"; fi

sect "15. camera"
ls /dev/video* /dev/media* /dev/v4l-subdev* 2>/dev/null >> "$LOG"
nv=$(ls /dev/video* 2>/dev/null | wc -l)
have v4l2-ctl && capsh 'v4l2-ctl --list-devices 2>&1 | head -n 20'
have cam && capsh 'cam -l 2>&1 | head'
capsh 'lsmod | grep -iE "imx|s5k|csis|camera|v4l2|videobuf|exynos.*(is|cam)" | head -n 10'
capsh 'systemctl is-enabled omamobile-camera.timer 2>&1; ls /usr/lib/systemd/system/ | grep -i camera'
[ "$nv" -gt 0 ] && rec "Camera nodes" INFO "$nv /dev/video* nodes (needs libcamera tuning/app to be usable)" || rec "Camera nodes" INFO "no /dev/video*: camera drivers are intentionally not loaded in this image"

sect "16. bluetooth"
systemctl is-active bluetooth >/dev/null 2>&1 && info "bluetooth.service active" || info "bluetooth.service inactive"
have hciconfig && capsh 'hciconfig -a 2>&1 | head -n 12'
have bluetoothctl && capsh 'timeout 5 bluetoothctl list 2>&1'
ls /sys/class/bluetooth 2>/dev/null | grep -q hci && rec "Bluetooth" OK "hci device present" || rec "Bluetooth" WARN "no hci device (firmware from factory image missing?)"

sect "17. Wi-Fi"
if [ -n "$wl" ]; then rec "Wi-Fi device" OK "$wl"; capsh "iw dev $wl link 2>&1 | head -n 8"; else rec "Wi-Fi device" WARN "no wireless interface (brcmfmac firmware missing?)"; fi
capsh 'dmesg | grep -iE "brcmfmac|bcm4389|wlan" | head -n 8 | cut -c1-160'

sect "18. GPU / graphics driver actually in use"
ls -la /dev/dri >> "$LOG" 2>&1
for c in /sys/class/drm/card*/device/driver; do [ -e "$c" ] && say "  $(basename "$(dirname "$(dirname "$c")")"): driver=$(basename "$(readlink -f "$c")")"; done
gpu_mod=$(lsmod | awk '$1 ~ /^(panthor|panfrost|mali|msm|lima)/ {print $1}' | tr '\n' ' ')
info "GPU kernel modules loaded: ${gpu_mod:-none (may be built-in)}"
if ls /dev/dri/renderD* >/dev/null 2>&1; then rec "DRM render node" OK "$(ls /dev/dri/renderD* | tr '\n' ' ')"; else rec "DRM render node" WARN "no /dev/dri/renderD*: no GPU acceleration"; fi
pc=$(pgrep -o -x phoc || phosh_pid)
if [ -n "$pc" ] && [ -r "/proc/$pc/maps" ]; then
  libs=$(grep -oE '[a-z_]*(panfrost|swrast|kms_swrast|libgallium|libvulkan_[a-z]+)[a-zA-Z0-9_.-]*\.so' "/proc/$pc/maps" | sort -u | tr '\n' ' ')
  info "graphics libs mapped by pid $pc: ${libs:-none found}"
  case "$libs" in *panfrost*|*gallium*) rec "GPU userspace" OK "mesa gallium mapped: $libs (panfrost on panthor if renderD exists)";; *swrast*) rec "GPU userspace" WARN "software rendering (llvmpipe) is in use";; *) rec "GPU userspace" INFO "could not tell from maps";; esac
fi
capsh 'journalctl -b --no-pager -q | grep -iE "llvmpipe|panfrost|panthor|renderer" | head -n 6 | cut -c1-180'
dpkg -s mesa-cheetah >/dev/null 2>&1 && info "mesa-cheetah installed (Mesa with Mali-G710 patch)"

sect "19. display scale"
capsh 'cat /etc/phosh/phoc.ini 2>&1'
for m in /sys/class/drm/card*-DSI*/modes; do [ -r "$m" ] && say "  $(basename "$(dirname "$m")"): $(head -n1 "$m") status=$(cat "$(dirname "$m")/status" 2>/dev/null)"; done
grep -q 'scale *= *3' /etc/phosh/phoc.ini 2>/dev/null && rec "Display scale" OK "scale=3 in phoc.ini" || rec "Display scale" WARN "scale=3 not set in /etc/phosh/phoc.ini"

sect "20. custom tweaks that must survive"
[ -x /usr/local/bin/phosh-osk-stub ] && rec "phosh-osk-stub (patched)" OK "present" || rec "phosh-osk-stub (patched)" WARN "/usr/local/bin/phosh-osk-stub missing or not executable"
[ -f /opt/phosh-overlay/sm/puri/phosh/ui/top-panel.ui ] && rec "top-panel.ui overlay" OK present || rec "top-panel.ui overlay" WARN missing
[ -f /root/osk-tweaks.sh ] && rec "/root/osk-tweaks.sh" OK present || rec "/root/osk-tweaks.sh" WARN missing
ls /etc/systemd/system/pixel-phosh.service.d/ >> "$LOG" 2>&1
[ -f /etc/systemd/system/pixel-phosh.service.d/20-clock-right.conf ] && rec "20-clock-right.conf" OK present || rec "20-clock-right.conf" WARN missing
sw=$(find /usr/share/applications /usr/local/share/applications /home/user/.local/share/applications -maxdepth 1 \( -iname '*android*' -o -iname '*reboot*' -o -iname '*switch*' \) 2>/dev/null | head -n 3 | tr '\n' ' ')
[ -n "$sw" ] && rec "Reboot-to-Android icon" OK "$sw" || rec "Reboot-to-Android icon" WARN "no android/reboot/switch .desktop file found"

sect "21. user accounts"
passwd -S user root 2>&1 | tee -a "$LOG" >/dev/null
[ -f /var/lib/cheetah/password-change-required ] && rec "Default password marker" WARN "first-login password change still pending (change with passwd, see 32-sec-harden.sh passwords)" || rec "Default password marker" OK "cleared"

if [ "$DO_LOCK" = 1 ]; then
  sect "22. lock screen inspection (11-lockscreen-check.sh)"
  if [ -f "$HERE/11-lockscreen-check.sh" ]; then
    bash "$HERE/11-lockscreen-check.sh" --quiet >> "$LOG" 2>&1
    lk="$HEALTH_DIR/last-11-lockscreen-check.tsv"
    if [ -s "$lk" ]; then
      lw=$(awk -F'\t' '$2=="WARN"' "$lk" | wc -l); lf=$(awk -F'\t' '$2=="FAIL"' "$lk" | wc -l)
      if [ "$lf" -gt 0 ]; then rec "Lock screen" FAIL "$lf fail / $lw warn: run 11-lockscreen-check.sh"
      elif [ "$lw" -gt 0 ]; then rec "Lock screen" WARN "$lw warnings: run 11-lockscreen-check.sh and 12-lockscreen-fix.sh"
      else rec "Lock screen" OK "all lock screen checks passed"; fi
    else rec "Lock screen" WARN "lockscreen script produced no result"; fi
  else rec "Lock screen" WARN "11-lockscreen-check.sh not found next to this script"; fi
fi

sect "TABLE"
print_table "$TSV"
finish
