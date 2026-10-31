# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 50-rootfs-stage1.sh
# Stage 1 (run as root, resumable): Ubuntu 24.04 (noble) arm64 base + Phosh from universe, via mmdebstrap + qemu-user binfmt.
# Ubuntu ARM lives on ports.ubuntu.com (https: plain http is not reachable from every network). No snapd.
set -euo pipefail
source "$(dirname "$0")/env.sh"
R=$UWORK/rootfs
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || { echo "register qemu-aarch64 binfmt first"; exit 1; }
[ -f "$R/.stage1-done" ] && { echo "stage 1 already done"; exit 0; }
rm -rf "$R"
INCLUDE="ubuntu-keyring,systemd-sysv,systemd-resolved,systemd-timesyncd,udev,dbus,dbus-user-session,sudo,openssh-server,network-manager,wpasupplicant,iw,wireless-regdb,nftables,e2fsprogs,kmod,i2c-tools,usbutils,pciutils,iproute2,iputils-ping,curl,less,nano,bash-completion,locales,tzdata,ca-certificates,rfkill,zstd,xz-utils,polkitd,bluez,libgl1-mesa-dri,libegl-mesa0,libgbm1,kbd,libcap2-bin,phosh-core,gnome-console,epiphany-browser,iio-sensor-proxy,fonts-noto-core,pipewire-audio,adwaita-icon-theme"
mmdebstrap --mode=root --arch=arm64 --variant=minbase \
  --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
  --aptopt='APT::Install-Recommends "false"' \
  --include="$INCLUDE" "$SUITE" "$R" - <<SRC
deb $MIRROR $SUITE main universe
deb $MIRROR $SUITE-updates main universe
deb $MIRROR $SUITE-security main universe
SRC
touch "$R/.stage1-done"
du -sh "$R"; echo "STAGE1 DONE"
