# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 55-rootfs-stage2.sh
# Stage 2 (run as root): configure the Ubuntu 24.04 rootfs for the Pixel 7 Pro, add the kernel modules and Omarchy Mobile's
# omamobile-device-cheetah package (installed with its own ./build and ./install, not pacman), and write the ext4 image
# (label omamobile-root: the initramfs grows it to the whole userdata partition on first boot, as for Omarchy's Arch root).
set -euo pipefail
source "$(dirname "$0")/env.sh"
R=$UWORK/rootfs
[ -f "$R/.stage1-done" ] || { echo "run stage 1 first"; exit 1; }
REL=$(cat "$WORKDIR/modstage/RELEASE")

# --- kernel modules
rm -rf "$R/usr/lib/modules"; mkdir -p "$R/usr/lib/modules"
cp -a "$WORKDIR/modstage/lib/modules/$REL" "$R/usr/lib/modules/"
depmod -b "$R" "$REL"

# --- Omarchy Mobile device package (cheetah): scripts, systemd units, udev rules, modprobe.d, reboot-to, bootctl
PK=$OMA/packages/omamobile-device-cheetah
rm -rf "$WORKDIR/devpkg-build" "$WORKDIR/devpkg-stage"
(cd "$PK" && CC=aarch64-linux-gnu-gcc ./build "$WORKDIR/devpkg-build" && ./install "$WORKDIR/devpkg-stage" "$WORKDIR/devpkg-build")
cp -a "$WORKDIR/devpkg-stage/." "$R/"
rm -rf "$R/etc/pacman.d"                                  # Arch-only
rm -f "$R/usr/lib/systemd/system/timers.target.wants/omamobile-camera.timer"   # no libcamera/Omarchy camera stack here: don't load camera drivers

# --- Ubuntu specifics: apt sources (ports.ubuntu.com), no snapd, no automatic apt activity, minimal motd noise
cat > "$R/etc/apt/sources.list" <<X
deb $MIRROR $SUITE main universe
deb $MIRROR $SUITE-updates main universe
deb $MIRROR $SUITE-security main universe
X
rm -f "$R/etc/apt/sources.list.d/"*.sources 2>/dev/null || true
mkdir -p "$R/etc/apt/preferences.d" "$R/etc/apt/apt.conf.d"
printf 'Package: snapd\nPin: release *\nPin-Priority: -10\n' > "$R/etc/apt/preferences.d/no-snapd"
printf 'APT::Install-Recommends "false";\nAPT::Periodic::Enable "0";\n' > "$R/etc/apt/apt.conf.d/99cheetah"
# Mesa is our own build (Mali-G710 support, see 57-mesa-install.sh): keep apt from replacing it with Ubuntu's
printf 'Package: libegl-mesa0 libgbm1 libgl1-mesa-dri libglx-mesa0 mesa-libgallium mesa-vulkan-drivers libglapi-mesa mesa-cheetah\nPin: release *\nPin-Priority: -10\n\nPackage: mesa-cheetah\nPin: version *\nPin-Priority: 1001\n' > "$R/etc/apt/preferences.d/mesa-cheetah"

# --- identity, locale, time
echo cheetah > "$R/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 cheetah\n::1 localhost ip6-localhost ip6-loopback\n' > "$R/etc/hosts"
sed -i 's/^# *\(en_US.UTF-8\|ar_EG.UTF-8\) /\1 /' "$R/etc/locale.gen"
chroot "$R" locale-gen >/dev/null
echo 'LANG=en_US.UTF-8' > "$R/etc/default/locale"
ln -sfn /usr/share/zoneinfo/UTC "$R/etc/localtime"; echo UTC > "$R/etc/timezone"
: > "$R/etc/machine-id"; rm -f "$R/var/lib/dbus/machine-id"

# --- user "user" / password "user"; must be changed on first login (see below). root: locked, key-only.
chroot "$R" id user >/dev/null 2>&1 || chroot "$R" useradd -m -u 1000 -s /bin/bash -G sudo,video,render,audio,input,netdev,plugdev,dialout,bluetooth user 2>/dev/null \
  || chroot "$R" useradd -m -u 1000 -s /bin/bash -G sudo,video,render,audio,input,netdev,dialout user
CHEETAH_USER_PASSWORD=${CHEETAH_USER_PASSWORD:-user}
printf 'user:%s\n' "$CHEETAH_USER_PASSWORD" | chroot "$R" chpasswd
# Default password is the placeholder 'user' (CHANGE_ME on first login). Override with CHEETAH_USER_PASSWORD at build time.
chroot "$R" passwd -l root >/dev/null
mkdir -p "$R/var/lib/cheetah"; touch "$R/var/lib/cheetah/password-change-required"
awk -F: '$1=="user"{print $2}' "$R/etc/shadow" > "$R/var/lib/cheetah/default-hash"; chmod 600 "$R/var/lib/cheetah/default-hash"
cat > "$R/usr/local/sbin/cheetah-clear-password-marker" <<'X'
# run-with sh
# Removes the "change your password" marker only if user's password hash really changed.
now=$(awk -F: '$1=="user"{print $2}' /etc/shadow); old=$(cat /var/lib/cheetah/default-hash 2>/dev/null)
[ -n "$now" ] && { case "$now" in "$old") false;; *) true;; esac; } && rm -f /var/lib/cheetah/password-change-required /var/lib/cheetah/default-hash
X
chmod 755 "$R/usr/local/sbin/cheetah-clear-password-marker"
echo 'user ALL=(root) NOPASSWD: /usr/local/sbin/cheetah-clear-password-marker' > "$R/etc/sudoers.d/10-cheetah-marker"; chmod 440 "$R/etc/sudoers.d/10-cheetah-marker"
cat > "$R/etc/profile.d/cheetah-first-login.sh" <<'X'
# Force a password change on the first interactive login (console or SSH) of "user".
if [ "$(id -un)" = user ] && [ -f /var/lib/cheetah/password-change-required ] && [ -t 0 ]; then
  echo "First login: you must change the default password (user/user) now."
  until passwd; do echo "Try again."; done
  sudo -n /usr/local/sbin/cheetah-clear-password-marker
fi
X
cat > "$R/usr/local/bin/cheetah-first-login" <<'X'
# run-with sh
# Run inside a terminal by the autostart entry on the touch screen.
[ -f /var/lib/cheetah/password-change-required ] || exit 0
echo "Welcome. You must change the default password (it is: user) before using the phone."
until passwd; do echo "Try again."; done
sudo -n /usr/local/sbin/cheetah-clear-password-marker
echo "Done. You can close this window."; sleep 3
X
chmod 755 "$R/usr/local/bin/cheetah-first-login"
mkdir -p "$R/etc/xdg/autostart"
cat > "$R/etc/xdg/autostart/cheetah-first-login.desktop" <<'X'
[Desktop Entry]
Type=Application
Name=Change default password
Exec=kgx -e /usr/local/bin/cheetah-first-login
OnlyShowIn=GNOME;Phosh;
X

# --- SSH: password login allowed, but only reachable over the USB cable (nftables), plus the debug key
mkdir -p "$R/etc/ssh/sshd_config.d"
cat > "$R/etc/ssh/sshd_config.d/10-cheetah.conf" <<'X'
PasswordAuthentication yes
PermitRootLogin prohibit-password
X
# Optional: install YOUR debug SSH public key (never commit a private key).
# Set CHEETAH_SSH_PUBKEY to a .pub file path at build time.
if [ -n "${CHEETAH_SSH_PUBKEY:-}" ] && [ -f "$CHEETAH_SSH_PUBKEY" ]; then
  for d in root home/user; do mkdir -p "$R/$d/.ssh"; cp "$CHEETAH_SSH_PUBKEY" "$R/$d/.ssh/authorized_keys"; chmod 700 "$R/$d/.ssh"; chmod 600 "$R/$d/.ssh/authorized_keys"; done
  chroot "$R" chown -R user:user /home/user/.ssh
else
  echo "NOTE: no CHEETAH_SSH_PUBKEY set; root SSH will need a password or a key you add later."
fi
rm -f "$R"/etc/ssh/ssh_host_*
cat > "$R/etc/systemd/system/cheetah-sshkeys.service" <<'X'
[Unit]
Description=Generate SSH host keys on first boot
Before=ssh.service
ConditionPathExists=/etc/ssh
# Runs every boot; ssh-keygen -A is a no-op when keys exist
[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
[Install]
WantedBy=multi-user.target
X
cat > "$R/etc/nftables.conf" <<'X'
# nftables ruleset
flush ruleset
table inet cheetah {
  chain input {
    type filter hook input priority 0; policy accept;
    # SSH only over the USB cable (usb0), never over Wi-Fi or any other interface
    tcp dport 22 iifname "usb0" accept
    tcp dport 22 iifname "lo" accept
    tcp dport 22 drop
  }
}
X

# --- services
# Phosh via Debian's phosh.service (autologin of uid 1000 "user", no display manager); greetd stays disabled.
chroot "$R" systemctl disable greetd.service >/dev/null 2>&1 || true
# Ubuntu 24.04 uses ssh.socket activation: use the plain service instead so cheetah-sshkeys can run first
chroot "$R" systemctl disable ssh.socket >/dev/null 2>&1 || true
chroot "$R" systemctl mask ssh.socket >/dev/null 2>&1 || true
sed -i 's/^Before=ssh.service$/Before=ssh.service sshd.service/' "$R/etc/systemd/system/cheetah-sshkeys.service"
for u in NetworkManager systemd-networkd systemd-resolved ssh nftables bluetooth phosh cheetah-sshkeys systemd-timesyncd; do
  chroot "$R" systemctl enable "$u.service" >/dev/null 2>&1 || echo "warn: cannot enable $u"
done
chroot "$R" systemctl set-default graphical.target >/dev/null
chroot "$R" systemctl mask systemd-networkd-wait-online.service NetworkManager-wait-online.service >/dev/null 2>&1 || true
ln -sfn /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
# Unneeded background services/timers (speed, battery, no surprise apt/snap activity)
for u in apt-daily.timer apt-daily-upgrade.timer motd-news.timer e2scrub_all.timer dpkg-db-backup.timer systemd-sysupdate.timer systemd-sysupdate-reboot.timer man-db.timer fwupd-refresh.timer; do
  chroot "$R" systemctl mask "$u" >/dev/null 2>&1 || true
done
chroot "$R" systemctl mask apt-daily.service apt-daily-upgrade.service e2scrub_reap.service >/dev/null 2>&1 || true

# --- Phosh: scale 3 like Omarchy's 480x1040 logical layout, GPU compositor. phoc reads /etc/phosh/phoc.ini first.
mkdir -p "$R/etc/phosh"
cat > "$R/etc/phosh/phoc.ini" <<X
# Pixel 7 Pro: 1440x3120 panel. Scale 3 = 480x1040 logical px (the same as Omarchy Mobile's monitor scale).
[core]
xwayland=false

[output:DSI-1]
scale = 3
[output:DSI-2]
scale = 3
X
# Performance: no Xwayland (saves memory/startup), GL renderer for GTK4 and wlroots on the Mali (panfrost) through GBM/kmsro
mkdir -p "$R/etc/systemd/system/phosh.service.d"
cat > "$R/etc/systemd/system/phosh.service.d/10-cheetah.conf" <<X
[Service]
Environment=WLR_RENDERER=gles2
Environment=GSK_RENDERER=ngl
Environment=MESA_LOADER_DRIVER_OVERRIDE=
Nice=-5
X
sed -i '/MESA_LOADER_DRIVER_OVERRIDE/d' "$R/etc/systemd/system/phosh.service.d/10-cheetah.conf"
# Panthor firmware (redistributable, from linux-firmware; Ubuntu's linux-firmware deb is 500 MB so only this file is shipped)
mkdir -p "$R/usr/lib/firmware/arm/mali/arch10.8"
install -m 644 "$(dirname "$0")/files/mali_csffw.bin" "$R/usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin"
mkdir -p "$R/usr/share/doc/cheetah"
cp "$UC/build/work/rootfs/usr/share/doc/firmware-misc-nonfree/copyright" "$R/usr/share/doc/cheetah/linux-firmware-mali-copyright" 2>/dev/null || true

# --- documentation inside the image
mkdir -p "$R/usr/share/doc/cheetah"
cat > "$R/usr/share/doc/cheetah/README.txt" <<X
Ubuntu 24.04 LTS (noble) arm64 + Phosh for the Google Pixel 7 Pro (cheetah). EXPERIMENTAL, built from Omarchy Mobile's
cheetah pipeline (kernel $REL, its initramfs, its device package). Untested on real hardware by the builder.
Login: user / user (forced change at first login). USB networking: phone 172.16.42.1, host 172.16.42.2/24.
Wi-Fi/Bluetooth/audio need Google's firmware from your own factory image (scripts/provision-firmware.sh).
GPU: Mesa 26.2.4 + Omarchy's Mali-G710 patch (panfrost on the panthor kernel driver); llvmpipe is the fallback.
Root file system: grown once at first boot to at most 50 GB (the rest of userdata stays unused).
X

# --- Mesa with Mali-G710 support (built by 61-mesa-build.sh; set NO_MESA=1 to skip and keep Ubuntu's Mesa = llvmpipe)
if { case "${NO_MESA:-0}" in 1) false;; *) true;; esac; }; then "$(dirname "$0")/57-mesa-install.sh"; else echo "NO_MESA=1: keeping Ubuntu's Mesa (software rendering only)"; fi

# --- clean
rm -rf "$R"/var/lib/apt/lists/* "$R"/var/cache/apt/*.bin "$R"/var/cache/apt/archives/*.deb "$R"/var/log/*.log "$R"/var/log/journal/* "$R"/tmp/* "$R"/var/tmp/*
rm -f "$R/var/lib/systemd/random-seed"

# --- ext4 image
USED=$(du -sx --block-size=1M "$R" | cut -f1)
SIZE=$(( (USED * 12 / 10 + 768 + 63) / 64 * 64 ))
IMG=$UWORK/rootfs.img
rm -f "$IMG"; truncate -s "${SIZE}M" "$IMG"
mkfs.ext4 -q -L omamobile-root -m 1 -d "$R" "$IMG"
e2fsck -fn "$IMG" >/dev/null && echo "fsck clean"
echo "$USED MiB of files in a $SIZE MiB ext4 image (label omamobile-root)"
img2simg "$IMG" "$OUT/userdata.simg"
ls -l "$OUT/userdata.simg"
echo "STAGE2 DONE"
