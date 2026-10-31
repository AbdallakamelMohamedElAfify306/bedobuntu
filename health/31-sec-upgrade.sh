# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 31-sec-upgrade.sh
# Phase 3b - safe full-upgrade: hold kernel/boot/Mesa/Phosh packages, SIMULATE first, refuse if the plan touches them.
# shellcheck disable=SC2015,SC2016,SC2012
# Usage: bash 31-sec-upgrade.sh [--check|--apply] [--allow-remove] [--no-update]
# Why: this image uses a CUSTOM kernel (7.3.0-rc6-omamobile) whose modules were copied into /usr/lib/modules (no linux-image
# package), a custom Mesa (package mesa-cheetah, pinned) and a patched Phosh UI overlay. Ubuntu packages must not replace them.
# Nothing here writes to any block device or boot partition; apt only writes inside the root filesystem (/dev/sda32).
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log
trap "" HUP   # keep apt/dpkg running if the SSH link drops
ALLOW_RM=0; NOUPD=0
for a in "${REST_ARGS[@]}"; do case "$a" in --allow-remove) ALLOW_RM=1;; --no-update) NOUPD=1;; esac; done
APTO=(-o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)
HOLD_RE='^(linux-.*|initramfs-tools.*|flash-kernel|u-boot.*|grub.*|shim.*|systemd-boot.*|mesa-cheetah|libegl-mesa0|libgbm1|libgl1-mesa-dri|libglx-mesa0|mesa-libgallium|mesa-vulkan-drivers|libglapi-mesa|phosh|phosh-.*|libphosh.*|phoc|squeekboard|omamobile-.*|.*-cheetah)$'
FORBID_RE='^(linux-.*|initramfs-tools.*|flash-kernel|u-boot.*|grub.*|shim.*|systemd-boot.*|mesa-cheetah|libegl-mesa0|libgbm1|libgl1-mesa-dri|libglx-mesa0|mesa-libgallium|mesa-vulkan-drivers|libglapi-mesa|phosh|phosh-.*|libphosh.*|phoc|squeekboard|omamobile-.*|.*-cheetah|android-.*|fastboot|adb)$'

sect "U1. pre-flight"
ip route get 1.1.1.1 >/dev/null 2>&1 && ok "route to the internet exists" || { fail "no internet route: run 20-fix-network.sh --apply first"; finish; exit 1; }
[ "$(ip -4 route get 1.1.1.1 2>/dev/null | grep -c 'dev usb0')" -eq 0 ] && ok "internet goes through Wi-Fi (not usb0)" || warn "internet goes via usb0 (needs Mac Internet Sharing); prefer 20-fix-network.sh --apply"
findmnt /boot >/dev/null 2>&1 && fail "/boot is a mount ($(findmnt -no SOURCE /boot)): refusing, a package could write there" || ok "/boot is not a separate mount (nothing in apt can reach a boot partition)"
rsrc=$(findmnt -no SOURCE /); info "root device: $rsrc"
dpkg -s mesa-cheetah >/dev/null 2>&1 && ok "mesa-cheetah installed: $(dpkg-query -W -f='${Version}' mesa-cheetah)" || warn "mesa-cheetah not installed (GPU stack differs from the build)"
[ -d "/usr/lib/modules/$(uname -r)" ] && ok "kernel modules for $(uname -r) present" || fail "/usr/lib/modules/$(uname -r) missing - do not upgrade"
dpkg -s initramfs-tools >/dev/null 2>&1 && warn "initramfs-tools is installed: it would write /boot/initrd.img-* INSIDE the root filesystem only (not to vendor_kernel_boot_b); the phone boots its own initramfs from the boot partition and ignores it" || ok "initramfs-tools not installed (no initramfs hooks can run)"
dpkg -l 2>/dev/null | awk '/^ii/{print $2}' | grep -E '^linux-(image|modules|generic)' | sed 's/^/  kernel pkg: /' >> "$LOG"

[ "$N_FAIL" -gt 0 ] && { fail "pre-flight failed: not continuing (nothing changed)"; finish; exit 1; }

sect "U2. holds"
mapfile -t TOHOLD < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1=="ii"{print $2}' | grep -E "$HOLD_RE")
info "installed packages matching the hold list: ${TOHOLD[*]:-none}"
for p in "${TOHOLD[@]}"; do
  if apt-mark showhold 2>/dev/null | grep -qx "$p"; then ok "$p already held"; else act "apt-mark hold $p" apt-mark hold "$p"; fi
done
cap apt-mark showhold
[ -f /etc/apt/preferences.d/mesa-cheetah ] && ok "Mesa pin file present (/etc/apt/preferences.d/mesa-cheetah)" || warn "Mesa pin file missing: apt could install Ubuntu Mesa over mesa-cheetah"

sect "U3. refresh package lists"
if [ "$NOUPD" = 1 ]; then info "--no-update: using cached lists"
else apt-get "${APTO[@]}" update >> "$LOG" 2>&1 && ok "apt-get update" || { fail "apt-get update failed (network/clock? run 20-fix-network.sh and 21-repair-system.sh time)"; finish; exit 1; }; fi

sect "U4. simulation of full-upgrade"
SIM=$(apt-get "${APTO[@]}" -s full-upgrade 2>&1)
printf '%s\n' "$SIM" >> "$LOG"
ninst=$(printf '%s\n' "$SIM" | grep -c '^Inst'); nrem=$(printf '%s\n' "$SIM" | grep -c '^Remv')
info "plan: $ninst upgrades/installs, $nrem removals"
printf '%s\n' "$SIM" | grep -E '^(Inst|Remv)' | awk '{print $1, $2, $3}' | head -n 60 | sed 's/^/  /' | tee -a "$LOG" > /dev/null
[ "$QUIET" = 1 ] || printf '%s\n' "$SIM" | grep -E '^(Inst|Remv)' | awk '{print "  " $1, $2, $3}' | head -n 40
bad=$(printf '%s\n' "$SIM" | awk '$1=="Inst"||$1=="Remv"{print $2}' | grep -E "$FORBID_RE")
if [ -n "$bad" ]; then fail "the plan touches protected packages: $(printf '%s' "$bad" | tr '\n' ' ') - REFUSING. Nothing was changed."; finish; exit 1; fi
ok "plan does not touch kernel / boot / Mesa / Phosh / omamobile packages"
if [ "$nrem" -gt 0 ] && { case "$ALLOW_RM" in 1) false;; *) true;; esac; }; then fail "plan REMOVES $nrem packages: $(printf '%s\n' "$SIM" | awk '$1=="Remv"{print $2}' | tr '\n' ' ') - refusing (re-run with --allow-remove after reading them)"; finish; exit 1; fi
printf '%s\n' "$SIM" | grep -q '^E:' && { fail "apt reported errors in the simulation (see log)"; finish; exit 1; }
sec=$(printf '%s\n' "$SIM" | grep '^Inst' | grep -c -- '-security'); info "of which security pocket: $sec"

sect "U5. apply"
if [ "$APPLY" = 1 ]; then
  dpkg-query -W > "$HEALTH_DIR/backup/pkgs-before-$TS.txt" && ok "package versions saved: $HEALTH_DIR/backup/pkgs-before-$TS.txt (downgrade reference)"
  dpkg --get-selections > "$HEALTH_DIR/backup/selections-before-$TS.txt"
  ls -la --time-style=full-iso /boot > "$HEALTH_DIR/backup/boot-ls-before-$TS.txt" 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get "${APTO[@]}" -y full-upgrade >> "$LOG" 2>&1 && ok "apt-get full-upgrade finished" || fail "apt-get full-upgrade failed: see $LOG ; then 21-repair-system.sh dpkg --apply"
  sect "U6. post-checks"
  dpkg --audit | grep -q . && fail "dpkg --audit reports problems" || ok "dpkg --audit clean"
  dpkg -s mesa-cheetah >/dev/null 2>&1 && ok "mesa-cheetah still installed" || fail "mesa-cheetah is GONE: reinstall mesa-cheetah_26.2.4_arm64.deb with: dpkg -i FILE (the file is in the build output - ask for it); GPU falls back to software until then"
  [ -d "/usr/lib/modules/$(uname -r)" ] && ok "kernel modules intact" || fail "kernel modules directory vanished"
  [ -x /usr/local/bin/phosh-osk-stub ] && ok "patched phosh-osk-stub intact" || fail "patched OSK missing"
  [ -f /opt/phosh-overlay/sm/puri/phosh/ui/top-panel.ui ] && ok "top-panel.ui overlay intact" || warn "top-panel.ui overlay missing"
  ls -la --time-style=full-iso /boot 2>&1 | diff -q - "$HEALTH_DIR/backup/boot-ls-before-$TS.txt" >/dev/null && ok "/boot unchanged" || warn "/boot listing changed (it is inside the rootfs; still harmless to the boot partitions): compare $HEALTH_DIR/backup/boot-ls-before-$TS.txt"
  u=$(phosh_unit); [ -n "$u" ] && systemctl is-active "$u" >/dev/null 2>&1 && ok "$u active" || warn "phosh is not active"
  systemctl is-active ssh >/dev/null 2>&1 && ok "ssh active" || warn "ssh not active"
  [ -f /var/run/reboot-required ] && warn "reboot-required is set (libc/systemd updated): reboot the phone when convenient, using the normal Ubuntu reboot" || ok "no reboot required"
else
  dry "apt-get full-upgrade (plan above). Run with --apply to execute."
fi
finish
