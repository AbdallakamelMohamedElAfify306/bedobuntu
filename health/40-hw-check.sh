# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 40-hw-check.sh
# Phase 4 - HARDWARE ENABLEMENT diagnosis (read-only). For every Pixel 7 Pro subsystem: kernel evidence vs userspace in THIS image.
# shellcheck disable=SC2015,SC2016,SC2012,SC2010
# Usage: bash 40-hw-check.sh [--quiet]
# Nothing is installed here. Reality (Oct 2026): the kernel (7.3.0-rc6-omamobile) carries most drivers, but this Ubuntu image
# only ships the generic userspace + omamobile-device-cheetah; the Omarchy-Mobile userspace stacks (AoC audio, sensors, GNSS,
# fingerprint, camera app, modem bridge) are Arch packages and are NOT installed here. See the guide for what is feasible.
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log

DM=$(dmesg 2>/dev/null)
LM=$(lsmod 2>/dev/null)
kev() { printf '%s\n%s\n' "$DM" "$LM" | grep -qiE "$1"; }       # kernel evidence in dmesg/lsmod
pkg() { dpkg -s "$1" >/dev/null 2>&1; }
unit() { systemctl cat "$1" >/dev/null 2>&1; }

hw() { # hw NAME KERNEL(1/0) USER(1/0) NOTE
  local n=$1 k=$2 u=$3 note=$4
  if [ "$k" = 1 ] && [ "$u" = 1 ]; then rec "$n" OK "kernel + userspace present. $note"
  elif [ "$k" = 1 ]; then rec "$n" INFO "kernel driver evidence only; userspace not in this image. $note"
  elif [ "$u" = 1 ]; then rec "$n" WARN "userspace present but no kernel evidence. $note"
  else rec "$n" INFO "no evidence in this boot. $note"; fi
}
b() { [ "$1" = 1 ] && echo 1 || echo 0; }

sect "H0. firmware that must come from YOUR Google factory image"
for pat in 'brcm/*4389*' 'brcm/*bcm4389*' 'cirrus/*' 'arm/mali/arch10.8/mali_csffw.bin' 'google/*'; do
  n=$(find /usr/lib/firmware -path "/usr/lib/firmware/${pat}" 2>/dev/null | wc -l); info "firmware /usr/lib/firmware/$pat : $n file(s)"
done
[ -f /usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin ] && rec "Mali CSF firmware" OK present || rec "Mali CSF firmware" FAIL "missing: GPU (panthor) cannot start"
fwmiss=$(printf '%s\n' "$DM" | grep -ciE 'Direct firmware load for .* failed|firmware: failed to load')
[ "$fwmiss" -eq 0 ] && rec "Firmware requests" OK "no failed loads" || { rec "Firmware requests" WARN "$fwmiss failed loads: run provision-firmware.sh from the factory zip (on the Mac/Docker), see guide"; printf '%s\n' "$DM" | grep -iE 'Direct firmware load for' | sed 's/.*Direct firmware load for //' | sort -u | head -n 15 >> "$LOG"; }

sect "H1. per-subsystem verdict"
d=$(ls /sys/class/drm/ 2>/dev/null | grep -c 'DSI'); hw "Display (DSI panel)" "$(b $((d>0)))" 1 "120 Hz KMS driver in kernel"
ls /dev/dri/renderD* >/dev/null 2>&1 && g=1 || g=0; pkg mesa-cheetah && gu=1 || gu=0; hw "GPU Mali-G710 (panthor+panfrost)" "$g" "$gu" "needs mesa-cheetah and mali_csffw.bin"
t=$(grep -ciE 'synaptics|touch' /proc/bus/input/devices 2>/dev/null); hw "Touchscreen" "$(b $((t>0)))" 1 "Synaptics S3908 TouchComm"
wlan=0; wifi_iface >/dev/null && wlan=1; hw "Wi-Fi (BCM4389)" "$wlan" 1 "needs factory firmware"
bt=0; ls /sys/class/bluetooth 2>/dev/null | grep -q hci && bt=1; hw "Bluetooth" "$bt" "$(b "$(pkg bluez && echo 1 || echo 0)")" "A2DP ok upstream; HFP calls not yet"
ba=0; ls /sys/class/power_supply/ 2>/dev/null | grep -qi -E 'max77759|battery|bms' && ba=1; hw "Battery / charging" "$ba" 1 "MAX77759 gauge"
au=0; grep -q '^ *[0-9]' /proc/asound/cards 2>/dev/null && au=1; aoc=0; kev 'aoc' && aoc=1
hw "Audio (AoC DSP + speakers/mics)" "$au" "$(b $((au)))" "ALSA card present? If 0: AoC userspace (omamobile-aoc/omamobile-audio, Arch packages) is not ported here. Speakers are quiet/thin even upstream (C9j)"
hw "AoC DSP" "$aoc" 0 "firmware boot handled by omamobile-aoc.service (not in this image)"
io=$(ls /sys/bus/iio/devices 2>/dev/null | wc -l); pkg iio-sensor-proxy && sp=1 || sp=0; hw "Sensors (accel/light/prox)" "$(b $((io>0)))" "$sp" "need AoC + USF daemon (omamobile-sensors, Arch)"
ls /dev/gnss* >/dev/null 2>&1 && gn=1 || gn=0; pkg geoclue-2.0 && gcu=1 || gcu=0; hw "GPS / GNSS" "$gn" "$gcu" "upstream: Google GNSS stack in a chroot (omamobile-gnss) behind GeoClue"
ls /sys/class/nfc >/dev/null 2>&1 && nf=1 || nf=0; command -v neard >/dev/null 2>&1 && nu=1 || nu=0; hw "NFC (tags only)" "$nf" "$nu" "ST54J via st-nci; card emulation/payments not supported"
fp=0; kev 'fingerprint|fpc|goodix|trusty' && fp=1; pkg fprintd && fu=1 || fu=0; hw "Fingerprint" "$fp" "$fu" "upstream is opt-in and needs Google's HAL in a chroot + Trusty TA + libfprint driver (omamobile-fingerprint, Arch)"
vb=0; ls /sys/class/leds 2>/dev/null | grep -qiE 'vib|haptic' && vb=1; unit feedbackd.service && fb=1 || fb=0; hw "Haptics" "$vb" "$fb" "CS40L26 via feedbackd"
tc=0; ls /sys/class/leds 2>/dev/null | grep -qiE 'torch|flash' && tc=1; hw "Torch" "$tc" 0 "LM3644, quick-settings tile is Omarchy-only"
cm=$(ls /dev/video* 2>/dev/null | wc -l); command -v cam >/dev/null 2>&1 && cu=1 || cu=0; hw "Camera (4 sensors)" "$(b $((cm>0)))" "$cu" "kernel patches exist (camera-main/front/tele/uw-lens) but this image masks the camera timer on purpose; needs libcamera 0.7-class patches + tuning + omacam (Arch). Noble's libcamera lacks gs201"
mo=0; kev 'cpif|s5300|modem_if|umts' && mo=1; systemctl is-active ModemManager >/dev/null 2>&1 && mu=1 || mu=0; hw "Modem (Exynos S5300)" "$mo" "$mu" "upstream: boots to ONLINE without a SIM; registration/SMS/data/calls NOT working yet"
rec "eSIM" INFO "not possible on Linux here: the Pixel's built-in eUICC is only reachable through Android's LPA (privileged) and needs the modem; lpac is not in Ubuntu noble. Manage the eSIM in Android"
ss=$(cat /sys/power/mem_sleep 2>/dev/null); rec "Suspend" INFO "mem_sleep=[${ss:-?}] s2idle is experimental upstream; deep sleep (SYS_SLEEP) does not exist yet -> battery drains faster than Android"
ip link show usb0 >/dev/null 2>&1 && rec "USB networking" OK "usb0 present" || rec "USB networking" WARN "no usb0"

sect "H2. packages that exist in Ubuntu noble and are SAFE to install when the matching kernel node exists"
for p in iio-sensor-proxy geoclue-2.0 fprintd modemmanager v4l-utils alsa-utils lm-sensors wireplumber feedbackd; do
  pkg "$p" && info "installed: $p" || info "not installed: $p   (apt-get install $p)"
done
info "NOT in noble: lpac, neard, libcamera-tools, systemd-zram-generator (this kit avoids them)"

sect "TABLE"
print_table "$TSV"
finish
