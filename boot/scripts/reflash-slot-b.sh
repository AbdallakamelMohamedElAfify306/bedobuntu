# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash reflash-slot-b.sh
# Repair slot B after an Android OTA (or anything else) overwrote it: re-flash ONLY the five slot-B boot images.
# userdata is NOT touched, so the Linux system and its data survive. Use --with-userdata for a full reinstall.
set -euo pipefail
. "$(dirname "$0")/common.sh"
[ "${1:-}" = "--with-userdata" ] && exec "$(dirname "$0")/flash-linux.sh" "${@:2}"
sha_check "$OUTDIR" || die "SHA256SUMS mismatch"
pick_phone; check_phone
say "Re-flashing slot B boot images (userdata untouched)"
for p in $BOOT_IMAGES; do safe_flash "${p}_b" "$IMAGES/$p.img"; done
fb --set-active=b; fb reboot
