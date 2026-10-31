# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 30-initramfs.sh
# Build Omarchy Mobile's cheetah initramfs (Alpine minirootfs + dropbear + e2fsprogs + kexec + our init),
# mirroring `bin/omamobile initramfs`, but with a GNU cross compiler instead of the Android clang/musl sysroot.
# The init script is Omarchy's own, with one change for this build (grow_root capped at 50 GB): initramfs/init (storage guard, USB gadget NCM+ACM,
# grow root to userdata, switch_root to /usr/lib/systemd/systemd on the userdata partition).
set -euo pipefail
source "$(dirname "$0")/env.sh"
DL=$WORKDIR/alpine; ST=$UWORK/initramfs; VER=3.24.2
TARBALL=alpine-minirootfs-$VER-aarch64.tar.gz
SUM=9bf70a7f18ea44094cbb5f70c58f9af129c8214745743db0e68e5502cc2ce773
mkdir -p "$DL"
[ -f "$DL/$TARBALL" ] || curl -fsSL -o "$DL/$TARBALL" "https://dl-cdn.alpinelinux.org/alpine/v${VER%.*}/releases/aarch64/$TARBALL"
echo "$SUM  $DL/$TARBALL" | sha256sum -c --quiet
rm -rf "$ST"; mkdir -p "$ST"; tar -xzf "$DL/$TARBALL" -C "$ST"
for apk in $(python3 -I "$(dirname "$0")/alpine-fetch.py" "$VER" "$DL/apks" dropbear kexec-tools e2fsprogs e2fsprogs-extra); do
  tar -xzf "$apk" -C "$ST" --exclude='.PKGINFO' --exclude='.SIGN.*' --exclude='.*.sh' 2>/dev/null || true
done
for f in sbin/e2fsck usr/sbin/resize2fs usr/sbin/dumpe2fs; do [ -x "$ST/$f" ] || { echo "missing /$f"; exit 1; }; done
install -m 755 "$OMA/initramfs/init" "$ST/init"
# Ubuntu build: cap the first-boot root growth. Omarchy's grow_root resizes the ext4 root to fill ALL of userdata; here it
# stops at 50 GB (50,000,000,000 bytes = 47683 MiB, so never more than 50 GB in either GB or GiB); the rest of userdata
# stays unallocated. omamobile.noresize on the command line still skips growing entirely.
echo 47683 > "$ST/etc/omamobile-root-cap"
python3 "$(dirname "$0")/patch-init-cap.py" "$ST/init"
# Disable the USB dead-man crash (it panicked the phone 65 s after boot whenever no USB host configured the gadget)
python3 "$(dirname "$0")/patch-init-nopanic.py" "$ST/init"
# Split layout: root found by label omamobile-root on a partition named `ubuntu` or `userdata`; `ubuntu` allowlisted
python3 "$(dirname "$0")/patch-init-split.py" "$ST/init"
sh -n "$ST/init"

# Per-device files for the shared init, as initramfs_config does for cheetah's device.conf
# (packed: omamobile-compatible, omamobile-simplefb-trig, omamobile-bringup-probe, omamobile-ufs-rw, omamobile-usb-product)
E=$ST/etc
# shellcheck disable=SC1090
source <(grep -E '^(COMPATIBLE|SIMPLEFB_TRIG_CON|UFS_RW|USB_PRODUCT)=' "$OMA/device/cheetah/device.conf" | sed 's/^/DEV_/')
echo "$DEV_COMPATIBLE" > "$E/omamobile-compatible"
echo "$DEV_SIMPLEFB_TRIG_CON" > "$E/omamobile-simplefb-trig"
: > "$E/omamobile-bringup-probe"
echo "$DEV_UFS_RW ubuntu" > "$E/omamobile-ufs-rw"
echo "$DEV_USB_PRODUCT" > "$E/omamobile-usb-product"
# Safety: only slot B's boot images and userdata may be writable
for p in $DEV_UFS_RW; do case $p in boot_b|init_boot_b|vendor_boot_b|vendor_kernel_boot_b|dtbo_b|userdata|ubuntu) ;; *) echo "bad UFS_RW $p"; exit 1;; esac; done

CC=aarch64-linux-gnu-gcc
mkdir -p "$ST/usr/local/bin"
# devmem is freestanding with a naked _start: needs clang (GCC 14 ignores `naked` on aarch64), as in omamobile's fallback branch
clang --target=aarch64-linux-gnu -nostdlib -static -ffreestanding -fno-builtin \
  -fno-stack-protector -fno-pie -fuse-ld=lld -O2 \
  -o "$ST/usr/local/bin/devmem" "$OMA/tools/devmem-freestanding.c"
$CC -static -O2 -o "$ST/usr/local/bin/reboot-to" "$OMA/packages/omamobile-device-cheetah/src/reboot-to.c"
$CC -static -O2 -o "$ST/usr/local/bin/omamobile-bootctl" "$OMA/packages/omamobile-device-cheetah/src/omamobile-bootctl.c"
aarch64-linux-gnu-strip "$ST/usr/local/bin/"* || true

# Debug SSH key for the initramfs' dropbear (root@172.16.42.1 over USB networking only)
KEYDIR=$OUT/debug_ssh; mkdir -p "$KEYDIR"
if [ -n "${CHEETAH_SSH_PUBKEY:-}" ] && [ -f "$CHEETAH_SSH_PUBKEY" ]; then
  mkdir -p "$ST/root/.ssh"; cp "$CHEETAH_SSH_PUBKEY" "$ST/root/.ssh/authorized_keys"
else
  echo "NOTE: set CHEETAH_SSH_PUBKEY to embed a debug SSH public key in initramfs; none embedded"
  mkdir -p "$ST/root/.ssh"; : > "$ST/root/.ssh/authorized_keys"
fi
chmod 700 "$ST/root/.ssh"; chmod 600 "$ST/root/.ssh/authorized_keys"

(cd "$ST" && find . | sort | cpio -o -H newc --owner=0:0 --quiet) | lz4 -l -9 -q > "$UWORK/initramfs.cpio.lz4"
ls -l "$UWORK/initramfs.cpio.lz4"
