# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 20-kernel.sh
# Build the Omarchy Mobile kernel (omamobile-int) exactly as bin/omamobile kernel does:
# arm64 defconfig + kernel/configs/omamobile.config, LLVM=1. Resumable (make is incremental).
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$KSRC"
M="make ARCH=arm64 LLVM=1 O=$KOUT"
[ -f "$KOUT/.config" ] || {
  $M defconfig
  scripts/kconfig/merge_config.sh -m -O "$KOUT" "$KOUT/.config" "$OMA/kernel/configs/omamobile.config"
}
$M olddefconfig
$M -j"$JOBS" Image dtbs modules
$M kernelrelease > "$KOUT/release.txt"
echo "KERNEL BUILD DONE $(cat $KOUT/release.txt)"
