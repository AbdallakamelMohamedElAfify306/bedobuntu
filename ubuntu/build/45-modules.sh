# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 45-modules.sh
# Install the kernel modules (stripped) into a staging dir, as `bin/omamobile modules` does.
set -euo pipefail
source "$(dirname "$0")/env.sh"
REL=$(cat "$KOUT/include/config/kernel.release")
rm -rf "$WORKDIR/modstage"; mkdir -p "$WORKDIR/modstage"
make -C "$KSRC" ARCH=arm64 LLVM=1 O="$KOUT" INSTALL_MOD_PATH="$WORKDIR/modstage" INSTALL_MOD_STRIP=1 modules_install >/dev/null
rm -f "$WORKDIR/modstage/lib/modules/$REL/build" "$WORKDIR/modstage/lib/modules/$REL/source"
echo "$REL" > "$WORKDIR/modstage/RELEASE"
du -sh "$WORKDIR/modstage"; find "$WORKDIR/modstage/lib/modules/$REL" -name '*.ko*' | wc -l
